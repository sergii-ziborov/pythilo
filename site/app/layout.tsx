import type { Metadata, Viewport } from "next";
import { SITE_ORIGIN } from "@/lib/seo";
import "./globals.css";

// Relative canonical and Open Graph URLs resolve against each page's own path,
// so every page gets its own absolute URL without repeating it.
export const metadata: Metadata = {
  metadataBase: new URL(SITE_ORIGIN),
  title: { default: "Pythilo: Python IDE, courses and Labs for iPhone and iPad", template: "%s | Pythilo" },
  description: "A Python IDE, courses and algorithm Labs for iPhone and iPad, with CPython 3.14 on the device. The lessons and Labs also run free in your browser.",
  applicationName: "Pythilo",
  authors: [{ name: "Pythilo", url: SITE_ORIGIN }],
  category: "education",
  alternates: { canonical: "./", types: { "application/rss+xml": [{ url: "/blog/rss.xml", title: "Pythilo blog" }] } },
  openGraph: { siteName: "Pythilo", type: "website", locale: "en_US", url: "./" },
  twitter: { card: "summary_large_image" },
  // Safari on iPhone and iPad offers the app in a banner at the top of each page.
  itunes: { appId: "6829637526" },
  appleWebApp: { title: "Pythilo" },
  robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1, "max-video-preview": -1 } },
};
export const viewport: Viewport = { themeColor: "#0B1016", colorScheme: "dark" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
