// Types and labels safe to import from both server and client components.

export type Role = "owner" | "admin" | "member" | "viewer";

export type Account = {
  id: string;
  name: string;
  kind: "cash" | "bank" | "ewallet" | "savings" | "credit_card" | "loan" | "other";
  class: "asset" | "liability";
  is_spendable: boolean;
  display_order: number;
  owner_user_id: string | null;
  balance: number;
};

export type Category = { id: string; name: string; kind: "income" | "expense" };

export const GROUP_ORDER: Record<Account["kind"], number> = {
  cash: 1,
  ewallet: 2,
  bank: 3,
  credit_card: 4,
  loan: 4,
  savings: 5,
  other: 6,
};

export const GROUP_LABEL: Record<Account["kind"], string> = {
  cash: "Cash",
  ewallet: "E-wallet",
  bank: "Bangko",
  credit_card: "Credit card",
  loan: "Credit card",
  savings: "Ipon",
  other: "Iba pa",
};

/** Accounts grouped for display: [["Cash", [...]], ["E-wallet", [...]], ...] */
export function groupAccounts(accounts: Account[]): [string, Account[]][] {
  const groups = new Map<string, Account[]>();
  for (const a of accounts) {
    const label = GROUP_LABEL[a.kind];
    groups.set(label, [...(groups.get(label) ?? []), a]);
  }
  return [...groups.entries()];
}
