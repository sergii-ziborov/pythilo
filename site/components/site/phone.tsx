import type { Shot } from "@/lib/shots";

/** A screenshot inside a device outline. Phone shots are 600 × 1304, iPad shots 1032 × 1376. */
export function DeviceShot({ shot, eager = false, className = "" }: { shot: Shot; eager?: boolean; className?: string }) {
  return <span className={`device ${shot.device}${className ? ` ${className}` : ""}`}>
    {/* Static, pre-sized WebP files: no image optimiser needed. */}
    {/* eslint-disable-next-line @next/next/no-img-element */}
    <img src={`/shots/${shot.file}.webp`} alt={shot.alt} width={shot.device === "ipad" ? 1032 : 600} height={shot.device === "ipad" ? 1376 : 1304} loading={eager ? "eager" : "lazy"} decoding="async" draggable={false} />
  </span>;
}
