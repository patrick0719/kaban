import type { createClient } from "./supabase/server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

export type BudgetRow = {
  category_id: string;
  category: string;
  budget: number | null;
  spent: number;
  avg_spent: number | null;
  months_of_history: number;
  suggested: number | null;
};

export type Pace = "ok" | "pace" | "over";

export async function getBudget(supabase: Supabase, householdId: string, month: string) {
  const { data } = await supabase.rpc("budget_status", { p_household: householdId, p_month: month });
  return ((data ?? []) as BudgetRow[]).map((r) => ({
    ...r,
    budget: r.budget == null ? null : Number(r.budget),
    spent: Number(r.spent),
    avg_spent: r.avg_spent == null ? null : Number(r.avg_spent),
    suggested: r.suggested == null ? null : Number(r.suggested),
  }));
}

/** Where this month is: day of month and number of days. */
export function monthProgress(today: string) {
  const [y, m, d] = today.split("-").map(Number);
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return { day: d, days, left: days - d };
}

/**
 * Over = already past the budget. Pace = on track to pass it by month end
 * (only judged after the first 5 days, so one early purchase does not alarm).
 */
export function pace(spent: number, budget: number, today: string): { status: Pace; projected: number } {
  const { day, days } = monthProgress(today);
  const projected = Math.round((spent / day) * days);
  if (spent > budget) return { status: "over", projected };
  if (day >= 5 && projected > budget * 1.05) return { status: "pace", projected };
  return { status: "ok", projected };
}
