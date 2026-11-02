import Link from "next/link";
import { notFound } from "next/navigation";
import { getAccounts, getContext, GROUP_LABEL } from "@/lib/context";
import { daysBetween, getBill, getOccurrence, REPEAT_LABEL } from "@/lib/bills";
import { amountText, longDate, peso, shortDate, todayManila } from "@/lib/money";
import { toggleSkip } from "../actions";
import { AmountForm, PayForm } from "./Forms";

export default async function BillOccurrencePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = await getContext();
  const occ = await getOccurrence(ctx.supabase, id);
  if (!occ) notFound();
  const [bill, accounts, { data: payments }] = await Promise.all([
    getBill(ctx.supabase, occ.bill_id),
    getAccounts(ctx),
    ctx.supabase
      .from("transactions")
      .select("id, occurred_on, status, ledger_entries(amount, account_id)")
      .eq("bill_occurrence_id", id)
      .neq("status", "void")
      .order("occurred_on"),
  ]);
  if (!bill) notFound();

  const today = todayManila();
  const card = bill.settles_account_id ? accounts.find((a) => a.id === bill.settles_account_id) : undefined;
  // Card bills are paid from money accounts; other bills can also be charged to a card.
  const sources = accounts.filter((a) => a.class === "asset" || (!card && a.class === "liability"));
  const defaultFrom = bill.pay_from_account_id && sources.some((a) => a.id === bill.pay_from_account_id) ? bill.pay_from_account_id : "";
  const accName = new Map(accounts.map((a) => [a.id, a.name]));
  const d = daysBetween(today, occ.due_on);
  const settled = occ.remaining === 0;

  const status = occ.is_skipped
    ? "Skipped this month"
    : settled
      ? "Paid"
      : d < 0
        ? `Overdue by ${-d} day${d === -1 ? "" : "s"}`
        : d === 0
          ? "Due today"
          : `Due in ${d} day${d === 1 ? "" : "s"}`;

  return (
    <div>
      <Link href="/bills" className="text-[14px] text-muted">
        Back to bills
      </Link>

      <p className={`mt-6 text-[15px] ${!settled && !occ.is_skipped && d < 0 ? "text-rust" : "text-muted"}`}>{status}</p>
      <h1 className="mt-1 text-[28px] font-semibold tracking-tight">{bill.name}</h1>
      <p className={`mt-2 text-[40px] font-semibold leading-none tracking-tight ${settled || occ.is_skipped ? "text-muted" : ""}`}>
        ₱{amountText(settled || occ.is_skipped ? occ.amount_due : occ.remaining)}
      </p>
      {occ.paid > 0 && !settled && (
        <p className="mt-2 text-[14px] text-muted">
          {peso(occ.paid)} paid of {peso(occ.amount_due)}
        </p>
      )}

      <dl className="mt-6 divide-y divide-line border-y border-line text-[15px]">
        <Row label="Due" value={longDate(occ.due_on)} />
        <Row label="Repeats" value={REPEAT_LABEL[bill.recurrence_months == null ? "" : String(bill.recurrence_months)]} />
        {card && <Row label="Credit card" value={card.name} />}
        {occ.owner_user_id && <Row label="Visible to" value="Only you" />}
      </dl>

      {(payments ?? []).length > 0 && (
        <section className="mt-6">
          <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Payments</h2>
          <ul className="divide-y divide-line">
            {(payments ?? []).map((p) => {
              const out = (p.ledger_entries as { amount: number; account_id: string }[]).find((e) => Number(e.amount) < 0);
              return (
                <li key={p.id}>
                  <Link href={`/transactions/${p.id}`} className="flex items-baseline justify-between py-2.5 text-[15px]">
                    <span>
                      {shortDate(p.occurred_on)}
                      <span className="ml-2 text-[13px] text-muted">from {out ? accName.get(out.account_id) ?? "an account" : "an account"}</span>
                    </span>
                    <span className="font-medium">{out ? peso(-Number(out.amount)) : ""}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {ctx.canWrite && !settled && !occ.is_skipped && (
        <section className="mt-8">
          <h2 className="mb-3 text-[17px] font-semibold">Record a payment</h2>
          <PayForm
            occurrenceId={occ.id}
            remaining={amountText(occ.remaining)}
            accounts={sources.map((a) => ({ id: a.id, name: a.name, group: GROUP_LABEL[a.kind] }))}
            defaultFrom={defaultFrom}
            today={today}
            cardName={card?.name ?? null}
          />
        </section>
      )}

      {ctx.canWrite && (
        <section className="mt-8 space-y-4 border-t border-line pt-6">
          {!settled && !occ.is_skipped && <AmountForm occurrenceId={occ.id} current={amountText(occ.amount_due)} />}
          {occ.paid === 0 && (
            <form action={toggleSkip}>
              <input type="hidden" name="occurrence_id" value={occ.id} />
              <input type="hidden" name="skip" value={occ.is_skipped ? "false" : "true"} />
              <button className="text-[14px] text-jade underline underline-offset-4">
                {occ.is_skipped ? "Undo skip" : "Skip this month (no bill this time)"}
              </button>
            </form>
          )}
          <Link href={`/bills/edit/${bill.id}`} className="block text-[14px] text-jade underline underline-offset-4">
            Edit bill
          </Link>
        </section>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4 py-2.5">
      <dt className="text-muted">{label}</dt>
      <dd className="text-right">{value}</dd>
    </div>
  );
}
