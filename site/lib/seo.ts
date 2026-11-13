/** Helpers for titles, descriptions and structured data. */
export const SITE_ORIGIN = (process.env.SITE_ORIGIN || "https://pythilo.com").replace(/\/$/, "");

export const absoluteUrl = (path: string) => (path.startsWith("http") ? path : `${SITE_ORIGIN}${path}`);

/** Plain text of at most `max` characters that ends on a whole word, for meta descriptions. */
export function describe(text: string, max = 158): string {
  const plain = text.replace(/`/g, "").replace(/\s+/g, " ").trim();
  if (plain.length <= max) return plain;
  const cut = plain.slice(0, max - 1);
  const end = cut.lastIndexOf(" ");
  return `${(end > max * 0.6 ? cut.slice(0, end) : cut).replace(/[\s,;:.(-]+$/, "")}…`;
}

/** schema.org BreadcrumbList from [name, path] pairs, first to last. */
export function breadcrumbList(items: [string, string][]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map(([name, path], index) => ({ "@type": "ListItem", position: index + 1, name, item: absoluteUrl(path) })),
  };
}

export const PUBLISHER = { "@type": "Organization", name: "Pythilo", url: absoluteUrl("/") } as const;
