"use client";
import dynamic from "next/dynamic";
const Workspace = dynamic(() => import("./workspace"), { ssr: false, loading: () => <div className="pg-loading"><h1>Playground</h1><p>Preparing the editor…</p></div> });
export function PlaygroundLoader() { return <Workspace />; }
