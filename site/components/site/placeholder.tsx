import Link from "next/link";
import { CONTACT_EMAIL } from "@/lib/site-info";

/** Use the configured public email; otherwise offer the available support channels. */
export function ContactEmail() {
  return CONTACT_EMAIL ? <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> : <Link href="/support/#contact">the support page</Link>;
}
