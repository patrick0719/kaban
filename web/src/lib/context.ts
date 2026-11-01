import { redirect } from "next/navigation";
import { createClient } from "./supabase/server";

import { GROUP_ORDER, type Account, type Category, type Role } from "./shared";
export { GROUP_LABEL, groupAccounts, type Account, type Category, type Role } from "./shared";

/** The signed-in user and their household. Redirects if either is missing. */
export async function getContext() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: membership } = await supabase
    .from("household_members")
    .select("household_id, role, households(name, card_debt_mode, reserve_days, reserve_horizon)")
    .eq("user_id", user.id)
    .order("joined_at")
    .limit(1)
    .maybeSingle();

  if (!membership) redirect("/welcome");

  const household = membership.households as unknown as {
    name: string;
    card_debt_mode: "statement" | "full";
    reserve_days: number;
    reserve_horizon: string;
  };

  return {
    supabase,
    user,
    householdId: membership.household_id as string,
    role: membership.role as Role,
    household,
    canWrite: membership.role !== "viewer",
    isAdmin: membership.role === "owner" || membership.role === "admin",
  };
}

type Ctx = Awaited<ReturnType<typeof getContext>>;

/** Active accounts with balances, in menu order. */
export async function getAccounts({ supabase, householdId }: Pick<Ctx, "supabase" | "householdId">) {
  const [{ data: accounts }, { data: balances }] = await Promise.all([
    supabase
      .from("accounts")
      .select("id, name, kind, class, is_spendable, display_order, owner_user_id")
      .eq("household_id", householdId)
      .eq("is_archived", false),
    supabase.from("account_balances").select("account_id, balance").eq("household_id", householdId),
  ]);
  const bal = new Map((balances ?? []).map((b) => [b.account_id as string, Number(b.balance)]));
  return ((accounts ?? []) as Omit<Account, "balance">[])
    .map((a) => ({ ...a, balance: bal.get(a.id) ?? 0 }))
    .sort((x, y) => GROUP_ORDER[x.kind] - GROUP_ORDER[y.kind] || x.display_order - y.display_order || x.name.localeCompare(y.name));
}

export async function getCategories({ supabase, householdId }: Pick<Ctx, "supabase" | "householdId">) {
  const { data } = await supabase
    .from("categories")
    .select("id, name, kind")
    .eq("household_id", householdId)
    .eq("is_archived", false)
    .order("name");
  return (data ?? []) as Category[];
}
