import Link from "next/link";
import { notFound } from "next/navigation";
import { getAccounts, getContext } from "@/lib/context";
import { describe, getTransaction } from "@/lib/transactions";
import { amountText, longDate } from "@/lib/money";
import { VoidButton } from "./VoidButton";

const TYPE_LABEL: Record<string, string> = {
  expense: "Expense",
  bill_payment: "Bill payment",
  income: "Income",
  refund: "Refund",
  transfer: "Transfer",
  savings_contribution: "Savings deposit",
  opening_balance: "Opening balance",
  adjustment: "Balance correction",
};

export default async function TransactionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = await getContext();
  const [t, accounts] = await Promise.all([getTransaction(ctx.supabase, id), getAccounts(ctx)]);
  if (!t) notFound();

  const v = describe(t, new Map(accounts.map((a) => [a.id, a])));
  const mine = t.created_by === ctx.user.id;
  const canVoid = t.status !== "void" && ctx.canWrite && (mine || ctx.isAdmin);
  const sign = v.tone === "out" ? "−" : v.tone === "in" ? "+" : v.amount < 0 ? "−" : "";

  return (
    <div>
      <Link href="/transactions" className="text-[14px] text-muted">
        Back to activity
      </Link>

      <p className="mt-6 text-[15px] text-muted">{TYPE_LABEL[t.type]}</p>
      <h1 className={`mt-1 text-[40px] font-semibold leading-none tracking-tight ${t.status === "void" ? "text-muted line-through" : ""} ${v.tone === "in" ? "text-jade" : ""}`}>
        {sign}₱{amountText(v.amount)}
      </h1>
      <p className="mt-2 text-[17px] font-medium">{v.title}</p>

      <dl className="mt-6 divide-y divide-line border-y border-line text-[15px]">
        <Row label="Date" value={longDate(t.occurred_on)} />
        <Row label="Account" value={v.detail || "—"} />
        {t.description && <Row label="Note" value={t.description} />}
        <Row label="Recorded by" value={mine ? "You" : "Another member"} />
        <Row label="Recorded with" value={t.source === "quick_entry" ? "Back Tap" : "App"} />
        {t.status === "void" && <Row label="Status" value="Void" />}
        {t.status === "scheduled" && <Row label="Status" value="Scheduled" />}
      </dl>

      {canVoid && (
        <div className="mt-8">
          <VoidButton id={t.id} />
        </div>
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
