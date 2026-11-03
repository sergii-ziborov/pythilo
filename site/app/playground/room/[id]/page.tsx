import type { Metadata } from "next";
import { PlaygroundLoader } from "@/components/playground/loader";
import "../../playground.css";
export const metadata: Metadata = { title: "Shared room", robots: { index: false, follow: false }, referrer: "no-referrer" };
export default function PlaygroundRoomPage() { return <PlaygroundLoader />; }
