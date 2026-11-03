import type { Metadata } from "next";
import { PlaygroundLoader } from "@/components/playground/loader";
import "./playground.css";
export const metadata: Metadata = { title: "Python Playground", description: "Write Python, run it in your browser with Pyodide, and share a live room with people, AI clients or the Pythilo iPhone app." };
export default function PlaygroundPage() { return <PlaygroundLoader />; }
