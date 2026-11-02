import Link from "next/link";
import { getAccounts, getContext, groupAccounts } from "@/lib/context";
import { getTransactions, describe } from "@/lib/transactions";
import { amountText, peso, shortDate, todayManila } from "@/lib/money";
import { TxnRow } from "@/components/TxnRow";
import { Progress } from "@/components/Progress";
import { getGoals, percent } from "@/lib/goals";
import { Wordmark } from "@/components/Wordmark";

type Available = {
  spendable_balance: number;
  earmarked: number;
  bills_reserved: number;
  card_debt: number;
  available: number;
  horizon: string;
  over_earmarked: boolean;
};

export default async function Dashboard() {
  const ctx = await getContext();
  const { supabase, householdId, household } = ctx;
  const today = todayManila();
  const monthStart = `${today.slice(0, 7)}-01`;

  const [avail, summary, accounts, recent, bills, { goals }] = await Promise.all([
    supabase.rpc("available_to_spend", { p_household: householdId, p_scope: "all" }).single<Available>(),
    supabase
      .rpc("monthly_summary", { p_household: householdId, p_month: monthStart })
      .single<{ income: number; expense: number }>(),
    getAccounts(ctx),
    getTransactions(supabase, householdId, { limit: 6 }),
    supabase
      .from("bill_occurrence_status")
      .select("id, name, due_on, remaining")
      .eq("household_id", householdId)
      .gt("remaining", 0)
      .lte("due_on", addDays(today, 120))
      .order("due_on"),
    getGoals(supabase, householdId),
  ]);

  const a = avail.data;
  // Same window the reservation uses, so the list explains the "Nakareserba" line.
  const dueBills = (bills.data ?? []).filter((b) => !a || b.due_on <= a.horizon);
  const byId = new Map(accounts.map((x) => [x.id, x]));
  const monthName = new Intl.DateTimeFormat("en-PH", { month: "long", timeZone: "Asia/Manila" }).format(new Date());

  return (
    <div>
      <header className="flex items-center justify-between">
        <Wordmark />
        <span className="text-[13px] text-muted">{household.name}</span>
      </header>

      {/* The answer, shown as the sum that produces it */}
      <section aria-labelledby="avail-title" className="mt-8">
        {a ? (
          <>
            <dl className="space-y-2 text-[15px]">
              <Line label="Money in accounts" value={a.spendable_balance} />
              {a.bills_reserved > 0 && <Line label="Set aside for bills" value={-a.bills_reserved} />}
              {a.card_debt > 0 && <Line label="Credit card debt" value={-a.card_debt} />}
              {a.earmarked > 0 && <Line label="Earmarked for savings" value={-a.earmarked} />}
            </dl>
            <div className="mt-4 border-t-2 border-ink pt-3">
              <h1 id="avail-title" className="text-[15px] font-medium">
                {a.available < 0 ? "Short by" : "Safe to spend"}
              </h1>
              <p
                className={`mt-1 text-[44px] font-semibold leading-none tracking-tight ${
                  a.available < 0 ? "text-rust" : ""
                }`}
              >
                <span className="mr-1 align-top text-[24px] font-medium">₱</span>
                {amountText(a.available)}
              </p>
              <p className="mt-2 text-[13px] text-muted">
                Includes bills due by {shortDate(a.horizon)}.
                {a.over_earmarked && " One account holds less than its savings earmark."}
              </p>
            </div>
          </>
        ) : (
          <p className="text-muted">Could not load your balances. Try refreshing.</p>
        )}
      </section>

      <section className="mt-10 border-y border-line py-4">
        <h2 className="text-[13px] text-muted">{monthName} so far</h2>
        <div className="mt-2 grid grid-cols-2">
        <div>
          <p className="text-[13px] text-muted">Income</p>
          <p className="mt-0.5 text-[18px] font-semibold text-jade">{peso(summary.data?.income ?? 0)}</p>
        </div>
        <div className="border-l border-line pl-4">
          <p className="text-[13px] text-muted">Spent</p>
          <p className="mt-0.5 text-[18px] font-semibold">{peso(summary.data?.expense ?? 0)}</p>
        </div>
        </div>
      </section>

      {dueBills.length > 0 && (
        <section className="mt-8">
          <div className="flex items-baseline justify-between">
            <h2 className="text-[17px] font-semibold">Upcoming bills</h2>
            <Link href="/bills" className="text-[13px] text-jade">
              See all
            </Link>
          </div>
          <ul className="mt-2 divide-y divide-line">
            {dueBills.map((b) => (
              <li key={b.id}>
                <Link href={`/bills/${b.id}`} className="flex items-baseline justify-between py-2.5 text-[15px] active:bg-line/40">
                <span>
                  {b.name}
                  <span className={`ml-2 text-[13px] ${b.due_on < today ? "text-rust" : "text-muted"}`}>
                    {b.due_on < today ? "overdue, " : ""}
                    {shortDate(b.due_on)}
                  </span>
                </span>
                <span className="font-medium">{peso(Number(b.remaining))}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {goals.length > 0 && (
        <section className="mt-8">
          <div className="flex items-baseline justify-between">
            <h2 className="text-[17px] font-semibold">Goals</h2>
            <Link href="/goals" className="text-[13px] text-jade">
              See all
            </Link>
          </div>
          <ul className="mt-3 space-y-4">
            {goals
              .slice()
              .sort((x, y) => percent(y) - percent(x))
              .slice(0, 3)
              .map((g) => (
                <li key={g.goal_id}>
                  <Link href={`/goals/${g.goal_id}`} className="block">
                    <span className="flex items-baseline justify-between text-[15px]">
                      <span className="truncate">{g.name}</span>
                      <span className="shrink-0 pl-3 text-[13px] text-muted">
                        {peso(g.saved)} of {peso(g.target_amount)}
                      </span>
                    </span>
                    <span className="mt-1.5 block">
                      <Progress value={percent(g)} label={`${g.name} progress`} />
                    </span>
                  </Link>
                </li>
              ))}
          </ul>
        </section>
      )}

      <section className="mt-8">
        <div className="flex items-baseline justify-between">
          <h2 className="text-[17px] font-semibold">Accounts</h2>
          <Link href="/accounts" className="text-[13px] text-jade">
            See all
          </Link>
        </div>
        <ul className="mt-2 divide-y divide-line">
          {groupAccounts(accounts).map(([label, list]) => {
            const total = list.reduce((s, x) => s + x.balance, 0);
            const isDebt = list[0].class === "liability";
            return (
              <li key={label} className="flex items-baseline justify-between py-2.5 text-[15px]">
                <span>
                  {label}
                  <span className="ml-2 text-[13px] text-muted">{list.length}</span>
                </span>
                <span className={isDebt && total < 0 ? "text-rust" : ""}>
                  {isDebt ? (total < 0 ? `Owe ${peso(-total)}` : "No debt") : peso(total)}
                </span>
              </li>
            );
          })}
        </ul>
      </section>

      <section className="mt-8">
        <div className="flex items-baseline justify-between">
          <h2 className="text-[17px] font-semibold">Recent</h2>
          <Link href="/transactions" className="text-[13px] text-jade">
            See all
          </Link>
        </div>
        {recent.length === 0 ? (
          <p className="mt-3 text-[15px] text-muted">
            Nothing recorded yet. Tap <span className="font-medium text-ink">Add</span> below, or Back Tap your iPhone.
          </p>
        ) : (
          <ul className="mt-1 divide-y divide-line">
            {recent.map((t) => (
              <TxnRow key={t.id} id={t.id} view={describe(t, byId)} quick={t.source === "quick_entry"} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function Line({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex items-baseline justify-between">
      <dt className="text-muted">{label}</dt>
      <dd className="font-medium">{peso(value)}</dd>
    </div>
  );
}

function addDays(iso: string, days: number) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
