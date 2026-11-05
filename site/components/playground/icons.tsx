import type { ReactNode } from "react";

/** 16 px line icons, drawn on a 16 grid with a 1.5 stroke, in the current text colour. */
const paths: Record<string, ReactNode> = {
  "new-file": <><path d="M9 1.75H4.5a1.25 1.25 0 0 0-1.25 1.25v10A1.25 1.25 0 0 0 4.5 14.25h3" /><path d="M9 1.75 12.75 5.5V8" /><path d="M9 1.75V5.5h3.75" /><path d="M12 10.25v4.5M9.75 12.5h4.5" /></>,
  "new-folder": <><path d="M1.75 12.5V3.75c0-.55.45-1 1-1h3.1l1.6 1.75h5.8c.55 0 1 .45 1 1V8" /><path d="M1.75 12.5c0 .55.45 1 1 1H8" /><path d="M12 10.25v4.5M9.75 12.5h4.5" /></>,
  upload: <><path d="M8 10.5V2.25M4.75 5.25 8 2l3.25 3.25" /><path d="M2.25 10.25v2.5c0 .55.45 1 1 1h9.5c.55 0 1-.45 1-1v-2.5" /></>,
  download: <><path d="M8 2v8.25M4.75 7 8 10.25 11.25 7" /><path d="M2.25 10.25v2.5c0 .55.45 1 1 1h9.5c.55 0 1-.45 1-1v-2.5" /></>,
  collapse: <><path d="M4.5 6.5 8 3l3.5 3.5M4.5 13 8 9.5l3.5 3.5" /></>,
  rename: <><path d="M10.5 2.5 13.5 5.5 6 13H3v-3z" /><path d="M9 4l3 3" /></>,
  trash: <><path d="M2.5 4h11M6.25 4V2.5h3.5V4M4 4l.6 9.1c.05.5.45.9 1 .9h4.8c.55 0 .95-.4 1-.9L12 4" /></>,
  more: <><circle cx="3.5" cy="8" r=".9" fill="currentColor" /><circle cx="8" cy="8" r=".9" fill="currentColor" /><circle cx="12.5" cy="8" r=".9" fill="currentColor" /></>,
  play: <path d="M4.5 2.6c0-.6.65-.95 1.15-.63l7.6 4.9c.47.3.47.97 0 1.27l-7.6 4.9c-.5.32-1.15-.04-1.15-.63z" fill="currentColor" stroke="none" />,
  stop: <rect x="3.5" y="3.5" width="9" height="9" rx="1.5" fill="currentColor" stroke="none" />,
  share: <><path d="M8 10V2M5 5l3-3 3 3" /><path d="M5.5 7.5H4.25c-.55 0-1 .45-1 1v4.25c0 .55.45 1 1 1h7.5c.55 0 1-.45 1-1V8.5c0-.55-.45-1-1-1H10.5" /></>,
  link: <><path d="M6.75 9.25a2.75 2.75 0 0 0 3.9 0l2.1-2.1a2.75 2.75 0 0 0-3.9-3.9l-.85.85" /><path d="M9.25 6.75a2.75 2.75 0 0 0-3.9 0l-2.1 2.1a2.75 2.75 0 0 0 3.9 3.9l.85-.85" /></>,
  copy: <><rect x="5.25" y="5.25" width="8.5" height="8.5" rx="1.25" /><path d="M10.75 5.25V3.5c0-.7-.55-1.25-1.25-1.25H3.5c-.7 0-1.25.55-1.25 1.25v6c0 .7.55 1.25 1.25 1.25h1.75" /></>,
  check: <path d="M3 8.5 6.25 11.75 13 4.5" />,
  close: <path d="M4 4l8 8M12 4l-8 8" />,
  phone: <><rect x="4.25" y="1.5" width="7.5" height="13" rx="1.75" /><path d="M7 12.25h2" /></>,
  folder: <path d="M1.75 12.25V3.75c0-.55.45-1 1-1h3.1l1.6 1.75h5.8c.55 0 1 .45 1 1v6.75c0 .55-.45 1-1 1H2.75c-.55 0-1-.45-1-1z" />,
  "folder-open": <><path d="M1.75 12.25V3.75c0-.55.45-1 1-1h3.1l1.6 1.75h4.8c.55 0 1 .45 1 1v1" /><path d="M1.75 12.25 3.6 7.3c.15-.4.5-.55.95-.55h9.2c.45 0 .75.45.6.85l-1.7 4.5c-.15.4-.5.65-.95.65H2.75c-.55 0-1-.45-1-1z" /></>,
  chevron: <path d="M6 4l4 4-4 4" />,
  search: <><circle cx="7" cy="7" r="4.25" /><path d="M10.25 10.25 13.5 13.5" /></>,
  files: <><path d="M9 1.75H4.5c-.7 0-1.25.55-1.25 1.25v10c0 .7.55 1.25 1.25 1.25h7c.7 0 1.25-.55 1.25-1.25V5.5z" /><path d="M9 1.75V5.5h3.75" /></>,
  code: <path d="M5.5 4 1.75 8l3.75 4M10.5 4l3.75 4-3.75 4" />,
  terminal: <><rect x="1.75" y="2.75" width="12.5" height="10.5" rx="1.5" /><path d="M4.5 6.25 6.75 8 4.5 9.75M8.5 10h3" /></>,
  keyboard: <><rect x="1.5" y="3.75" width="13" height="8.5" rx="1.5" /><path d="M4 6.5h.01M6.5 6.5h.01M9 6.5h.01M11.5 6.5h.01M5 9.5h6" /></>,
  clear: <><circle cx="8" cy="8" r="5.75" /><path d="M4 12 12 4" /></>,
  open: <><path d="M9.5 2.25h4.25V6.5M13.5 2.5 7.5 8.5" /><path d="M12 9.5v3.25c0 .55-.45 1-1 1H3.25c-.55 0-1-.45-1-1V5c0-.55.45-1 1-1H6.5" /></>,
  sparkle: <path d="M8 1.75c.4 2.9 1.35 3.85 4.25 4.25C9.35 6.4 8.4 7.35 8 10.25 7.6 7.35 6.65 6.4 3.75 6 6.65 5.6 7.6 4.65 8 1.75zM12.25 10c.2 1.3.6 1.7 1.9 1.9-1.3.2-1.7.6-1.9 1.9-.2-1.3-.6-1.7-1.9-1.9 1.3-.2 1.7-.6 1.9-1.9z" />,
  drafts: <><path d="M2.25 5.25h11.5v7.5c0 .55-.45 1-1 1h-9.5c-.55 0-1-.45-1-1z" /><path d="M1.75 2.25h12.5v3H1.75zM6.25 8h3.5" /></>,
  plus: <path d="M8 3v10M3 8h10" />,
  entry: <path d="M5.5 3.6c0-.5.55-.8.95-.53l5.3 3.9c.35.26.35.8 0 1.06l-5.3 3.9c-.4.27-.95-.03-.95-.53z" fill="currentColor" stroke="none" />,
  people: <><circle cx="6" cy="5.5" r="2.25" /><path d="M2 13c.4-2.2 1.9-3.5 4-3.5s3.6 1.3 4 3.5" /><path d="M10.5 3.5a2.25 2.25 0 0 1 0 4.25M12 9.75c1.05.45 1.75 1.5 2 3.25" /></>,
  end: <><circle cx="8" cy="8" r="5.75" /><path d="M5.75 5.75h4.5v4.5h-4.5z" /></>,
};

export type IconName = keyof typeof paths;

export function Icon({ name, size = 16, className }: { name: IconName; size?: number; className?: string }) {
  return <svg className={className ? `pg-icon ${className}` : "pg-icon"} width={size} height={size} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">{paths[name]}</svg>;
}
