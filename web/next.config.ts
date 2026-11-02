import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    // Keep visited tabs in the browser for 30 seconds, so switching back is instant.
    // Saving anything in the app refreshes them right away.
    staleTimes: { dynamic: 30, static: 180 },
  },
  async headers() {
    // The service worker must never be cached, so fixes reach phones right away.
    return [{ source: "/sw.js", headers: [{ key: "Cache-Control", value: "no-cache, no-store, must-revalidate" }] }];
  },
};

export default nextConfig;
