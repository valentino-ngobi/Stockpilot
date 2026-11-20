[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Run only against the disposable Supabase project named below. This script
# creates fictional audit data which is intentionally left in that disposable
# database; it never performs cleanup through append-only inventory tables.
$testProjectId = 'stockpilotm2test20261120'
$databaseContainer = 'supabase_db_stockpilotm2test20261120'
$databaseHost = '127.0.0.1'
$databasePort = 56322
$databaseName = 'postgres'
$databaseUser = 'postgres'
$requiredMigration = '202611210001'
$passwordVariable = 'STOCKPILOT_ISOLATED_DB_PASSWORD'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required for safe argument-list based process launching.'
}

$dockerCommand = Get-Command docker -ErrorAction Stop
$psqlCommand = Get-Command psql -ErrorAction SilentlyContinue
$useContainerPsql = $null -eq $psqlCommand
if ($useContainerPsql) {
    $databaseHost = 'host.docker.internal'
}
$dockerContext = & $dockerCommand.Source context show
if ($LASTEXITCODE -ne 0 -or "$dockerContext".Trim() -ne 'desktop-linux') {
    throw 'Select the verified desktop-linux Docker context before running isolated concurrency checks.'
}
$databasePassword = $null
if (-not $useContainerPsql) {
    $databasePassword = [Environment]::GetEnvironmentVariable($passwordVariable)
    if ([string]::IsNullOrEmpty($databasePassword)) {
        throw "Set $passwordVariable in the current process environment before running this isolated test."
    }
}

$dockerState = & $dockerCommand.Source inspect --format '{{.State.Status}}|{{index .Config.Labels "com.docker.compose.project"}}' $databaseContainer
if ($LASTEXITCODE -ne 0) {
    throw "Cannot inspect the expected isolated database container $databaseContainer."
}
$dockerParts = "$dockerState".Trim().Split('|', 2)
if ($dockerParts.Count -ne 2 -or $dockerParts[0] -ne 'running' -or $dockerParts[1] -ne $testProjectId) {
    throw 'The expected isolated Supabase database container is not running under the required project ID.'
}

