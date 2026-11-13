/**
 * Facts about Pythilo as a product and a business, used by the home page, pricing,
 * the guide, support and the legal pages. Optional business facts are never invented:
 * support falls back to email and the public repository, and no forum is chosen
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

/** One-time paid-app price in the United States, read back from App Store Connect on 12 November 2026. */
export const PRICE = "US$9.99";

/** Pythilo 1.0 was released on the App Store in 175 countries and regions on this day. */
export const RELEASED = "2026-11-12";

/** The App Store page. Apple redirects it to the visitor's own storefront. */
export const APP_STORE_URL = "https://apps.apple.com/app/id6829637526";

/** Date the legal pages were last changed, shown on each of them. */
export const LEGAL_UPDATED = "2026-11-12";

export const APPLE_EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";

export const formatDay = (iso: string) => new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
