import type { CSSProperties } from "react";
import { learnIcons, type LearnIconName } from "@/lib/learn-icons";

/** Sets the track colour for the element and everything inside it. */
export const accentStyle = (color: string) => ({ "--accent": color }) as CSSProperties;

/** One Learn icon as inline SVG. It takes the text colour and is hidden from screen readers. */
export function LearnIcon({ name, size = 24, className }: { name: LearnIconName; size?: number; className?: string }) {
  return <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false"><path d={learnIcons[name]} /></svg>;
}
