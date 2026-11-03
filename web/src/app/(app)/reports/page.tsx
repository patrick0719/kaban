import Link from "next/link";
import { getAccounts, getContext } from "@/lib/context";
import { describe, getTransactions } from "@/lib/transactions";
import { getGoals } from "@/lib/goals";
import { peso, shortDate, todayManila } from "@/lib/money";
import { ActivityTabs } from "@/components/ActivityTabs";
import { TrendChart, type TrendPoint } from "./TrendChart";

const SPENT = "#b8601a";

function shiftMonth(ym: string, by: number) {
  const [y, mo] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, mo - 1 + by, 1)).toISOString().slice(0, 7);
}
const monthName = (iso: string, style: "long" | "short") =>
  new Intl.DateTimeFormat("en-PH", { month: style, ...(style === "long" ? { year: "numeric" } : {}), timeZone: "UTC" }).format(
    new Date(`${iso.slice(0, 7)}-01T00:00:00Z`),
  );

export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ m?: string }> }) {
  const ctx = await getContext();
  const { m } = await searchParams;
  const current = todayManila().slice(0, 7);
  const month = /^\d{4}-\d{2}$/.test(m ?? "") && m! <= current ? m! : current;
  const first = `${month}-01`;

  const [{ data: cats }, { data: trend }, txns, accounts, { goals }] = await Promise.all([
    ctx.supabase.rpc("report_categories", { p_household: ctx.householdId, p_month: first }),
    ctx.supabase.rpc("report_trend", { p_household: ctx.householdId, p_month: first, p_months: 6 }),
    getTransactions(ctx.supabase, ctx.householdId, { from: first, to: `${shiftMonth(month, 1)}-01` }),
    getAccounts(ctx),
    getGoals(ctx.supabase, ctx.householdId),
  ]);

  const rows = ((cats ?? []) as { category_id: string; category: string; spent: number; prev_spent: number }[]).map((r) => ({
    ...r,
    spent: Number(r.spent),
    prev_spent: Number(r.prev_spent),
  }));
  const points: TrendPoint[] = ((trend ?? []) as { month: string; income: number; spent: number; saved: number }[]).map((t) => ({
    key: t.month,
    label: monthName(t.month, "short"),
    long: monthName(t.month, "long"),
    income: Number(t.income),
    spent: Number(t.spent),
    saved: Number(t.saved),
  }));
  const now = points.at(-1) ?? { income: 0, spent: 0, saved: 0, key: first, label: "", long: "" };
  const prev = points.at(-2);
  const left = now.income - now.spent;
  const rate = now.income > 0 ? Math.round((left / now.income) * 100) : null;
  const total = rows.reduce((s, r) => s + Math.max(r.spent, 0), 0);
  const maxCat = Math.max(1, ...rows.map((r) => r.spent));
  const byId = new Map(accounts.map((a) => [a.id, a]));
  const biggest = txns
    .filter((t) => t.type === "expense" || t.type === "bill_payment")
    .map((t) => ({ t, v: describe(t, byId) }))
    .sort((a, b) => a.v.amount - b.v.amount)
    .slice(0, 5);
  const goalsSaved = goals.reduce((s, g) => s + g.saved, 0);
  const prevName = prev ? monthName(prev.key, "long").split(" ")[0] : "";
  const hasData = points.some((p) => p.income || p.spent);

  return (
    <div>
      <ActivityTabs current="/reports" month={month} />
      <div className="flex items-center justify-between">
        <Link href={`/reports?m=${shiftMonth(month, -1)}`} aria-label="Previous month" className="-ml-2 p-2 text-muted">
          <Chevron flip />
        </Link>
        <h1 className="text-[20px] font-semibold tracking-tight">{monthName(first, "long")}</h1>
        {month === current ? (
          <span className="w-9" />
        ) : (
          <Link href={`/reports?m=${shiftMonth(month, 1)}`} aria-label="Next month" className="-mr-2 p-2 text-muted">
            <Chevron />
          </Link>
        )}
      </div>

      {!hasData ? (
        <p className="mt-10 text-center text-[15px] text-muted">Nothing recorded yet. Reports fill in as you add income and expenses.</p>
      ) : (
        <>
          {/* The month in three numbers */}
          <section className="mt-5 grid grid-cols-3 border-y border-line py-4">
            <Stat label="Income" value={peso(now.income)} />
            <Stat label="Spent" value={peso(now.spent)} border />
            <Stat label={left < 0 ? "Short" : "Left over"} value={peso(Math.abs(left))} border tone={left < 0 ? "rust" : undefined} />
          </section>
          <p className="mt-3 text-[14px] text-muted">
            {rate != null && (left >= 0 ? `You kept ${rate}% of what came in. ` : `You spent more than came in. `)}
            {prev && prev.spent > 0 && now.spent !== prev.spent
              ? `Spending is ${peso(Math.abs(now.spent - prev.spent))} ${now.spent < prev.spent ? "lower" : "higher"} than ${prevName}${month === current ? " so far" : ""}.`
              : ""}
          </p>

          <section className="mt-8">
            <h2 className="text-[17px] font-semibold">Last 6 months</h2>
            <div className="mt-3">
              <TrendChart points={points} />
            </div>
            <table className="mt-4 w-full text-[13px]">
              <caption className="sr-only">Income, spending and savings by month</caption>
              <thead>
                <tr className="text-left text-muted">
                  <th className="pb-1.5 font-normal">Month</th>
                  <th className="pb-1.5 text-right font-normal">Income</th>
                  <th className="pb-1.5 text-right font-normal">Spent</th>
                  <th className="pb-1.5 text-right font-normal">Saved</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line border-t border-line">
                {[...points].reverse().map((p) => (
                  <tr key={p.key}>
                    <td className="py-1.5">{p.label}</td>
                    <td className="py-1.5 text-right">{peso(p.income)}</td>
                    <td className="py-1.5 text-right">{peso(p.spent)}</td>
                    <td className="py-1.5 text-right">{peso(p.saved)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>

          <section className="mt-10">
            <h2 className="text-[17px] font-semibold">Where the money went</h2>
            {rows.filter((r) => r.spent > 0).length === 0 ? (
              <p className="mt-2 text-[15px] text-muted">No spending this month.</p>
            ) : (
              <ul className="mt-3 space-y-3.5">
                {rows
                  .filter((r) => r.spent > 0)
                  .map((r) => {
                    const share = total ? Math.round((r.spent / total) * 100) : 0;
                    const diff = r.spent - r.prev_spent;
                    return (
                      <li key={r.category_id}>
                        <div className="flex items-baseline justify-between gap-3 text-[15px]">
                          <span className="truncate">{r.category}</span>
                          <span className="shrink-0 font-medium">{peso(r.spent)}</span>
                        </div>
                        <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-line">
                          <div className="h-full rounded-full" style={{ width: `${Math.max(2, (r.spent / maxCat) * 100)}%`, background: SPENT }} />
                        </div>
                        <p className="mt-1 text-[12px] text-muted">
                          {share}% of spending
                          {r.prev_spent > 0 && diff !== 0
                            ? `, ${peso(Math.abs(diff))} ${diff > 0 ? "more" : "less"} than ${prevName}`
                            : r.prev_spent === 0 && prev
                              ? `, nothing in ${prevName}`
                              : ""}
                        </p>
                      </li>
                    );
                  })}
              </ul>
            )}
          </section>

          {biggest.length > 0 && (
            <section className="mt-10">
              <h2 className="text-[17px] font-semibold">Biggest expenses</h2>
              <ul className="mt-1 divide-y divide-line">
                {biggest.map(({ t, v }) => (
                  <li key={t.id}>
                    <Link href={`/transactions/${t.id}`} className="flex items-baseline justify-between gap-4 py-2.5 text-[15px]">
                      <span className="min-w-0">
                        <span className="block truncate">{v.title}</span>
                        <span className="block text-[13px] text-muted">
                          {shortDate(t.occurred_on)}
                          {v.detail ? `, ${v.detail}` : ""}
                        </span>
                      </span>
                      <span className="shrink-0 font-medium">{peso(-v.amount)}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section className="mt-10 rounded-lg border border-line bg-white p-4">
            <h2 className="text-[15px] font-semibold">Savings</h2>
            <p className="mt-1 text-[15px]">
              {now.saved > 0 ? `${peso(now.saved)} moved to savings this month.` : "Nothing moved to savings this month."}
            </p>
            {goals.length > 0 && (
              <p className="mt-1 text-[13px] text-muted">
                {peso(goalsSaved)} saved across your goals.{" "}
                <Link href="/goals" className="text-jade underline underline-offset-4">
                  See goals
                </Link>
              </p>
            )}
          </section>
        </>
      )}
    </div>
  );
}

function Stat({ label, value, border, tone }: { label: string; value: string; border?: boolean; tone?: "rust" }) {
  return (
    <div className={border ? "border-l border-line pl-3" : ""}>
      <p className="text-[12px] text-muted">{label}</p>
      <p className={`mt-0.5 text-[15px] font-semibold ${tone === "rust" ? "text-rust" : ""}`}>{value}</p>
    </div>
  );
}

function Chevron({ flip }: { flip?: boolean }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" style={flip ? { transform: "scaleX(-1)" } : undefined}>
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}
