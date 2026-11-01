"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getContext } from "@/lib/context";
import { toCentavos } from "@/lib/money";
import { friendly } from "@/lib/errors";

export type AddState = { error?: string };

export async function addTransaction(_: AddState, form: FormData): Promise<AddState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const kind = String(form.get("kind"));
  const amount = toCentavos(String(form.get("amount") ?? ""));
  const date = String(form.get("date") ?? "");
  const note = String(form.get("note") ?? "").trim() || null;
  const key = String(form.get("request_id") ?? "") || null;

  if (!amount || amount <= 0) return { error: "Ilagay kung magkano. Halimbawa: 150 o 1,250.50" };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { error: "Pumili ng petsa." };

  let p_type: string;
  let p_entries: { account_id: string; amount: number }[];
  let p_category_id: string | null = null;

  if (kind === "transfer") {
    const from = String(form.get("from") ?? "");
    const to = String(form.get("to") ?? "");
    if (!from || !to) return { error: "Pumili kung saan galing at saan papunta." };
    if (from === to) return { error: "Magkaiba dapat ang galing at papunta." };
    p_type = "transfer";
    p_entries = [
      { account_id: from, amount: -amount },
      { account_id: to, amount },
    ];
  } else {
    const account = String(form.get("account") ?? "");
    p_category_id = String(form.get("category") ?? "") || null;
    if (!account) return { error: "Pumili ng account." };
    if (!p_category_id) return { error: "Pumili ng category." };
    p_type = kind === "income" ? "income" : "expense";
    p_entries = [{ account_id: account, amount: kind === "income" ? amount : -amount }];
  }

  const { error } = await supabase.rpc("post_transaction", {
    p_household: householdId,
    p_type,
    p_occurred_on: date,
    p_entries,
    p_category_id,
    p_description: note,
    p_idempotency_key: key,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  redirect("/?saved=1");
}
