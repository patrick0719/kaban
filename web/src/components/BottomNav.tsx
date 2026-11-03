"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const tabs = [
  { href: "/", label: "Home", icon: "M3 11a9 7 0 0 1 18 0M3 11h18v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z" },
  { href: "/transactions", label: "Activity", icon: "M5 6h14M5 12h14M5 18h9", match: ["/transactions", "/reports"] },
  { href: "/add", label: "Add", icon: "M12 5v14M5 12h14", primary: true },
  { href: "/bills", label: "Plan", icon: "M4 5h16v15H4zM4 9h16M8 3v4M16 3v4M8 13h3M8 16h6", match: ["/bills", "/goals", "/budget"] },
  { href: "/household", label: "More", icon: "M4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0M10.4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0M16.8 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0", match: ["/household", "/accounts"] },
];

export function BottomNav() {
  const path = usePathname();
  return (
    <nav
      aria-label="Main navigation"
      className="fixed inset-x-0 bottom-0 z-20 border-t border-line bg-paper/95 backdrop-blur"
    >
      <ul className="mx-auto flex max-w-md items-stretch justify-around px-2 pb-[max(env(safe-area-inset-bottom),0.5rem)] pt-2">
        {tabs.map((t) => {
          const active = t.href === "/" ? path === "/" : (t.match ?? [t.href]).some((p) => path.startsWith(p));
          return (
            <li key={t.href} className="flex-1">
              <Link
                href={t.href}
                aria-current={active ? "page" : undefined}
                className={`flex flex-col items-center gap-1 py-1 text-[11px] font-medium ${
                  active ? "text-ink" : "text-muted"
                }`}
              >
                <span className="flex h-7 items-center justify-center">
                  {t.primary ? (
                    <span className="flex h-8 w-8 items-center justify-center rounded-full bg-jade text-white">
                      <Icon d={t.icon} />
                    </span>
                  ) : (
                    <Icon d={t.icon} />
                  )}
                </span>
                {t.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

function Icon({ d }: { d: string }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}
