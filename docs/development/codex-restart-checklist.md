# StockPilot Codex restart checklist

Use this checklist after restarting Windows or opening a new Codex session. It is a safety and context aid; verify current state rather than assuming services or approvals persisted.

## 1. Resume the local Git checkpoint

Open PowerShell and use the existing repository:

```powershell
Set-Location D:\stockpilot
git status --short --branch
git branch --show-current
git rev-parse HEAD
git log -2 --format="%H %s"
git rev-list --left-right --count origin/main...HEAD
```

Pre-documentation checkpoint recorded on 2026-11-22:

- Branch: `main`
- Local HEAD: `c517e8b7a1f5be6179c77e5da205feedd0480634` (`fix(repairs): restrict staff-readable repair evidence`)
- Previous commit: `d47b266b6e72ba2bdf36da560540f39ac2209478` (`feat(repairs): add secure serialized repair workflows`)
- The worktree was clean before this restart documentation was added.
- At that checkpoint, the two implementation commits above were **not pushed**. A read-only remote check returned `origin/main` at `65a261503dea64c110a91a3d1de7642f8e6e00b4`; local `main` was two commits ahead. This is a historical snapshot, not the current status after the documentation checkpoint. Recheck HEAD and the remote after restart.

Remote verification, if network access is available (read-only):

```powershell
git ls-remote origin refs/heads/main
```

Do not treat a stale local `origin/main` tracking ref as proof of current remote state. Do not reset, rebase, or discard local work. Stage, commit, or push only when the task explicitly authorizes it.

## 2. Read project guidance

Read `AGENTS.md` at the repository root before work. It records the architecture, current backend scope, data invariants, security expectations, and protected database boundaries. Use `git status` to determine the current commit/staging state of these documentation files; do not assume it from this historical checklist.

## 3. Check Docker without changing services

Start Docker Desktop only if a database task requires it. Then use read-only checks:

```powershell
docker context show
docker --context desktop-linux info --format '{{.ServerVersion}}'
docker --context desktop-linux inspect --format '{{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} mounts={{range .Mounts}}{{.Name}}->{{.Destination}} {{end}} ports={{json .NetworkSettings.Ports}}' supabase_db_stockpilotm2repairtest20261122
Test-NetConnection -ComputerName 127.0.0.1 -Port 57322
```

The database container must be the repair-test project, use its expected test volume, be healthy, and publish PostgreSQL only on `127.0.0.1:57322`. A successful TCP check alone does not establish database identity; verify the container, mount, and host binding first. If any check disagrees, stop before running SQL or Supabase commands.

Protected resources that must not be targeted:

- Original StockPilot database: `supabase_db_stockpilot`, port `54322`.
- Older test baseline: `supabase_db_stockpilotm2test20261120`, port `56322`.

Never run `supabase db reset` against either protected database. Do not stop, restart, recreate, or delete their containers or volumes.

## 4. Verify the authorized isolated Supabase target

The authorized test project is `stockpilotm2repairtest20261122`, PostgreSQL port `57322`. Its work directory recorded in the local machine is:

```text
C:\Users\ADMIN\AppData\Local\Temp\stockpilot-m2-phase3db-isolated
```

Before database work, read only the nonsecret project and port settings from:

```text
<isolated work directory>\supabase\config.toml
```

Confirm `project_id = "stockpilotm2repairtest20261122"` and the database port is `57322`. Use the pinned Supabase CLI (`npx --yes supabase@3.2.0`) with this explicit work directory for any authorized operation. Never invoke Supabase commands from `D:\stockpilot` with implicit/default project selection when they could target a database.

Supabase status output may include local keys or credential-bearing URLs. Do not paste raw status/startup output into chat or logs; inspect only redacted project, health, and port fields. If a SQL client is needed, target `127.0.0.1:57322` explicitly and enter any password only at a private interactive prompt.

Database migrations, resets, fixtures, and concurrency tests require a task that authorizes them. The authorized project boundary does not by itself authorize a destructive operation.

## 5. Check tools and run frontend validation when needed

Required tools recorded by the project: Node.js 22.12+, npm, Docker Desktop (`desktop-linux`) for local Supabase work, and Supabase CLI 3.2.0 for database tooling. Check the installed runtime without changing it:

```powershell
node --version
npm --version
```

Existing frontend validation commands:

```powershell
npm test
npx tsc -b --pretty false
npm run build
git diff --check
```

The production build runs TypeScript compilation and Vite. Do not install packages unless the task requires them and the existing lockfile/package setup has been checked.

## 6. Codex permissions after restart

The inspected user Codex config is `C:\Users\ADMIN\.codex\config.toml`. It marks `D:\stockpilot` as a trusted project and sets user-level model preferences. Trust status helps Codex load project configuration; it is not an authorization to bypass the execution sandbox or access protected databases. No persistent `sandbox_mode` or `approval_policy` override was present in the inspected config.

The current execution environment uses workspace-scoped write access and restricted network access. Treat per-session permission grants, network approvals, Docker access, and escalated command approvals as **not guaranteed to survive a Windows restart or new session**. If prompted again, request/approve only the specific operation, target, and scope needed. Do not enable unrestricted command execution, disable sandboxing, or grant access to the protected database containers. If an approval is denied, stop that operation and report the blocker; do not try an alternate path that bypasses the restriction.

## 7. Resume work safely

Continue from local `main` at the HEAD verified after restart, preserving local commits and all files whether pushed or not. Review `AGENTS.md`, then inspect the current Git diff and task-specific files before coding. For database work, complete the isolated-target checks above before any database command. Run the relevant frontend/database validation only when requested and authorized. Ask separately before committing, pushing, deploying, or performing destructive database operations.
