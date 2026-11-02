import Link from "next/link";
import { redirect } from "next/navigation";
import { getAccounts, getCategories, getContext } from "@/lib/context";
import { todayManila } from "@/lib/money";
import { BillForm } from "../BillForm";

export default async function NewBillPage() {
  const ctx = await getContext();
  if (!ctx.canWrite) redirect("/bills");
  const [accounts, categories] = await Promise.all([getAccounts(ctx), getCategories(ctx)]);

  return (
    <div>
      <Link href="/bills" className="text-[14px] text-muted">
        Back to bills
      </Link>
      <h1 className="mt-4 text-[24px] font-semibold tracking-tight">Add a bill</h1>
      <BillForm
        isNew
        initial={{ next_due: todayManila() }}
        categories={categories.filter((c) => c.kind === "expense")}
        cards={accounts.filter((a) => a.class === "liability").map(({ id, name }) => ({ id, name }))}
        payAccounts={accounts.filter((a) => a.class === "asset").map(({ id, name }) => ({ id, name }))}
      />
    </div>
  );
}
