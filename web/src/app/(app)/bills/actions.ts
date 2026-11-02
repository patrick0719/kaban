"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getContext } from "@/lib/context";
import { getBill, getOccurrence } from "@/lib/bills";
import { peso, toCentavos } from "@/lib/money";
import { friendly } from "@/lib/errors";

export type BillState = { error?: string; ok?: string };

const ISO = /^\d{4}-\d{2}-\d{2}$/;

export async function saveBill(_: BillState, form: FormData): Promise<BillState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const billId = String(form.get("bill_id") ?? "") || null;
  const name = String(form.get("name") ?? "").trim();
  const amount = toCentavos(String(form.get("amount") ?? ""));
  const nextDue = String(form.get("next_due") ?? "");
  const repeat = String(form.get("repeat") ?? "1");
  const category = String(form.get("category") ?? "");
  const card = String(form.get("card") ?? "") || null;
  const payFrom = String(form.get("pay_from") ?? "") || null;
  const personal = form.get("personal") === "on";

  if (!name) return { error: "Give the bill a name, like Meralco or Rent." };
  if (!amount || amount <= 0) return { error: "Enter the usual amount, like 3,200." };
  if (!ISO.test(nextDue)) return { error: "Choose the next due date." };
  if (!category) return { error: "Choose a category." };

  const { error } = await supabase.rpc("save_bill", {
    p_household: householdId,
    p_bill: billId,
    p_name: name,
    p_category: category,
    p_amount: amount,
    p_next_due: nextDue,
    p_repeat_months: repeat === "" ? null : Number(repeat),
    p_pay_from: payFrom,
    p_settles: card,
    p_personal: personal,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  redirect("/bills");
}

/** Record a payment. A credit card bill moves money into the card; any other bill is spending. */
export async function payBill(_: BillState, form: FormData): Promise<BillState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };

  const occurrenceId = String(form.get("occurrence_id") ?? "");
  const from = String(form.get("from") ?? "");
  const date = String(form.get("date") ?? "");
  const amount = toCentavos(String(form.get("amount") ?? ""));
  const key = String(form.get("request_id") ?? "") || null;

  const occ = await getOccurrence(supabase, occurrenceId);
  if (!occ) return { error: "Bill not found." };
  const bill = await getBill(supabase, occ.bill_id);
  if (!bill) return { error: "Bill not found." };
  if (!amount || amount <= 0) return { error: "Enter how much you paid." };
  if (amount > occ.remaining) return { error: `That is more than what is left (${peso(occ.remaining)}).` };
  if (!from) return { error: "Choose where the money came from." };
  if (!ISO.test(date)) return { error: "Choose the payment date." };

  const card = bill.settles_account_id;
  const { error } = await supabase.rpc("post_transaction", {
    p_household: householdId,
    p_type: card ? "transfer" : "bill_payment",
    p_occurred_on: date,
    p_entries: card
      ? [
          { account_id: from, amount: -amount },
          { account_id: card, amount },
        ]
      : [{ account_id: from, amount: -amount }],
    p_description: bill.name,
    p_bill_occurrence: occurrenceId,
    p_idempotency_key: key ? `bill:${key}` : null,
  });
  if (error) return { error: friendly(error.message) };

  revalidatePath("/", "layout");
  return { ok: amount === occ.remaining ? `Paid. ${bill.name} is settled.` : `Recorded ${peso(amount)}.` };
}

export async function setAmount(_: BillState, form: FormData): Promise<BillState> {
  const { supabase, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };
  const amount = toCentavos(String(form.get("amount") ?? ""));
  if (!amount || amount <= 0) return { error: "Enter this month's amount." };
  const { error } = await supabase.rpc("set_occurrence_amount", {
    p_occurrence: String(form.get("occurrence_id") ?? ""),
    p_amount: amount,
  });
  if (error) return { error: friendly(error.message) };
  revalidatePath("/", "layout");
  return { ok: `This month is now ${peso(amount)}.` };
}

export async function toggleSkip(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("skip_bill_occurrence", {
    p_occurrence: String(form.get("occurrence_id") ?? ""),
    p_skip: form.get("skip") === "true",
  });
  revalidatePath("/", "layout");
}

export async function stopBill(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("stop_bill", { p_bill: String(form.get("bill_id") ?? "") });
  revalidatePath("/", "layout");
  redirect("/bills");
}
