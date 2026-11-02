import type { createClient } from "./supabase/server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

export type Goal = {
  goal_id: string;
  name: string;
  mode: "account" | "earmark";
  target_amount: number;
  saved: number;
  target_date: string | null;
  linked_account_id: string | null;
  owner_user_id: string | null;
};

export type Earmark = { goal_id: string; account_id: string; amount: number };

export async function getGoals(supabase: Supabase, householdId: string) {
  const [{ data: goals }, { data: marks }] = await Promise.all([
    supabase
      .from("goal_progress")
      .select("goal_id, name, mode, target_amount, saved, target_date, linked_account_id, owner_user_id")
      .eq("household_id", householdId)
      .order("name"),
    supabase.from("goal_earmarks").select("goal_id, account_id, amount").eq("household_id", householdId),
  ]);
  const list = ((goals ?? []) as Goal[]).map((g) => ({ ...g, saved: Number(g.saved), target_amount: Number(g.target_amount) }));
  const earmarks = ((marks ?? []) as Earmark[]).map((m) => ({ ...m, amount: Number(m.amount) }));
  return { goals: list, earmarks };
}

export function percent(g: Pick<Goal, "saved" | "target_amount">) {
  return Math.max(0, Math.min(100, Math.floor((g.saved / g.target_amount) * 100)));
}

/** How much to save each month to reach the target on time; null when there is no date or it is reached. */
export function perMonth(g: Pick<Goal, "saved" | "target_amount" | "target_date">, today: string) {
  const left = g.target_amount - g.saved;
  if (left <= 0 || !g.target_date) return null;
  const days = (Date.parse(`${g.target_date}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 864e5;
  const months = Math.max(1, Math.ceil(days / 30.44));
  return { amount: Math.ceil(left / months / 100) * 100, months }; // rounded up to the peso
}
