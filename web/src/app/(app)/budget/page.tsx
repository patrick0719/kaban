import { getContext } from "@/lib/context";
import { getBudget, monthProgress, pace } from "@/lib/budget";
import { peso, todayManila } from "@/lib/money";
import { PlanTabs } from "@/components/PlanTabs";
import { Progress } from "@/components/Progress";
import { BudgetItem } from "./BudgetItem";
import { applySuggestions } from "./actions";

function monthsBack(today: string, n: number) {
  const [y, m] = today.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 - n, 1)).toISOString().slice(0, 10);
}

export default async function BudgetPage() {
  const ctx = await getContext();
  const today = todayManila();
  const [rows, ...history] = await Promise.all([
    getBudget(ctx.supabase, ctx.householdId, today),
    ...[1, 2, 3].map((n) =>
      ctx.supabase
        .rpc("monthly_summary", { p_household: ctx.householdId, p_month: monthsBack(today, n) })
        .single<{ income: number; expense: number }>(),
    ),
  ]);

  const { left, days, day } = monthProgress(today);
  const monthName = new Intl.DateTimeFormat("en-PH", { month: "long", timeZone: "Asia/Manila" }).format(new Date());
  const withBudget = rows.filter((r) => r.budget != null);
  const without = rows.filter((r) => r.budget == null).sort((a, b) => b.spent - a.spent || (b.suggested ?? 0) - (a.suggested ?? 0));
  const toSuggest = without.filter((r) => r.suggested != null);

  const budgeted = withBudget.reduce((s, r) => s + (r.budget ?? 0), 0);
  const spentBudgeted = withBudget.reduce((s, r) => s + r.spent, 0);
  const spentAll = rows.reduce((s, r) => s + r.spent, 0);

  const past = history.map((h) => h.data).filter((d): d is { income: number; expense: number } => !!d && (Number(d.income) > 0 || Number(d.expense) > 0));
  const avgIncome = past.length ? past.reduce((s, d) => s + Number(d.income), 0) / past.length : 0;
  const avgSpend = past.length ? past.reduce((s, d) => s + Number(d.expense), 0) / past.length : 0;
  const plan = budgeted + toSuggest.reduce((s, r) => s + (r.suggested ?? 0), 0);

  return (
    <div>
      <PlanTabs current="/budget" />
      <h1 className="text-[24px] font-semibold tracking-tight">Budget</h1>
      <p className="mt-1 text-[15px] text-muted">
        {monthName}, {left === 0 ? "last day" : `${left} day${left === 1 ? "" : "s"} left`}
      </p>

      {withBudget.length > 0 && (
        <section className="mt-6 rounded-lg border border-line bg-white p-4">
          <p className="text-[15px]">
            <span className="font-semibold">{peso(spentBudgeted)}</span>
            <span className="text-muted"> of {peso(budgeted)} budgeted</span>
          </p>
          <div className="mt-3">
            <Progress value={Math.min(100, Math.round((spentBudgeted / budgeted) * 100))} label="Budget used this month" />
          </div>
          <p className="mt-2 text-[13px] text-muted">
            {spentBudgeted <= budgeted
              ? `${peso(budgeted - spentBudgeted)} left in your budgeted categories. ${Math.round((day / days) * 100)}% of the month has passed.`
              : `${peso(spentBudgeted - budgeted)} over budget this month.`}
          </p>
        </section>
      )}

      {toSuggest.length > 0 && ctx.canWrite && (
        <section className="mt-6 rounded-lg border border-jade/40 bg-jade-soft/40 p-4">
          <h2 className="text-[15px] font-semibold">Suggested budget</h2>
          <p className="mt-1 text-[13px] text-muted">
            Based on what you spent in the last {toSuggest[0].months_of_history} month{toSuggest[0].months_of_history === 1 ? "" : "s"}, rounded up.
          </p>
          <ul className="mt-3 space-y-1.5 text-[15px]">
            {toSuggest.map((r) => (
              <li key={r.category_id} className="flex justify-between">
                <span>{r.category}</span>
                <span className="font-medium">{peso(r.suggested ?? 0)}</span>
              </li>
            ))}
          </ul>
          {avgIncome > 0 && (
            <p className="mt-3 text-[13px] text-muted">
              You earned about {peso(avgIncome)} and spent about {peso(avgSpend)} a month.{" "}
              {plan < avgIncome
                ? `With this budget, about ${peso(avgIncome - plan)} a month is left for savings and goals.`
                : `This budget is more than your usual income. Consider lowering a few categories.`}
            </p>
          )}
          <form action={applySuggestions} className="mt-4">
            <button className="btn-primary w-full">Use these suggestions</button>
          </form>
          <p className="mt-2 text-[12px] text-muted">You can change any of them after.</p>
        </section>
      )}

      {rows.length === 0 ? (
        <p className="mt-8 text-[15px] text-muted">Add expense categories first.</p>
      ) : (
        <>
          {withBudget.length > 0 && (
            <section className="mt-8">
              <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">With a budget</h2>
              <ul className="divide-y divide-line">
                {withBudget.map((r) => {
                  const p = pace(r.spent, r.budget!, today);
                  return (
                    <BudgetItem
                      key={r.category_id}
                      categoryId={r.category_id}
                      name={r.category}
                      budget={r.budget}
                      spent={r.spent}
                      suggested={r.suggested}
                      status={p.status}
                      projected={p.projected}
                      canWrite={ctx.canWrite}
                    />
                  );
                })}
              </ul>
            </section>
          )}
          <section className="mt-8">
            <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">
              {withBudget.length ? "No budget yet" : `All categories · ${peso(spentAll)} spent this month`}
            </h2>
            <ul className="divide-y divide-line">
              {without.map((r) => (
                <BudgetItem
                  key={r.category_id}
                  categoryId={r.category_id}
                  name={r.category}
                  budget={null}
                  spent={r.spent}
                  suggested={r.suggested}
                  status="ok"
                  projected={0}
                  canWrite={ctx.canWrite}
                />
              ))}
            </ul>
          </section>
        </>
      )}
    </div>
  );
}
