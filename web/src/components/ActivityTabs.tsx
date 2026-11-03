import Link from "next/link";

/** Switches between the list of entries and the reports for the same month. */
export function ActivityTabs({ current, month }: { current: "/transactions" | "/reports"; month?: string }) {
  const q = month ? `?m=${month}` : "";
  const tabs = [
    { href: "/transactions", label: "Entries" },
    { href: "/reports", label: "Reports" },
  ];
  return (
    <nav aria-label="Activity" className="mb-5 flex gap-1 rounded-lg border border-line bg-white p-1">
      {tabs.map((t) => (
        <Link
          key={t.href}
          href={`${t.href}${q}`}
          aria-current={t.href === current ? "page" : undefined}
          className={`flex-1 rounded-md py-1.5 text-center text-[14px] font-medium ${
            t.href === current ? "bg-ink text-white" : "text-muted"
          }`}
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}