$publishedPort = & $dockerCommand.Source port $databaseContainer '5432/tcp'
if ($LASTEXITCODE -ne 0 -or -not ($publishedPort | Where-Object { "$_".Trim() -match ':(56322)$' })) {
    throw 'The isolated database container is not published on the required host port 56322.'
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("stockpilot-phase2-concurrency-" + [guid]::NewGuid().ToString('N'))
$resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
$resolvedSystemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not $resolvedTemporaryRoot.StartsWith(
    $resolvedSystemTempRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'The temporary SQL directory resolved outside the system temporary directory.'
}
[void][IO.Directory]::CreateDirectory($temporaryRoot)
$oldPgPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD')
if (-not $useContainerPsql) {
    [Environment]::SetEnvironmentVariable('PGPASSWORD', $databasePassword)
}

function New-SqlFile {
    param([string]$Name, [string]$Sql)
    $path = Join-Path $temporaryRoot $Name
    [IO.File]::WriteAllText($path, $Sql, [Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-PsqlFile {
    param([string]$Path)
    $session = Start-PsqlSession -Name 'single-query' -Path $Path
    $result = @(Wait-PsqlSessions -Sessions @($session))[0]
    if ($result.ExitCode -ne 0) {
        throw "psql failed with exit code $($result.ExitCode). $($result.Stderr)"
    }
    return @($result.Stdout -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Start-PsqlSession {
    param([string]$Name, [string]$Path)
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    if ($useContainerPsql) {
        $processInfo.FileName = $dockerCommand.Source
    } else {
        $processInfo.FileName = $psqlCommand.Source
    }
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardInput = $useContainerPsql
    if ($useContainerPsql) {
        $arguments = @(
            'exec', '-i', $databaseContainer, 'sh', '-lc',
            'test -n "$POSTGRES_PASSWORD" && PGPASSWORD="$POSTGRES_PASSWORD" exec psql --no-psqlrc -X --quiet --tuples-only --no-align --set ON_ERROR_STOP=1 --host host.docker.internal --port 56322 --username postgres --dbname postgres'
        )
    } else {
        $arguments = @(
            '--no-psqlrc', '-X', '--quiet', '--tuples-only', '--no-align',
            '--set', 'ON_ERROR_STOP=1',
            '--host', $databaseHost, '--port', "$databasePort",
            '--username', $databaseUser, '--dbname', $databaseName,
            '--file', $Path
        )
    }
    foreach ($argument in $arguments) {
        [void]$processInfo.ArgumentList.Add($argument)
    }
    if (-not $useContainerPsql) {
        $processInfo.Environment['PGPASSWORD'] = $databasePassword
    }
    $process = [Diagnostics.Process]::Start($processInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($useContainerPsql) {
        $process.StandardInput.Write([IO.File]::ReadAllText($Path))
        $process.StandardInput.Close()
    }
    return [pscustomobject]@{
        Name = $Name
        Process = $process
        Stdout = $stdoutTask
        Stderr = $stderrTask
    }
}

function Wait-PsqlSessions {
    param([object[]]$Sessions)
    foreach ($session in $Sessions) {
        $session.Process.WaitForExit()
    }
    foreach ($session in $Sessions) {
        [pscustomobject]@{
            Name = $session.Name
            ExitCode = $session.Process.ExitCode
            Stdout = $session.Stdout.Result.Trim()
            Stderr = $session.Stderr.Result.Trim()
        }
    }
}

function New-DeviceJson {
    param([string]$VariantId, [string]$Imei, [decimal]$LineAmount)
    $device = @{
        line_number = 1
        variant_id = $VariantId
        original_line_amount = $LineAmount
        identifiers = @(@{
            identifier_type = 'imei1'
            raw_value = $Imei
            is_primary = $true
        })
    }
    return ConvertTo-Json -InputObject @($device) -Depth 8 -Compress
}

function New-ReceiptSql {
    param(
        [string]$ActorId,
        [string]$ShopId,
        [string]$BranchId,
        [string]$Key,
        [string]$Reference,
        [string]$Currency,
        [decimal]$Amount,
        [string]$DeviceJson,
        [bool]$PendingFx,
        [string]$RateSnapshotId = $null,
        [string]$ApplicationName = $null
    )
    $deviceLiteral = "'" + $DeviceJson.Replace("'", "''") + "'::jsonb"
    $pendingText = if ($PendingFx) { 'true' } else { 'false' }
    $currencyLiteral = if ($Currency) { "'$Currency'" } else { 'null' }
    $amountLiteral = if ($Currency) { $Amount.ToString([Globalization.CultureInfo]::InvariantCulture) } else { 'null' }
    $rateSnapshotLiteral = if ($RateSnapshotId) { "'$RateSnapshotId'::uuid" } else { 'null' }
    $applicationNameSql = if ($ApplicationName) { "set application_name = '$ApplicationName';" } else { '' }
    $rateValidityCheck = ''
    if ($RateSnapshotId) {
        $rateValidityCheck = @"
select (snapshot.valid_until > clock_timestamp()) as fx_rate_valid_before_rpc
from public.exchange_rate_snapshots as snapshot
where snapshot.id = '$RateSnapshotId' \gset
\if :fx_rate_valid_before_rpc
\echo STOCKPILOT_FX_RATE_VALID_BEFORE_RPC
\else
\echo STOCKPILOT_FX_RATE_EXPIRED_BEFORE_RPC
\quit 3
\endif
"@
    }
    return @"
\set QUIET 1
$applicationNameSql
select pg_sleep(1);
set role authenticated;
$rateValidityCheck
with auth_claim as materialized (
  select set_config('request.jwt.claim.sub', '$ActorId', true)
)
select public.receive_serialized_inventory(
  '$ShopId', '$BranchId', '$Key', 'supplier_invoice',
  'Fictional concurrency supplier', '$Reference', $currencyLiteral,
  $amountLiteral, $deviceLiteral, $rateSnapshotLiteral, null, null, null, null, $(if ($PendingFx) { 'true' } else { 'false' })
)
from auth_claim;
"@
}

function New-ReleaseSql {
    param([string]$ActorId, [string]$ShopId, [string]$BranchId, [string]$ReceiptId, [string]$Key, [string]$RateSnapshotId)
    return @"
\set QUIET 1
select pg_sleep(1);
set role authenticated;
with auth_claim as materialized (
  select set_config('request.jwt.claim.sub', '$ActorId', true)
)
select public.release_pending_fx_receipt(
  '$ShopId', '$BranchId', '$ReceiptId', '$Key', '$RateSnapshotId'
)
from auth_claim;
"@
}

try {
    $migrationCheckPath = New-SqlFile -Name 'verify_target.sql' -Sql @"
\set QUIET 1
select count(*) = 5
from supabase_migrations.schema_migrations
where version in (
  '202611190001',
  '202611190002',
  '202611190003',
  '202611200001',
  '$requiredMigration'
);
"@
    $migrationCheck = Invoke-PsqlFile -Path $migrationCheckPath
    if ($migrationCheck.Count -ne 1 -or $migrationCheck[0] -ne 't') {
        throw "The complete Milestone 1, Milestone 2 foundation, and new migration chain is not recorded on isolated host port $databasePort."
    }

    $shopId = ([guid]::NewGuid()).ToString()
    $branchId = ([guid]::NewGuid()).ToString()
    $ownerId = ([guid]::NewGuid()).ToString()
    $variantId = ([guid]::NewGuid()).ToString()
    $rateSnapshotId = ([guid]::NewGuid()).ToString()
    $productId = ([guid]::NewGuid()).ToString()
    $rateSource = 'fictional concurrency test source'
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $expiry = [DateTimeOffset]::UtcNow.AddDays(1).ToString('o')
    $ownerEmail = "phase2-concurrency-$($ownerId.Replace('-', '')).example.test@example.test"

    $fixtureSql = @"
\set QUIET 1
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '$ownerId', 'authenticated', 'authenticated', '$ownerEmail', '',
  clock_timestamp(), '{}'::jsonb, '{}'::jsonb, clock_timestamp(), clock_timestamp()
);
insert into public.shops (id, name, created_by)
values ('$shopId', 'Fictional concurrency test shop', '$ownerId');
insert into public.shop_memberships (shop_id, user_id, role, status, created_by)
values ('$shopId', '$ownerId', 'owner', 'active', '$ownerId');
insert into public.branches (id, shop_id, name, is_primary, is_active, created_by)
values ('$branchId', '$shopId', 'Concurrency test branch', true, true, '$ownerId');
set role authenticated;
with auth_claim as materialized (
  select set_config('request.jwt.claim.sub', '$ownerId', true)
)
select public.configure_shop_operating_currency('$shopId', 'USD')
from auth_claim;
reset role;
insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values (
  '$productId', '$shopId', 'smartphone', 'serialized',
  'Fictional concurrency device', '$ownerId', '$ownerId'
);
insert into public.product_variants (
  id, shop_id, product_id, created_by, updated_by
) values ('$variantId', '$shopId', '$productId', '$ownerId', '$ownerId');
insert into public.exchange_rate_snapshots (
  id, from_currency_code, to_currency_code, rate_to_currency,
  rate_source, observed_at, fetched_at, valid_until
) values (
  '$rateSnapshotId', 'CAD', 'USD', 0.5, '$rateSource',
  '$timestamp'::timestamptz, '$timestamp'::timestamptz, '$expiry'::timestamptz
);
"@
    $fixturePath = New-SqlFile -Name 'seed_fictional_fixture.sql' -Sql $fixtureSql
    [void](Invoke-PsqlFile -Path $fixturePath)

    $baseImei = (Get-Random -Minimum 100000000000000 -Maximum 999999999999999).ToString()
    $duplicateKey = "concurrency-duplicate-$([guid]::NewGuid().ToString('N'))"
    $duplicateRef = "DUP-$([guid]::NewGuid().ToString('N'))"
    $deviceJson = New-DeviceJson -VariantId $variantId -Imei $baseImei -LineAmount 0
    $duplicateSql = New-ReceiptSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -Key $duplicateKey -Reference $duplicateRef -Currency 'USD' -Amount 0 -DeviceJson $deviceJson -PendingFx $false
    $duplicatePath = New-SqlFile -Name 'duplicate_receipt.sql' -Sql $duplicateSql
    $duplicateSessions = @(
        Start-PsqlSession -Name 'duplicate-a' -Path $duplicatePath
        Start-PsqlSession -Name 'duplicate-b' -Path $duplicatePath
    )
    $duplicateResults = @(Wait-PsqlSessions -Sessions $duplicateSessions)
    $duplicateFailures = @($duplicateResults | Where-Object { $_.ExitCode -ne 0 })
    if ($duplicateFailures.Count -ne 0) {
        throw 'Concurrent identical receipt requests did not both succeed.'
    }
    $duplicateIds = @($duplicateResults | ForEach-Object {
        [regex]::Matches($_.Stdout, '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}') |
            ForEach-Object Value
    } | Where-Object { $_ })
    if ($duplicateIds.Count -ne 2 -or $duplicateIds[0] -ne $duplicateIds[1]) {
        throw 'Concurrent identical receipt requests did not return the same receipt ID.'
    }

    $claimImei = (Get-Random -Minimum 100000000000000 -Maximum 999999999999999).ToString()
    while ($claimImei -eq $baseImei) {
        $claimImei = (Get-Random -Minimum 100000000000000 -Maximum 999999999999999).ToString()
    }
    $claimJson = New-DeviceJson -VariantId $variantId -Imei $claimImei -LineAmount 0
    $claimA = New-ReceiptSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -Key "claim-a-$([guid]::NewGuid().ToString('N'))" -Reference "CLAIM-A-$([guid]::NewGuid().ToString('N'))" -Currency 'USD' -Amount 0 -DeviceJson $claimJson -PendingFx $false
    $claimB = New-ReceiptSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -Key "claim-b-$([guid]::NewGuid().ToString('N'))" -Reference "CLAIM-B-$([guid]::NewGuid().ToString('N'))" -Currency 'USD' -Amount 0 -DeviceJson $claimJson -PendingFx $false
    $claimPathA = New-SqlFile -Name 'identifier_claim_a.sql' -Sql $claimA
    $claimPathB = New-SqlFile -Name 'identifier_claim_b.sql' -Sql $claimB
    $claimSessions = @(
        Start-PsqlSession -Name 'identifier-a' -Path $claimPathA
        Start-PsqlSession -Name 'identifier-b' -Path $claimPathB
    )
    $claimResults = @(Wait-PsqlSessions -Sessions $claimSessions)
    $claimSuccessCount = @($claimResults | Where-Object { $_.ExitCode -eq 0 }).Count
    $claimFailureCount = @($claimResults | Where-Object { $_.ExitCode -ne 0 }).Count
    if ($claimSuccessCount -ne 1 -or $claimFailureCount -ne 1) {
        throw 'Competing claims for the same normalized identifier did not have exactly one winner.'
    }
    $claimFailure = $claimResults | Where-Object { $_.ExitCode -ne 0 } | Select-Object -First 1
    if ($claimFailure.Stderr -notmatch 'duplicate key value violates unique constraint') {
        throw 'The losing identifier claim failed for a reason other than the shop-wide uniqueness constraint.'
    }

    $pendingImei = (Get-Random -Minimum 100000000000000 -Maximum 999999999999999).ToString()
    $pendingJson = New-DeviceJson -VariantId $variantId -Imei $pendingImei -LineAmount 1
    $pendingKey = "pending-$([guid]::NewGuid().ToString('N'))"
    $pendingRef = "PENDING-$([guid]::NewGuid().ToString('N'))"
    $pendingSql = New-ReceiptSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -Key $pendingKey -Reference $pendingRef -Currency 'CAD' -Amount 1 -DeviceJson $pendingJson -PendingFx $true
    $pendingPath = New-SqlFile -Name 'seed_pending_receipt.sql' -Sql $pendingSql
    $pendingOutput = Invoke-PsqlFile -Path $pendingPath
    $pendingIds = @($pendingOutput | Where-Object { $_ -match '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' })
    if ($pendingIds.Count -ne 1) {
        throw 'Could not capture the synthetic Pending-FX receipt ID.'
    }
    $releaseKeyA = "release-a-$([guid]::NewGuid().ToString('N'))"
    $releaseKeyB = "release-b-$([guid]::NewGuid().ToString('N'))"
    $releasePathA = New-SqlFile -Name 'release_a.sql' -Sql (New-ReleaseSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -ReceiptId $pendingIds[0] -Key $releaseKeyA -RateSnapshotId $rateSnapshotId)
    $releasePathB = New-SqlFile -Name 'release_b.sql' -Sql (New-ReleaseSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -ReceiptId $pendingIds[0] -Key $releaseKeyB -RateSnapshotId $rateSnapshotId)
    $releaseSessions = @(
        Start-PsqlSession -Name 'release-a' -Path $releasePathA
        Start-PsqlSession -Name 'release-b' -Path $releasePathB
    )
    $releaseResults = @(Wait-PsqlSessions -Sessions $releaseSessions)
    $releaseSuccessCount = @($releaseResults | Where-Object { $_.ExitCode -eq 0 }).Count
    $releaseFailureCount = @($releaseResults | Where-Object { $_.ExitCode -ne 0 }).Count
    if ($releaseSuccessCount -ne 1 -or $releaseFailureCount -ne 1) {
        throw 'Competing Pending-FX releases did not have exactly one winner.'
    }
    $releaseFailure = $releaseResults | Where-Object { $_.ExitCode -ne 0 } | Select-Object -First 1
    if ($releaseFailure.Stderr -notmatch 'partially or already resolved') {
        throw 'The losing Pending-FX release failed for a reason other than the already-resolved receipt guard.'
    }

    # Hold the shop-settings row while a valid system-rate receipt starts.
    # The rate expires before the lock is released; the RPC must reject it
    # using the refreshed post-lock wall-clock decision time.
    $expiringSnapshotId = ([guid]::NewGuid()).ToString()
    $expiryKey = "fx-expiry-$([guid]::NewGuid().ToString('N'))"
    $expiryRef = "FX-EXPIRY-$([guid]::NewGuid().ToString('N'))"
    $expiryImei = (Get-Random -Minimum 100000000000000 -Maximum 999999999999999).ToString()
    $expiryDeviceJson = New-DeviceJson -VariantId $variantId -Imei $expiryImei -LineAmount 1
    $holderAppName = "stockpilot_fx_lock_$([guid]::NewGuid().ToString('N'))"
    $holderPath = New-SqlFile -Name 'hold_shop_settings_lock.sql' -Sql @"
\set QUIET 1
set application_name = '$holderAppName';
begin;
select shop_id from public.shop_settings where shop_id = '$shopId' for update;
    select pg_sleep(25);
commit;
"@
    $holderSession = Start-PsqlSession -Name 'fx-settings-lock-holder' -Path $holderPath
    $holderReady = $false
    $holderDeadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    $holderProbePath = New-SqlFile -Name 'verify_shop_settings_lock.sql' -Sql @"
\set QUIET 1
select count(*) = 1
from pg_catalog.pg_stat_activity
where application_name = '$holderAppName'
  and state = 'active'
  and wait_event = 'PgSleep';
"@
    while ([DateTimeOffset]::UtcNow -lt $holderDeadline -and -not $holderReady) {
        $holderProbe = Invoke-PsqlFile -Path $holderProbePath
        $holderReady = $holderProbe.Count -eq 1 -and $holderProbe[0] -eq 't'
        if (-not $holderReady) {
            Start-Sleep -Milliseconds 150
        }
    }
    if (-not $holderReady) {
        $holderResult = @(Wait-PsqlSessions -Sessions @($holderSession))[0]
        throw "Could not confirm the isolated lock holder acquired the shop-settings row. $($holderResult.Stderr)"
    }

    $expirySnapshotPath = New-SqlFile -Name 'insert_expiring_rate_snapshot.sql' -Sql @"
\set QUIET 1
insert into public.exchange_rate_snapshots (
  id, from_currency_code, to_currency_code, rate_to_currency,
  rate_source, observed_at, fetched_at, valid_until
) values (
  '$expiringSnapshotId', 'CAD', 'USD', 0.5,
  'fictional lock-wait expiry test', clock_timestamp(), clock_timestamp(),
  clock_timestamp() + interval '15 seconds'
);
"@
    [void](Invoke-PsqlFile -Path $expirySnapshotPath)
    $expiryReceiverAppName = "stockpilot_fx_receiver_$([guid]::NewGuid().ToString('N'))"
    $expiryReceiptSql = New-ReceiptSql -ActorId $ownerId -ShopId $shopId -BranchId $branchId -Key $expiryKey -Reference $expiryRef -Currency 'CAD' -Amount 1 -DeviceJson $expiryDeviceJson -PendingFx $false -RateSnapshotId $expiringSnapshotId -ApplicationName $expiryReceiverAppName
    $expiryReceiptPath = New-SqlFile -Name 'receipt_with_expiring_rate.sql' -Sql $expiryReceiptSql
    $expiryReceiptSession = Start-PsqlSession -Name 'fx-expiring-receipt' -Path $expiryReceiptPath
    $expiryWaitProbePath = New-SqlFile -Name 'verify_fx_wait_while_rate_valid.sql' -Sql @"
\set QUIET 1
select exists (
  select 1 from pg_catalog.pg_stat_activity
  where application_name = '$expiryReceiverAppName'
    and state = 'active'
    and wait_event_type = 'Lock'
)
and exists (
  select 1 from public.exchange_rate_snapshots
  where id = '$expiringSnapshotId'
    and valid_until > clock_timestamp()
);
"@
    $receiverWaitingWhileValid = $false
    $receiverWaitDeadline = [DateTimeOffset]::UtcNow.AddSeconds(8)
    while ([DateTimeOffset]::UtcNow -lt $receiverWaitDeadline -and -not $receiverWaitingWhileValid) {
        $waitProbe = Invoke-PsqlFile -Path $expiryWaitProbePath
        $receiverWaitingWhileValid = $waitProbe.Count -eq 1 -and $waitProbe[0] -eq 't'
        if (-not $receiverWaitingWhileValid) {
            Start-Sleep -Milliseconds 100
        }
    }
    if (-not $receiverWaitingWhileValid) {
        $failedReceiver = @(Wait-PsqlSessions -Sessions @($expiryReceiptSession))[0]
        $holderResult = @(Wait-PsqlSessions -Sessions @($holderSession))[0]
        throw "Could not confirm the receive RPC was lock-waiting while the rate remained valid. Receiver stderr: $($failedReceiver.Stderr). Lock-holder stderr: $($holderResult.Stderr)"
    }
    $expiryReceiptResult = @(Wait-PsqlSessions -Sessions @($expiryReceiptSession))[0]
    $holderResult = @(Wait-PsqlSessions -Sessions @($holderSession))[0]
    if ($holderResult.ExitCode -ne 0) {
        throw "The isolated shop-settings lock holder failed. $($holderResult.Stderr)"
    }
    if (($expiryReceiptResult.ExitCode -eq 0) -or
        ($expiryReceiptResult.Stdout -notmatch 'STOCKPILOT_FX_RATE_VALID_BEFORE_RPC') -or
        ($expiryReceiptResult.Stderr -notmatch 'exchange-rate snapshot is missing, expired, or has the wrong currency direction')) {
        throw "The lock-wait FX expiry regression did not reject a rate that was valid before the RPC call. Exit=$($expiryReceiptResult.ExitCode); stderr=$($expiryReceiptResult.Stderr)"
    }

    $expiryVerifyPath = New-SqlFile -Name 'verify_fx_expiry_rejection.sql' -Sql @"
\set QUIET 1
select (
  (select valid_until <= clock_timestamp()
   from public.exchange_rate_snapshots where id = '$expiringSnapshotId')
  and not exists (
    select 1 from public.inventory_receipts
    where shop_id = '$shopId' and supplier_invoice_reference = '$expiryRef'
  )
  and not exists (
    select 1 from public.inventory_operations
    where shop_id = '$shopId' and actor_id = '$ownerId' and idempotency_key = '$expiryKey'
  )
);
"@
    $expiryVerification = Invoke-PsqlFile -Path $expiryVerifyPath
    if ($expiryVerification.Count -ne 1 -or $expiryVerification[0] -ne 't') {
        throw 'The expired-rate rejection did not leave receipt or operation records behind.'
    }

    $verifySql = @"
\set QUIET 1
select (
  (select count(*) = 1 from public.inventory_receipts
   where shop_id = '$shopId' and supplier_invoice_reference = '$duplicateRef')
  and
  (select count(*) = 1 from public.inventory_operations
   where shop_id = '$shopId' and actor_id = '$ownerId'
     and idempotency_key = '$duplicateKey')
  and
  (select count(*) = 1 from public.serialized_inventory item
   join public.inventory_receipt_lines line
     on line.shop_id = item.shop_id
    and line.variant_id = item.variant_id
    and line.serialized_inventory_id = item.id
   where line.receipt_id = (
     select id from public.inventory_receipts
     where shop_id = '$shopId' and supplier_invoice_reference = '$duplicateRef'
   ))
  and
  (select count(*) = 1 from public.serialized_identifiers
   where shop_id = '$shopId' and normalized_value = '$claimImei')
  and
  (select count(*) = 1 from public.inventory_fx_resolutions resolution
   join public.inventory_receipt_lines line
     on line.shop_id = resolution.shop_id
    and line.branch_id = resolution.branch_id
    and line.id = resolution.receipt_line_id
   where line.receipt_id = '$($pendingIds[0])')
  and
  (select count(*) = 2 from public.inventory_movements
   where fx_resolution_id in (
     select resolution.id
     from public.inventory_fx_resolutions resolution
     join public.inventory_receipt_lines line
       on line.shop_id = resolution.shop_id
      and line.branch_id = resolution.branch_id
      and line.id = resolution.receipt_line_id
     where line.receipt_id = '$($pendingIds[0])'
   ))
  and
  (select count(*) = 1 from public.serialized_inventory item
   join public.inventory_receipt_lines line
     on line.shop_id = item.shop_id
    and line.variant_id = item.variant_id
    and line.serialized_inventory_id = item.id
   where line.receipt_id = '$($pendingIds[0])'
     and item.valuation_status = 'known_cost'
     and item.availability_status = 'available')
);
"@
    $verifyPath = New-SqlFile -Name 'verify_concurrency_results.sql' -Sql $verifySql
    $verification = Invoke-PsqlFile -Path $verifyPath
    if ($verification.Count -ne 1 -or $verification[0] -ne 't') {
        throw 'Concurrency postconditions failed.'
    }

    Write-Output ("Verified isolated project {0} at {1}, port {2}." -f $testProjectId, $databaseHost, $databasePort)
    Write-Output 'Concurrent duplicate receipt: both sessions returned the same receipt ID; one operation exists.'
    Write-Output 'Competing identifier claims: exactly one session succeeded; one identifier exists.'
    Write-Output 'Competing FX releases: exactly one session succeeded; one resolution and two movements exist.'
    Write-Output 'Lock-wait FX expiry: pg_stat_activity confirmed the receive RPC was blocked on the shop-settings lock while its rate was still valid; it expired before unlock and was rejected without receipt or operation records.'
    Write-Output 'Fictional test records remain in the disposable database.'
}
finally {
    [Environment]::SetEnvironmentVariable('PGPASSWORD', $oldPgPassword)
    if ($resolvedTemporaryRoot.StartsWith(
        $resolvedSystemTempRoot,
        [StringComparison]::OrdinalIgnoreCase
    ) -and (Test-Path -LiteralPath $resolvedTemporaryRoot)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
