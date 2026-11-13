import type { ReactNode } from "react";
import { JsonLd } from "@/components/site/json-ld";
import { allLabs } from "@/lib/browser-labs";
import { guidePlain, labGuide } from "@/lib/lab-guides";
import { PUBLISHER, absoluteUrl, breadcrumbList, describe } from "@/lib/seo";

/** Structured data for a Lab: an interactive exercise on one algorithm. */
export default async function LabLayout({ children, params }: { children: ReactNode; params: Promise<{ lab: string }> }) {
  const id = (await params).lab, lab = allLabs.find(item => item.id === id);
  if (!lab) return children;
  const path = `/labs/${lab.id}/`, guide = labGuide(lab.id);
  return <>
    <JsonLd data={{
      "@context": "https://schema.org", "@type": "LearningResource", "@id": absoluteUrl(path), url: absoluteUrl(path),
      name: lab.title, description: describe(guide ? guidePlain(guide.idea) : lab.summary, 300), learningResourceType: "Interactive lab",
      interactivityType: "active", inLanguage: "en", isAccessibleForFree: true, teaches: lab.title, provider: PUBLISHER,
    }} />
    <JsonLd data={breadcrumbList([["Labs", "/labs/"], [lab.title, path]])} />
    {children}
  </>;
}
