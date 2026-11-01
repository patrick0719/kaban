import Link from "next/link";
import { getAccounts, getContext } from "@/lib/context";
import { describe, getTransactions } from "@/lib/transactions";
import { longDate, peso, todayManila } from "@/lib/money";
import { TxnRow } from "@/components/TxnRow";

export default async function TransactionsPage({ searchParams }: { searchParams: Promise<{ m?: string }> }) {
  const ctx = await getContext();
  const { m } = await searchParams;
  const month = /^\d{4}-\d{2}$/.test(m ?? "") ? m! : todayManila().slice(0, 7);
  const from = `${month}-01`;
  const to = shiftMonth(month, 1) + "-01";

  const [accounts, txns] = await Promise.all([getAccounts(ctx), getTransactions(ctx.supabase, ctx.householdId, { from, to })]);
  const byId = new Map(accounts.map((a) => [a.id, a]));

  const days = new Map<string, typeof txns>();
  for (const t of txns) days.set(t.occurred_on, [...(days.get(t.occurred_on) ?? []), t]);

  const label = new Intl.DateTimeFormat("fil-PH", { month: "long", year: "numeric", timeZone: "UTC" }).format(
    new Date(`${from}T00:00:00Z`),
  );
  const isCurrent = month === todayManila().slice(0, 7);

  return (
    <div>
      <div className="flex items-center justify-between">
        <Link href={`/transactions?m=${shiftMonth(month, -1)}`} aria-label="Nakaraang buwan" className="-ml-2 p-2 text-muted">
          <Chevron flip />
        </Link>
        <h1 className="text-[20px] font-semibold tracking-tight">{label}</h1>
        {isCurrent ? (
          <span className="w-9" />
        ) : (
          <Link href={`/transactions?m=${shiftMonth(month, 1)}`} aria-label="Susunod na buwan" className="-mr-2 p-2 text-muted">
            <Chevron />
          </Link>
        )}
      </div>

      {days.size === 0 ? (
        <p className="mt-10 text-center text-[15px] text-muted">Walang naitala sa buwang ito.</p>
      ) : (
        [...days.entries()].map(([day, list]) => {
          const spent = list
            .filter((t) => t.type === "expense" || t.type === "bill_payment" || t.type === "refund")
            .reduce((s, t) => s - t.ledger_entries.reduce((x, e) => x + Number(e.amount), 0), 0);
          return (
            <section key={day} className="mt-6">
              <h2 className="flex items-baseline justify-between border-b border-line pb-1.5 text-[13px] text-muted">
                <span>{longDate(day)}</span>
                {spent > 0 && <span>Gastos {peso(spent)}</span>}
              </h2>
              <ul className="divide-y divide-line">
                {list.map((t) => (
                  <TxnRow key={t.id} id={t.id} view={describe(t, byId)} quick={t.source === "quick_entry"} />
                ))}
              </ul>
            </section>
          );
        })
      )}
    </div>
  );
}

function shiftMonth(ym: string, by: number) {
  const [y, mo] = ym.split("-").map(Number);
  const d = new Date(Date.UTC(y, mo - 1 + by, 1));
  return d.toISOString().slice(0, 7);
}

function Chevron({ flip }: { flip?: boolean }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" style={flip ? { transform: "scaleX(-1)" } : undefined}>
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}
