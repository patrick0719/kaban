"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const tabs = [
  { href: "/", label: "Kaban", icon: "M3 11a9 7 0 0 1 18 0M3 11h18v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z" },
  { href: "/transactions", label: "Talaan", icon: "M5 6h14M5 12h14M5 18h9" },
  { href: "/add", label: "Itala", icon: "M12 5v14M5 12h14", primary: true },
  { href: "/accounts", label: "Accounts", icon: "M3 7h18v12H3zM3 11h18M16 15h2" },
  { href: "/household", label: "Bahay", icon: "M4 11l8-6 8 6v9H4zM10 20v-5h4v5" },
];

export function BottomNav() {
  const path = usePathname();
  return (
    <nav
      aria-label="Pangunahing navigation"
      className="fixed inset-x-0 bottom-0 z-20 border-t border-line bg-paper/95 backdrop-blur"
    >
      <ul className="mx-auto flex max-w-md items-stretch justify-around px-2 pb-[max(env(safe-area-inset-bottom),0.5rem)] pt-2">
        {tabs.map((t) => {
          const active = t.href === "/" ? path === "/" : path.startsWith(t.href);
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
