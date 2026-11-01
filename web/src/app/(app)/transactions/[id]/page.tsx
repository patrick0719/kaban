import Link from "next/link";
import { notFound } from "next/navigation";
import { getAccounts, getContext } from "@/lib/context";
import { describe, getTransaction } from "@/lib/transactions";
import { amountText, longDate } from "@/lib/money";
import { VoidButton } from "./VoidButton";

const TYPE_LABEL: Record<string, string> = {
  expense: "Gastos",
  bill_payment: "Bayad sa bill",
  income: "Kita",
  refund: "Refund",
  transfer: "Lipat",
  savings_contribution: "Inipon",
  opening_balance: "Simulang balanse",
  adjustment: "Pagtatama ng balanse",
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
        Bumalik sa talaan
      </Link>

      <p className="mt-6 text-[15px] text-muted">{TYPE_LABEL[t.type]}</p>
      <h1 className={`mt-1 text-[40px] font-semibold leading-none tracking-tight ${t.status === "void" ? "text-muted line-through" : ""} ${v.tone === "in" ? "text-jade" : ""}`}>
        {sign}₱{amountText(v.amount)}
      </h1>
      <p className="mt-2 text-[17px] font-medium">{v.title}</p>

      <dl className="mt-6 divide-y divide-line border-y border-line text-[15px]">
        <Row label="Petsa" value={longDate(t.occurred_on)} />
        <Row label="Account" value={v.detail || "—"} />
        {t.description && <Row label="Tala" value={t.description} />}
        <Row label="Itinala ni" value={mine ? "Ikaw" : "Ibang member"} />
        <Row label="Paano" value={t.source === "quick_entry" ? "Back Tap" : "Sa app"} />
        {t.status === "void" && <Row label="Status" value="Void" />}
        {t.status === "scheduled" && <Row label="Status" value="Naka-schedule" />}
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
