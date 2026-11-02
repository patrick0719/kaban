import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getAccounts, getCategories, getContext } from "@/lib/context";
import { getBill } from "@/lib/bills";
import { amountText } from "@/lib/money";
import { BillForm } from "../../BillForm";
import { StopBill } from "./StopBill";

export default async function EditBillPage({ params }: { params: Promise<{ billId: string }> }) {
  const { billId } = await params;
  const ctx = await getContext();
  if (!ctx.canWrite) redirect("/bills");
  const [bill, accounts, categories] = await Promise.all([getBill(ctx.supabase, billId), getAccounts(ctx), getCategories(ctx)]);
  if (!bill) notFound();

  return (
    <div>
      <Link href="/bills" className="text-[14px] text-muted">
        Back to bills
      </Link>
      <h1 className="mt-4 text-[24px] font-semibold tracking-tight">Edit {bill.name}</h1>
      <p className="mt-1 text-[14px] text-muted">
        A new amount applies to months not yet paid. Paid months stay as they are.
      </p>
      <BillForm
        isNew={false}
        initial={{
          bill_id: bill.id,
          name: bill.name,
          amount: amountText(Number(bill.estimated_amount)),
          next_due: bill.starts_on,
          repeat: bill.recurrence_months == null ? "" : String(bill.recurrence_months),
          category: bill.category_id,
          card: bill.settles_account_id ?? "",
          pay_from: bill.pay_from_account_id ?? "",
        }}
        categories={categories.filter((c) => c.kind === "expense")}
        cards={accounts.filter((a) => a.class === "liability").map(({ id, name }) => ({ id, name }))}
        payAccounts={accounts.filter((a) => a.class === "asset").map(({ id, name }) => ({ id, name }))}
      />
      {bill.is_active && (
        <div className="mt-10 border-t border-line pt-6">
          <StopBill billId={bill.id} name={bill.name} />
        </div>
      )}
    </div>
  );
}
