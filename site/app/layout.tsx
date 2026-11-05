import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.SITE_ORIGIN || "https://pythilo.com"),
  title: { default: "Pythilo — Real Python on your iPhone and iPad", template: "%s | Pythilo" },
  description: "Python lessons and a playground that run in your browser, with no account. The iPhone and iPad app opens the same projects and runs them with full CPython, offline.",
  applicationName: "Pythilo",
  openGraph: { siteName: "Pythilo", type: "website", locale: "en_US" },
};
export const viewport: Viewport = { themeColor: "#0B1016", colorScheme: "dark" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
