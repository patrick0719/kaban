"use client";

import { useEffect } from "react";

/** Registers /sw.js so the installed app can receive bill reminders. */
export function ServiceWorker() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => {
        // Reminders simply stay unavailable; the rest of the app works.
      });
    }
  }, []);
  return null;
}
