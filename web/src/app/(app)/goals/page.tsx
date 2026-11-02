import Link from "next/link";
import { getAccounts, getContext } from "@/lib/context";
import { getGoals, perMonth, percent } from "@/lib/goals";
import { peso, todayManila } from "@/lib/money";
import { PlanTabs } from "@/components/PlanTabs";
import { Progress } from "@/components/Progress";

export default async function GoalsPage() {
  const ctx = await getContext();
  const today = todayManila();
  const [{ goals, earmarks }, accounts] = await Promise.all([getGoals(ctx.supabase, ctx.householdId), getAccounts(ctx)]);
  const accName = new Map(accounts.map((a) => [a.id, a.name]));
  const totalSaved = goals.reduce((s, g) => s + g.saved, 0);

  return (
    <div>
      <PlanTabs current="/goals" />
      <div className="flex items-center justify-between">
        <h1 className="text-[24px] font-semibold tracking-tight">Goals</h1>
        {ctx.canWrite && (
          <Link href="/goals/new" className="rounded-lg bg-jade px-3 py-2 text-[14px] font-semibold text-white">
            New goal
          </Link>
        )}
      </div>

      {goals.length === 0 ? (
        <div className="mt-10">
          <p className="text-[17px] font-medium">No goals yet</p>
          <p className="mt-2 text-[15px] text-muted">
            Start with an emergency fund, a trip, school fees, or a new phone. Money you put toward a goal is kept out of Safe to
            spend, so you do not use it by accident.
          </p>
        </div>
      ) : (
        <>
          <p className="mt-2 text-[15px] text-muted">{peso(totalSaved)} saved across {goals.length} goal{goals.length === 1 ? "" : "s"}.</p>
          <ul className="mt-6 space-y-3">
            {goals.map((g) => {
              const pct = percent(g);
              const pm = perMonth(g, today);
              const where =
                g.mode === "account"
                  ? `In ${accName.get(g.linked_account_id ?? "") ?? "its savings account"}`
                  : (() => {
                      const names = earmarks.filter((m) => m.goal_id === g.goal_id).map((m) => accName.get(m.account_id)).filter(Boolean);
                      return names.length ? `Set aside in ${names.join(", ")}` : "Nothing set aside yet";
                    })();
              return (
                <li key={g.goal_id}>
                  <Link href={`/goals/${g.goal_id}`} className="block rounded-lg border border-line bg-white p-4 active:bg-line/30">
                    <div className="flex items-baseline justify-between gap-3">
                      <span className="truncate text-[16px] font-semibold">{g.name}</span>
                      <span className="shrink-0 text-[14px] text-muted">{pct}%</span>
                    </div>
                    <p className="mt-1 text-[15px]">
                      <span className="font-medium">{peso(g.saved)}</span>
                      <span className="text-muted"> of {peso(g.target_amount)}</span>
                    </p>
                    <div className="mt-3">
                      <Progress value={pct} label={`${g.name} progress`} />
                    </div>
                    <p className="mt-2 text-[13px] text-muted">
                      {g.saved >= g.target_amount
                        ? "Reached. Well done."
                        : pm
                          ? `Save ${peso(pm.amount)} a month to reach it on time`
                          : `${peso(g.target_amount - g.saved)} to go`}
                      {" · "}
                      {where}
                    </p>
                  </Link>
                </li>
              );
            })}
          </ul>
        </>
      )}
    </div>
  );
}
