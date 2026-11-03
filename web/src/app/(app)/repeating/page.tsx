import Link from "next/link";
import { getAccounts, getContext } from "@/lib/context";
import { dueText, getRecurring, scheduleText, type Recurring } from "@/lib/recurring";
import { peso, todayManila } from "@/lib/money";
import { PlanTabs } from "@/components/PlanTabs";

export default async function RepeatingPage() {
  const ctx = await getContext();
  const today = todayManila();
  const [list, accounts] = await Promise.all([getRecurring(ctx.supabase, ctx.householdId), getAccounts(ctx)]);
  const accName = new Map(accounts.map((a) => [a.id, a.name]));

  const income = list.filter((r) => r.kind === "income");
  const expense = list.filter((r) => r.kind === "expense");
  const transfer = list.filter((r) => r.kind === "transfer");

  return (
    <div>
      <PlanTabs current="/repeating" />
      <div className="flex items-center justify-between">
        <h1 className="text-[24px] font-semibold tracking-tight">Repeating</h1>
        {ctx.canWrite && (
          <Link href="/repeating/new" className="rounded-lg bg-jade px-3 py-2 text-[14px] font-semibold text-white">
            Add
          </Link>
        )}
      </div>

      {list.length === 0 ? (
        <div className="mt-10">
          <p className="text-[17px] font-medium">Nothing repeating yet</p>
          <p className="mt-2 text-[15px] text-muted">
            Add your salary, a subscription, or a regular allowance. KABAN asks you on the day, or records it for you, so you
            do not have to type it every time.
          </p>
        </div>
      ) : (
        <>
          <Group title="Coming in" items={income} today={today} accName={accName} />
          <Group title="Going out" items={expense} today={today} accName={accName} />
          <Group title="Moving between accounts" items={transfer} today={today} accName={accName} />
        </>
      )}
    </div>
  );
}

function Group({ title, items, today, accName }: { title: string; items: Recurring[]; today: string; accName: Map<string, string> }) {
  if (items.length === 0) return null;
  return (
    <section className="mt-7">
      <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">{title}</h2>
      <ul className="divide-y divide-line">
        {items.map((r) => {
          const due = !r.auto_post && r.next_due <= today;
          return (
            <li key={r.id}>
              <Link href={`/repeating/${r.id}`} className="flex items-baseline justify-between gap-4 py-3 active:bg-line/40">
                <span className="min-w-0">
                  <span className="block truncate text-[15px] font-medium">{r.name}</span>
                  <span className="block text-[13px] text-muted">
                    {scheduleText(r)}
                    {r.kind === "transfer" && r.to_account_id ? ` · to ${accName.get(r.to_account_id) ?? "another account"}` : ""}
                  </span>
                  <span className={`block text-[13px] ${due || r.last_error ? "text-rust" : "text-muted"}`}>
                    {r.last_error ? "Could not record automatically" : due ? `${dueText(r.next_due, today)}, waiting for you` : dueText(r.next_due, today)}
                    {!r.last_error && r.auto_post ? " · automatic" : ""}
                  </span>
                </span>
                <span className={`shrink-0 text-[15px] font-medium ${r.kind === "income" ? "text-jade" : ""}`}>
                  {r.kind === "income" ? "+" : ""}
                  {peso(r.amount)}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
