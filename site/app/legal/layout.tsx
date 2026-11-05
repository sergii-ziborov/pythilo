import { SiteFooter, SiteHeader } from "@/components/site-header";
import { DocNav } from "@/components/site/doc-nav";
import { LEGAL_PAGES } from "@/lib/legal";
import "../site.css";

export default function LegalLayout({ children }: { children: React.ReactNode }) {
  return <>
    <SiteHeader current="legal" />
    <div className="doc-layout">
      <DocNav title="Legal" items={LEGAL_PAGES} />
      <main className="doc">{children}</main>
    </div>
    <SiteFooter />
  </>;
}
