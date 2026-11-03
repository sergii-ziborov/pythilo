import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";

export default function NotFound() {
  return <><SiteHeader /><main className="page"><section className="learn-intro"><h1>Nothing here</h1><p>This page does not exist. <Link href="/learn/">Go to the lessons</Link> or <Link href="/playground/">open the playground</Link>.</p></section></main><SiteFooter /></>;
}
