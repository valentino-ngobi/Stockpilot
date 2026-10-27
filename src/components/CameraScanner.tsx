import { useEffect, useRef, useState } from "react";
import { BrowserMultiFormatReader } from "@zxing/browser";
import { Camera, CheckCircle2, LoaderCircle, X } from "lucide-react";

type CameraScannerProps = {
  onDetected: (value: string) => void;
  onClose: () => void;
  title?: string;
};

export default function CameraScanner({ onDetected, onClose, title = "Scan device identifier" }: CameraScannerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [status, setStatus] = useState("Requesting camera access…");
  const [error, setError] = useState("");
  const [scannedValue, setScannedValue] = useState("");

  useEffect(() => {
    let disposed = false;
    let controls: { stop: () => void } | undefined;
    const reader = new BrowserMultiFormatReader();

    async function startScanner() {
      if (!videoRef.current) return;
      try {
        setStatus("Allow camera access when your browser asks.");
        const activeControls = await reader.decodeFromVideoDevice(
          undefined,
          videoRef.current,
          (result) => {
            if (!result || disposed) return;
            const value = result.getText().trim();
            if (!value) return;
            setScannedValue(value);
            setStatus("Code detected. Check it before using it.");
            controls?.stop();
            onDetected(value);
          },
        );
        controls = activeControls;
        if (disposed) activeControls.stop();
        else setStatus("Camera ready. Align a barcode or QR code inside the frame.");
      } catch (cause) {
        if (disposed) return;
        const reason = cause instanceof Error ? cause.message : "Camera could not be started.";
        setError(reason);
        setStatus("Camera unavailable");
      }
    }

    void startScanner();
    return () => {
      disposed = true;
      controls?.stop();
    };
  }, [onDetected]);

  return (
    <div className="scanner-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section className="scanner-dialog surface-card" role="dialog" aria-modal="true" aria-labelledby="scanner-title">
        <header className="scanner-header">
          <div className="scanner-heading-icon"><Camera size={19} /></div>
          <div className="scanner-title-copy">
            <h2 id="scanner-title">{title}</h2>
            <p>Barcode and QR scanning</p>
          </div>
          <button className="icon-button" onClick={onClose} aria-label="Close scanner"><X size={18} /></button>
        </header>
        <div className="scanner-viewfinder">
          <video ref={videoRef} className="scanner-video" muted playsInline />
          <div className="scanner-frame" aria-hidden="true"><i /><i /><i /><i /></div>
          <span className="scanner-live-label"><span /> CAMERA ACTIVE</span>
        </div>
        <div className="scanner-status" role="status">
          {scannedValue ? <CheckCircle2 size={16} /> : error ? <Camera size={16} /> : <LoaderCircle size={16} className="scanner-spin" />}
          <span>{error || status}</span>
        </div>
        {error && (
          <div className="scanner-help">
            Check that the page is running on localhost or HTTPS, allow camera permission, and close other apps using the camera. You can always type the identifier manually instead.
          </div>
        )}
        {scannedValue && <div className="scanner-result"><span>Detected value</span><strong>{scannedValue}</strong></div>}
        <footer className="scanner-footer">
          <span>Printed text OCR is a separate feature planned for a later stage.</span>
          <button className="button button-secondary" onClick={onClose}>Close scanner</button>
        </footer>
      </section>
    </div>
  );
}
