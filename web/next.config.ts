import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    // Keep visited tabs in the browser for 30 seconds, so switching back is instant.
    // Saving anything in the app refreshes them right away.
    staleTimes: { dynamic: 30, static: 180 },
  },
};

export default nextConfig;
