/**
 * Facts about Pythilo as a product and a business, used by the home page, pricing,
 * the guide, support and the legal pages. Optional business facts are never invented:
 * support falls back to TestFlight and the public repository, and no forum is chosen
 * until the owner specifies one.
 */
export const OWNER = "Serhii Ziborov";
export const PRODUCT = "Pythilo";
export const SITE_HOST = "pythilo.com";

/** Public alias forwarded to the owner through Forward Email, DNS on Vercel. */
export const CONTACT_EMAIL = "support@pythilo.com";

/** Country or state whose law governs the terms, and where disputes go. Not decided. */
export const GOVERNING_LAW: string | null = null;

/** Verified on the Helsinki node: daily rotation, seven rotated files, maxsize 64M. */
export const LOG_RETENTION = "up to eight days, with earlier rotation when a log reaches 64 MB";

/** One-time paid-app price confirmed by the owner on 5 November 2026. */
export const PRICE = "US$9.99";

/** Date the legal pages were last changed, shown on each of them. */
export const LEGAL_UPDATED = "2026-11-05";

export const APPLE_EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";

export const formatDay = (iso: string) => new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
