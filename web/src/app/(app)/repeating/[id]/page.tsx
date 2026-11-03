import Link from "next/link";
import { notFound } from "next/navigation";
import { getAccounts, getCategories, getContext, GROUP_LABEL } from "@/lib/context";
import { getOneRecurring, scheduleText } from "@/lib/recurring";
import { amountText, longDate, peso, shortDate, todayManila } from "@/lib/money";
import { ConfirmForm } from "../ConfirmForm";
import { RecurringForm } from "../RecurringForm";
import { stopRecurring } from "../actions";

const KIND_LABEL = { income: "Income", expense: "Expense", transfer: "Transfer" } as const;

export default async function RecurringPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = await getContext();
  const r = await getOneRecurring(ctx.supabase, id);
  if (!r || !r.is_active) notFound();
  const [accounts, categories, { data: history }] = await Promise.all([
    getAccounts(ctx),
    getCategories(ctx),
    ctx.supabase
      .from("transactions")
      .select("id, occurred_on, status, ledger_entries(amount)")
      .eq("recurring_id", id)
      .neq("status", "void")
      .order("occurred_on", { ascending: false })
      .limit(6),
  ]);

  const today = todayManila();
  const accName = new Map(accounts.map((a) => [a.id, a.name]));
  const category = categories.find((c) => c.id === r.category_id)?.name;
  const isDue = r.next_due <= today;
  const showConfirm = ctx.canWrite && (!r.auto_post || r.last_error);
  const where =
    r.kind === "transfer"
      ? `${accName.get(r.account_id) ?? "An account"} to ${accName.get(r.to_account_id ?? "") ?? "another account"}`
      : `${r.kind === "income" ? "Into" : "From"} ${accName.get(r.account_id) ?? "an account"}${category ? ` · ${category}` : ""}`;

  return (
    <div>
      <Link href="/repeating" className="text-[14px] text-muted">
        Back to repeating
      </Link>

      <p className="mt-6 text-[15px] text-muted">
        {KIND_LABEL[r.kind]} · {scheduleText(r)}
        {r.auto_post ? " · automatic" : ""}
      </p>
      <h1 className="mt-1 text-[28px] font-semibold tracking-tight">{r.name}</h1>
      <p className="mt-2 text-[40px] font-semibold leading-none tracking-tight">₱{amountText(r.amount)}</p>
      <p className="mt-2 text-[14px] text-muted">{where}</p>

      {r.last_error && (
        <p className="mt-5 rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">
          This could not be recorded automatically on {shortDate(r.next_due)}. KABAN will try again tomorrow, or you can record it
          below. Reason: {r.last_error.replace(/^KABAN:\s*/, "")}
        </p>
      )}

      {showConfirm ? (
        <section className="mt-8 rounded-xl border border-line bg-white p-4">
          <h2 className="text-[17px] font-semibold">{isDue ? `Due ${longDate(r.next_due)}` : `Next on ${longDate(r.next_due)}`}</h2>
          <p className="mb-4 mt-1 text-[14px] text-muted">
            {isDue
              ? "Record what actually came in or went out. Change the amount or date if it was different."
              : "Already happened? Record it now. The next one moves to the following date."}
          </p>
          <ConfirmForm
            id={r.id}
            due={r.next_due}
            amount={amountText(r.amount).replace(/,/g, "")}
            date={isDue ? r.next_due : today}
            today={today}
            verb={r.kind === "income" ? "Record income" : r.kind === "expense" ? "Record expense" : "Record transfer"}
          />
        </section>
      ) : (
        <p className="mt-6 text-[15px]">
          Next: <span className="font-medium">{longDate(r.next_due)}</span>
          {r.auto_post && <span className="block text-[13px] text-muted">Recorded automatically early that morning.</span>}
        </p>
      )}

      {(history ?? []).length > 0 && (
        <section className="mt-8">
          <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Recorded</h2>
          <ul className="divide-y divide-line">
            {(history ?? []).map((t) => {
              const lines = (t.ledger_entries ?? []) as { amount: number }[];
              const amt = Math.max(...lines.map((l) => Math.abs(Number(l.amount))), 0);
              return (
                <li key={t.id}>
                  <Link href={`/transactions/${t.id}`} className="flex items-baseline justify-between py-2.5 text-[15px] active:bg-line/40">
                    <span>
                      {shortDate(t.occurred_on)}
                      {t.status === "scheduled" && <span className="ml-2 text-[13px] text-muted">scheduled</span>}
                    </span>
                    <span className="font-medium">{peso(amt)}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {ctx.canWrite && (
        <>
          <details className="mt-8 border-t border-line pt-4">
            <summary className="cursor-pointer text-[15px] font-medium text-jade">Edit</summary>
            <RecurringForm
              initial={{
                id: r.id,
                name: r.name,
                kind: r.kind,
                amount: amountText(r.amount).replace(/,/g, ""),
                category: r.category_id ?? undefined,
                account: r.account_id,
                to: r.to_account_id ?? undefined,
                frequency: r.frequency,
                day1: r.day1 ?? undefined,
                day2: r.day2 ?? undefined,
                next: r.next_due,
                auto: r.auto_post,
              }}
              accounts={accounts.map((a) => ({ id: a.id, name: a.name, group: GROUP_LABEL[a.kind], cls: a.class, spendable: a.is_spendable }))}
              categories={categories}
            />
          </details>

          <form action={stopRecurring} className="mt-8 border-t border-line pt-6">
            <input type="hidden" name="id" value={r.id} />
            <button className="btn-danger w-full">Stop repeating</button>
            <p className="mt-2 text-[13px] text-muted">Entries already recorded stay in Activity.</p>
          </form>
        </>
      )}
    </div>
  );
}
