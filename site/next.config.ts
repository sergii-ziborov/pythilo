import type { NextConfig } from "next";

// SharedArrayBuffer (input() and Stop) needs a cross-origin isolated page. Everything
// these pages load is served from this origin, including Pyodide.
const isolated = [{ key: "Cross-Origin-Opener-Policy", value: "same-origin" }, { key: "Cross-Origin-Embedder-Policy", value: "require-corp" }];

const nextConfig: NextConfig = {
  allowedDevOrigins: ["127.0.0.1"],
  output: "standalone",
  trailingSlash: true,
  images: { unoptimized: true },
  poweredByHeader: false,
  outputFileTracingExcludes: { "/*": ["./tests/**/*", "./public/pyodide/**/*"] },
  async headers() {
    return [
      { source: "/:path*", headers: [
        { key: "X-Content-Type-Options", value: "nosniff" },
        { key: "X-Frame-Options", value: "DENY" },
        { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
      ] },
      ...["/api/:path*", "/healthz"].map((source) => ({ source, headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow, noarchive" }] })),
      { source: "/playground/room/:path*", headers: [{ key: "Referrer-Policy", value: "no-referrer" }, { key: "X-Robots-Tag", value: "noindex, nofollow, noarchive" }, { key: "Cache-Control", value: "private, no-store" }] },
      { source: "/playground/:path*", headers: isolated },
      { source: "/learn/:path*", headers: isolated },
      { source: "/_next/static/:path*", headers: [{ key: "Cross-Origin-Embedder-Policy", value: "require-corp" }] },
      { source: "/pyodide/:path*", headers: [{ key: "Cross-Origin-Embedder-Policy", value: "require-corp" }, { key: "Cross-Origin-Resource-Policy", value: "same-origin" }, { key: "Cache-Control", value: "public, max-age=86400" }] },
    ];
  },
};

export default nextConfig;
