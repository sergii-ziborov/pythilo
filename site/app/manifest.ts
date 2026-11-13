import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Pythilo: Python IDE, courses and Labs",
    short_name: "Pythilo",
    description: "Python lessons, Labs and a playground that run in your browser. The Pythilo app runs the same projects on iPhone and iPad with full CPython, offline.",
    start_url: "/",
    scope: "/",
    display: "browser",
    background_color: "#0B1016",
    theme_color: "#0B1016",
    lang: "en",
    categories: ["education", "developer tools"],
    icons: [
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png" },
      { src: "/icons/maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    related_applications: [{ platform: "itunes", url: "https://apps.apple.com/app/id6829637526", id: "6829637526" }],
  };
}
