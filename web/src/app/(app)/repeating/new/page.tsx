import Link from "next/link";
import { redirect } from "next/navigation";
import { getAccounts, getCategories, getContext, GROUP_LABEL } from "@/lib/context";
import { todayManila } from "@/lib/money";
import { RecurringForm } from "../RecurringForm";

export default async function NewRecurringPage() {
  const ctx = await getContext();
  if (!ctx.canWrite) redirect("/repeating");
  const [accounts, categories] = await Promise.all([getAccounts(ctx), getCategories(ctx)]);

  return (
    <div>
      <Link href="/repeating" className="text-[14px] text-muted">
        Back to repeating
      </Link>
      <h1 className="mt-4 text-[24px] font-semibold tracking-tight">Add a repeating entry</h1>
      <RecurringForm
        initial={{ next: todayManila() }}
        accounts={accounts.map((a) => ({ id: a.id, name: a.name, group: GROUP_LABEL[a.kind], cls: a.class, spendable: a.is_spendable }))}
        categories={categories}
      />
    </div>
  );
}
