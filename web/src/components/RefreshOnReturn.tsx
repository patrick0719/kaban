"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/**
 * When the app comes back to the foreground after a while (e.g. after a Back Tap
 * entry), reload the data. The installed iPhone app has no pull-to-refresh.
 */
export function RefreshOnReturn({ afterSeconds = 5 }: { afterSeconds?: number }) {
  const router = useRouter();
  useEffect(() => {
    let hiddenAt = 0;
    const onChange = () => {
      if (document.visibilityState === "hidden") hiddenAt = Date.now();
      else if (hiddenAt && Date.now() - hiddenAt > afterSeconds * 1000) router.refresh();
    };
    document.addEventListener("visibilitychange", onChange);
    return () => document.removeEventListener("visibilitychange", onChange);
  }, [router, afterSeconds]);
  return null;
}
