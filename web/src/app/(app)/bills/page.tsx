import Link from "next/link";
import { getContext } from "@/lib/context";
import { daysBetween, getBillOverview, type Occurrence } from "@/lib/bills";
import { peso, shortDate, todayManila } from "@/lib/money";
import { PlanTabs } from "@/components/PlanTabs";

export default async function BillsPage() {
  const ctx = await getContext();
  const today = todayManila();
  const soonDays = Math.max(ctx.household.reserve_days, 15);
  const { overdue, soon, later, paid, billById, hasBills } = await getBillOverview(ctx.supabase, ctx.householdId, today, soonDays);
  const isCard = (o: Occurrence) => Boolean(billById.get(o.bill_id)?.settles_account_id);
  const owedSoon = [...overdue, ...soon].reduce((s, o) => s + o.remaining, 0);

  return (
    <div>
      <PlanTabs current="/bills" />
      <div className="flex items-center justify-between">
        <h1 className="text-[24px] font-semibold tracking-tight">Bills</h1>
        {ctx.canWrite && (
          <Link href="/bills/new" className="rounded-lg bg-jade px-3 py-2 text-[14px] font-semibold text-white">
            Add bill
          </Link>
        )}
      </div>

      {!hasBills ? (
        <div className="mt-10">
          <p className="text-[17px] font-medium">No bills yet</p>
          <p className="mt-2 text-[15px] text-muted">
            Add Meralco, water, rent, internet, or a credit card. You will get a reminder before each one is due, and Safe to spend
            sets the money aside for you.
          </p>
        </div>
      ) : (
        <>
          {owedSoon > 0 && (
            <p className="mt-2 text-[15px] text-muted">
              {peso(owedSoon)} due in the next {soonDays} days{overdue.length > 0 ? ", including overdue" : ""}.
            </p>
          )}
          <Group title="Overdue" tone="rust" items={overdue} today={today} isCard={isCard} />
          <Group title={`Next ${soonDays} days`} items={soon} today={today} isCard={isCard} empty="Nothing due soon." />
          <Group title="Later" items={later} today={today} isCard={isCard} />
          <Group title="Paid recently" items={paid} today={today} isCard={isCard} paidList />
        </>
      )}
    </div>
  );
}

function Group({
  title,
  items,
  today,
  isCard,
  tone,
  empty,
  paidList,
}: {
  title: string;
  items: Occurrence[];
  today: string;
  isCard: (o: Occurrence) => boolean;
  tone?: "rust";
  empty?: string;
  paidList?: boolean;
}) {
  if (items.length === 0 && !empty) return null;
  return (
    <section className="mt-7">
      <h2 className={`border-b border-line pb-1.5 text-[13px] ${tone === "rust" ? "text-rust" : "text-muted"}`}>{title}</h2>
      {items.length === 0 ? (
        <p className="py-3 text-[15px] text-muted">{empty}</p>
      ) : (
        <ul className="divide-y divide-line">
          {items.map((o) => (
            <li key={o.id}>
              <Link href={`/bills/${o.id}`} className="flex items-baseline justify-between gap-4 py-3 active:bg-line/40">
                <span className="min-w-0">
                  <span className="block truncate text-[15px] font-medium">
                    {o.name}
                    {isCard(o) && <span className="ml-2 rounded bg-line px-1 py-px text-[11px] font-normal text-muted">Card</span>}
                  </span>
                  <span className={`block text-[13px] ${!paidList && o.due_on < today ? "text-rust" : "text-muted"}`}>
                    {paidList ? `Paid, was due ${shortDate(o.due_on)}` : when(o.due_on, today)}
                  </span>
                </span>
                <span className={`shrink-0 text-[15px] font-medium ${paidList ? "text-muted" : ""}`}>
                  {peso(paidList ? o.amount_due : o.remaining)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function when(due: string, today: string) {
  const d = daysBetween(today, due);
  if (d < 0) return `Due ${shortDate(due)}, ${-d} day${d === -1 ? "" : "s"} ago`;
  if (d === 0) return "Due today";
  if (d === 1) return "Due tomorrow";
  return `Due ${shortDate(due)}, in ${d} days`;
}
