"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getContext } from "@/lib/context";
import { friendly } from "@/lib/errors";

export type VoidState = { error?: string };

export async function voidTransaction(_: VoidState, form: FormData): Promise<VoidState> {
  const { supabase } = await getContext();
  const id = String(form.get("id") ?? "");
  const reason = String(form.get("reason") ?? "").trim() || null;
  const { error } = await supabase.rpc("void_transaction", { p_txn: id, p_reason: reason });
  if (error) return { error: friendly(error.message) };
  revalidatePath("/", "layout");
  redirect("/transactions");
}
