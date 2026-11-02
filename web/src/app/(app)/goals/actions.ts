"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getContext } from "@/lib/context";
import { peso, toCentavos } from "@/lib/money";
import { friendly } from "@/lib/errors";

export type GoalState = { error?: string; ok?: string };
const ISO = /^\d{4}-\d{2}-\d{2}$/;

export async function saveGoal(_: GoalState, form: FormData): Promise<GoalState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const goalId = String(form.get("goal_id") ?? "") || null;
  const name = String(form.get("name") ?? "").trim();
  const target = toCentavos(String(form.get("target") ?? ""));
  const date = String(form.get("target_date") ?? "");
  const where = String(form.get("where") ?? "earmark"); // "earmark" | "new" | <savings account id>
  const newName = String(form.get("new_account_name") ?? "").trim();

  if (!name) return { error: "Give the goal a name, like Emergency fund." };
  if (!target || target <= 0) return { error: "Enter how much you want to save." };
  if (date && !ISO.test(date)) return { error: "Choose a valid date, or leave it empty." };
  if (!goalId && where === "new" && !newName) return { error: "Name the new savings account, like GoTyme Savings." };

  const { data, error } = await supabase.rpc("save_goal", {
    p_household: householdId,
    p_goal: goalId,
    p_name: name,
    p_target: target,
    p_target_date: date || null,
    p_mode: where === "earmark" ? "earmark" : "account",
    p_account: where === "earmark" || where === "new" ? null : where,
    p_new_account_name: where === "new" ? newName : null,
    p_personal: form.get("personal") === "on",
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  redirect(`/goals/${data}`);
}

export async function moveGoalMoney(_: GoalState, form: FormData): Promise<GoalState> {
  const { supabase, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const direction = String(form.get("direction")); // "add" | "take"
  const amount = toCentavos(String(form.get("amount") ?? ""));
  const account = String(form.get("account") ?? "");
  const key = String(form.get("request_id") ?? "") || null;
  if (!amount || amount <= 0) return { error: "Enter an amount, like 1,000." };
  if (!account) return { error: direction === "add" ? "Choose where the money comes from." : "Choose where the money goes." };

  const { error } = await supabase.rpc(direction === "add" ? "add_to_goal" : "take_from_goal", {
    p_goal: String(form.get("goal_id") ?? ""),
    p_account: account,
    p_amount: amount,
    p_key: key ? `goal:${key}` : null,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  return { ok: direction === "add" ? `Added ${peso(amount)}.` : `Took out ${peso(amount)}.` };
}

export async function archiveGoal(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("archive_goal", { p_goal: String(form.get("goal_id") ?? "") });
  revalidatePath("/", "layout");
  redirect("/goals");
}
