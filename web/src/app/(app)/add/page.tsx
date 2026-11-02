import { getAccounts, getCategories, getContext } from "@/lib/context";
import { todayManila } from "@/lib/money";
import { AddForm } from "./AddForm";

export default async function AddPage() {
  const ctx = await getContext();
  const [accounts, categories] = await Promise.all([getAccounts(ctx), getCategories(ctx)]);
  return (
    <div>
      <h1 className="text-[24px] font-semibold tracking-tight">Add</h1>
      {!ctx.canWrite ? (
        <p className="mt-4 text-muted">You are a viewer in this household, so you cannot add entries.</p>
      ) : (
        <AddForm
          accounts={accounts.map(({ id, name, kind, class: cls, is_spendable }) => ({ id, name, kind, cls, is_spendable }))}
          categories={categories}
          today={todayManila()}
        />
      )}
    </div>
  );
}
