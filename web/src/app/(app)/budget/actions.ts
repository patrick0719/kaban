"use server";

import { revalidatePath } from "next/cache";
import { getContext } from "@/lib/context";
import { getBudget } from "@/lib/budget";
import { peso, todayManila, toCentavos } from "@/lib/money";
import { friendly } from "@/lib/errors";

export type BudgetState = { error?: string; ok?: string };

export async function setBudget(_: BudgetState, form: FormData): Promise<BudgetState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };
  const raw = String(form.get("amount") ?? "").trim();
  const amount = raw === "" ? 0 : toCentavos(raw);
  if (amount === null) return { error: "Enter an amount, like 4,000, or 0 to remove." };

  const { error } = await supabase.rpc("set_budget", {
    p_household: householdId,
    p_category: String(form.get("category_id") ?? ""),
    p_amount: amount,
  });
  if (error) return { error: friendly(error.message) };
  revalidatePath("/", "layout");
  return { ok: amount === 0 ? "Budget removed." : `Budget set to ${peso(amount)} a month.` };
}

/** Set every suggested amount for categories that have no budget yet. */
export async function applySuggestions() {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return;
  const rows = await getBudget(supabase, householdId, todayManila());
  const items = rows
    .filter((r) => r.budget == null && r.suggested != null)
    .map((r) => ({ category_id: r.category_id, amount: r.suggested }));
  if (items.length) await supabase.rpc("set_budgets", { p_household: householdId, p_items: items });
  revalidatePath("/", "layout");
}
