"use server";

import { revalidatePath } from "next/cache";
import { getContext } from "@/lib/context";
import { peso, todayManila, toCentavos } from "@/lib/money";
import { friendly } from "@/lib/errors";

export type FixState = { error?: string; ok?: string };

/**
 * Set an account to its real-world balance. The app posts the difference as
 * one ledger entry: an opening balance the first time, an adjustment after.
 * Adjustments never count as income or expense.
 */
export async function fixBalance(_: FixState, form: FormData): Promise<FixState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const id = String(form.get("id") ?? "");
  const value = toCentavos(String(form.get("value") ?? ""));
  const key = String(form.get("request_id") ?? "") || null;
  if (value === null) return { error: "Ilagay ang halaga. Halimbawa: 2,500 o 0" };

  const [{ data: acc }, { data: bal }, { count }] = await Promise.all([
    supabase.from("accounts").select("class, name").eq("id", id).single(),
    supabase.from("account_balances").select("balance").eq("account_id", id).single(),
    supabase.from("ledger_entries").select("id", { count: "exact", head: true }).eq("account_id", id),
  ]);
  if (!acc) return { error: "Hindi makita ang account." };

  // For cards the person types what they owe; the ledger stores debt as negative.
  const target = acc.class === "liability" ? -value : value;
  const diff = target - Number(bal?.balance ?? 0);
  if (diff === 0) return { ok: "Tama na ang balanse. Walang binago." };

  const { error } = await supabase.rpc("post_transaction", {
    p_household: householdId,
    p_type: (count ?? 0) === 0 ? "opening_balance" : "adjustment",
    p_occurred_on: todayManila(),
    p_entries: [{ account_id: id, amount: diff }],
    p_description: "Itinama sa totoong balanse",
    // Same key = same correction: a double tap or a retry never adjusts twice.
    p_idempotency_key: key ? `fix:${key}` : null,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  return {
    ok:
      acc.class === "liability"
        ? `Na-save. Utang sa ${acc.name}: ${peso(value)}.`
        : `Na-save. Laman ng ${acc.name}: ${peso(value)}.`,
  };
}
