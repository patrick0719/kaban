import Link from "next/link";
import { redirect } from "next/navigation";
import { getAccounts, getContext } from "@/lib/context";
import { getGoals } from "@/lib/goals";
import { todayManila } from "@/lib/money";
import { GoalForm } from "../GoalForm";

export default async function NewGoalPage() {
  const ctx = await getContext();
  if (!ctx.canWrite) redirect("/goals");
  const [accounts, { goals }] = await Promise.all([getAccounts(ctx), getGoals(ctx.supabase, ctx.householdId)]);
  const taken = new Set(goals.map((g) => g.linked_account_id).filter(Boolean));
  // Savings accounts not already used by another goal
  const free = accounts.filter((a) => a.class === "asset" && !a.is_spendable && !taken.has(a.id));

  return (
    <div>
      <Link href="/goals" className="text-[14px] text-muted">
        Back to goals
      </Link>
      <h1 className="mt-4 text-[24px] font-semibold tracking-tight">New goal</h1>
      <GoalForm isNew savingsAccounts={free.map(({ id, name }) => ({ id, name }))} today={todayManila()} />
    </div>
  );
}
