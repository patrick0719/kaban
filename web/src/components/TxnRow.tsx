import Link from "next/link";
import { peso, amountText } from "@/lib/money";
import type { TxnView } from "@/lib/transactions";

export function TxnRow({ id, view, quick }: { id: string; view: TxnView; quick?: boolean }) {
  const amount =
    view.tone === "out" ? (
      <span>−{amountText(view.amount)}</span>
    ) : view.tone === "in" ? (
      <span className="text-jade">+{amountText(view.amount)}</span>
    ) : (
      <span className="text-muted">{view.amount < 0 ? "−" : ""}{amountText(view.amount)}</span>
    );

  return (
    <li>
      <Link href={`/transactions/${id}`} className="flex items-baseline justify-between gap-4 py-3 active:bg-line/40">
        <span className="min-w-0">
          <span className="block truncate text-[15px] font-medium">{view.title}</span>
          <span className="block truncate text-[13px] text-muted">
            {view.detail}
            {quick && <span className="ml-1.5 rounded bg-jade-soft px-1 py-px text-[11px] text-jade">Back Tap</span>}
          </span>
        </span>
        <span className="shrink-0 text-[15px] font-medium" aria-label={peso(view.tone === "out" ? -view.amount : view.amount)}>
          {amount}
        </span>
      </Link>
    </li>
  );
}
