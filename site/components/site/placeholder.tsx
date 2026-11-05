import { CONTACT_EMAIL } from "@/lib/site-info";

/** Something the owner has to decide or fill in. Rendered so nobody can miss it. */
export function Placeholder({ children }: { children: React.ReactNode }) {
  return <mark className="placeholder" data-placeholder="owner"><span className="placeholder-tag">To be filled in</span>{children}</mark>;
}

/** The support address, or a marked placeholder while there is none. */
export function ContactEmail() {
  return CONTACT_EMAIL ? <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> : <Placeholder>support email address</Placeholder>;
}
