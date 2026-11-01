"use server";

import { revalidatePath } from "next/cache";
import { getContext } from "@/lib/context";
import { friendly } from "@/lib/errors";

export type FormState = { error?: string; ok?: string; token?: string };

export async function invite(_: FormState, form: FormData): Promise<FormState> {
  const { supabase, householdId, isAdmin } = await getContext();
  if (!isAdmin) return { error: friendly("only owners and admins") };
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  const role = String(form.get("role") ?? "member");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return { error: "Ilagay ang buong email address." };

  const { error } = await supabase.rpc("invite_member", { p_household: householdId, p_email: email, p_role: role });
  if (error) return { error: friendly(error.message) };
  revalidatePath("/household");
  return { ok: `Na-invite si ${email}. Sabihan siyang buksan ang KABAN at gumawa ng account gamit ang email na ito.` };
}

export async function revokeInvite(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("revoke_invite", { p_invite: String(form.get("id")) });
  revalidatePath("/household");
}

/** A Back Tap token for the signed-in user: expenses only, from shared money accounts and cards. */
export async function createToken(_: FormState, form: FormData): Promise<FormState> {
  const { supabase, householdId, canWrite } = await getContext();
  if (!canWrite) return { error: friendly("not allowed to write") };
  const label = String(form.get("label") ?? "").trim() || "iPhone";

  const { data: accounts } = await supabase
    .from("accounts")
    .select("id, name, kind, class, is_spendable, display_order")
    .eq("household_id", householdId)
    .eq("is_archived", false)
    .is("owner_user_id", null);
  const usable = (accounts ?? []).filter((a) => a.is_spendable || a.class === "liability");
  if (usable.length === 0) return { error: "Wala pang account na puwedeng gastusin." };
  const def = usable.find((a) => a.kind === "cash") ?? usable[0];

  const { data, error } = await supabase
    .rpc("create_quick_entry_token", {
      p_household: householdId,
      p_label: label.slice(0, 40),
      p_default_account: def.id,
      p_allowed_accounts: usable.filter((a) => a.id !== def.id).map((a) => a.id),
    })
    .single<{ token: string }>();
  if (error || !data) return { error: friendly(error?.message) };
  revalidatePath("/household");
  return { token: data.token };
}

export async function revokeToken(form: FormData) {
  const { supabase } = await getContext();
  await supabase.rpc("revoke_quick_entry_token", { p_token_id: String(form.get("id")) });
  revalidatePath("/household");
}
