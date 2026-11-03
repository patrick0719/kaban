"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getContext } from "@/lib/context";
import { peso, toCentavos } from "@/lib/money";
import { friendly } from "@/lib/errors";

export type RecurringState = { error?: string; ok?: string };

const ISO = /^\d{4}-\d{2}-\d{2}$/;
const KINDS = ["income", "expense", "transfer"];
const FREQUENCIES = ["weekly", "every_2_weeks", "monthly", "twice_a_month"];

export async function saveRecurring(_: RecurringState, form: FormData): Promise<RecurringState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const id = String(form.get("id") ?? "") || null;
  const name = String(form.get("name") ?? "").trim();
  const kind = String(form.get("kind") ?? "");
  const amount = toCentavos(String(form.get("amount") ?? ""));
  const category = String(form.get("category") ?? "") || null;
  const account = String(form.get("account") ?? "");
  const to = String(form.get("to") ?? "") || null;
  const frequency = String(form.get("frequency") ?? "");
  const day1 = Number(form.get("day1") ?? 0) || null;
  const day2 = Number(form.get("day2") ?? 0) || null;
  const next = String(form.get("next") ?? "");
  const auto = form.get("mode") === "auto";

  if (!name) return { error: "Give it a name, like Salary or Netflix." };
  if (!KINDS.includes(kind)) return { error: "Choose income, expense or transfer." };
  if (!amount || amount <= 0) return { error: "Enter the usual amount, like 25,000." };
  if (!account) return { error: kind === "income" ? "Choose where the money goes." : "Choose where the money comes from." };
  if (kind === "transfer" && !to) return { error: "Choose where the money goes." };
  if (kind === "transfer" && to === account) return { error: "From and To must be different accounts." };
  if (kind !== "transfer" && !category) return { error: "Choose a category." };
  if (!FREQUENCIES.includes(frequency)) return { error: "Choose how often it repeats." };
  if (frequency === "twice_a_month" && day1 && day2 && day1 >= day2) {
    return { error: "Choose the earlier day first, like the 15th and the last day." };
  }
  if (!ISO.test(next)) return { error: "Choose the next date." };

  const { error } = await supabase.rpc("save_recurring", {
    p_household: householdId,
    p_id: id,
    p_name: name,
    p_kind: kind,
    p_amount: amount,
    p_category: kind === "transfer" ? null : category,
    p_account: account,
    p_to_account: kind === "transfer" ? to : null,
    p_frequency: frequency,
    p_day1: day1,
    p_day2: day2,
    p_next: next,
    p_auto_post: auto,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  redirect("/repeating");
}

/** Record the due one with the amount and date that actually happened. */
export async function recordRecurring(_: RecurringState, form: FormData): Promise<RecurringState> {
  const { supabase, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const amount = toCentavos(String(form.get("amount") ?? ""));
  const date = String(form.get("date") ?? "");
  const key = String(form.get("request_id") ?? "") || null;
  if (!amount || amount <= 0) return { error: "Enter the amount." };
  if (!ISO.test(date)) return { error: "Choose the date." };

  const { error } = await supabase.rpc("record_recurring", {
    p_id: String(form.get("id") ?? ""),
    p_due: String(form.get("due") ?? ""),
    p_amount: amount,
    p_on: date,
    p_key: key ? `rec:${key}` : null,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  return { ok: `Recorded ${peso(amount)}.` };
}

export async function skipRecurring(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("skip_recurring", { p_id: String(form.get("id") ?? ""), p_due: String(form.get("due") ?? "") });
  revalidatePath("/", "layout");
}

export async function stopRecurring(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("stop_recurring", { p_id: String(form.get("id") ?? "") });
  revalidatePath("/", "layout");
  redirect("/repeating");
}
