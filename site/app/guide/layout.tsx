import { SiteFooter, SiteHeader } from "@/components/site-header";
import { GuideNav } from "@/components/guide/guide-nav";
import "../site.css";

export default function GuideLayout({ children }: { children: React.ReactNode }) {
  return <>
    <SiteHeader current="guide" />
    <div className="doc-layout">
      <GuideNav />
      <main className="doc">{children}</main>
    </div>
    <SiteFooter />
  </>;
}
