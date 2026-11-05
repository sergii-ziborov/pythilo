import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return { rules: [{ userAgent: "*", allow: "/", disallow: ["/api/", "/playground/room/"] }], sitemap: `${process.env.SITE_ORIGIN || "https://pythilo.com"}/sitemap.xml` };
}
