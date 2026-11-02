import Link from "next/link";

const TABS = [
  { href: "/bills", label: "Bills" },
  { href: "/goals", label: "Goals" },
];

/** Switches between the parts of the Plan tab. */
export function PlanTabs({ current }: { current: "/bills" | "/goals" }) {
  return (
    <nav aria-label="Plan" className="mb-5 flex gap-1 rounded-lg border border-line bg-white p-1">
      {TABS.map((t) => (
        <Link
          key={t.href}
          href={t.href}
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
