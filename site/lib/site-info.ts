/**
 * Facts about Pythilo as a product and a business, used by the home page, pricing,
 * the guide, support and the legal pages. A `null` value is something the owner has
 * not decided yet: the pages show a clearly marked placeholder instead of inventing it.
 */
export const OWNER = "Sergii Ziborov";
export const PRODUCT = "Pythilo";
export const SITE_HOST = "pythilo.com";

/** Public support address. Not decided: do not put a personal address here. */
export const CONTACT_EMAIL: string | null = null;

/** Country or state whose law governs the terms, and where disputes go. Not decided. */
export const GOVERNING_LAW: string | null = null;

/** How long the web server's access and error logs are kept. Not configured on the server yet. */
export const LOG_RETENTION: string | null = null;

/** The App Store price or in-app purchase. Not decided (docs/STATUS.md, docs/app-store/listing.md). */
export const PRICE: string | null = null;

/** Date the legal pages were last changed, shown on each of them. */
export const LEGAL_UPDATED = "2026-11-04";

export const APPLE_EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";

export const formatDay = (iso: string) => new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
