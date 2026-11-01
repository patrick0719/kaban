import type { Account } from "./shared";
import type { createClient } from "./supabase/server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

export type TxnType =
  | "income"
  | "expense"
  | "bill_payment"
  | "refund"
  | "transfer"
  | "savings_contribution"
  | "opening_balance"
  | "adjustment";

export type Txn = {
  id: string;
  type: TxnType;
  status: "posted" | "scheduled" | "void";
  occurred_on: string;
  description: string | null;
  source: "app" | "quick_entry" | "import" | "system";
  created_by: string;
  created_at: string;
  categories: { name: string } | null;
  ledger_entries: { amount: number; account_id: string }[];
};

const SELECT =
  "id, type, status, occurred_on, description, source, created_by, created_at, categories(name), ledger_entries(amount, account_id)";

export async function getTransactions(
  supabase: Supabase,
  householdId: string,
  opts: { limit?: number; from?: string; to?: string; includeVoid?: boolean } = {},
) {
  let q = supabase
    .from("transactions")
    .select(SELECT)
    .eq("household_id", householdId)
    .order("occurred_on", { ascending: false })
    .order("created_at", { ascending: false });
  if (!opts.includeVoid) q = q.neq("status", "void");
  if (opts.from) q = q.gte("occurred_on", opts.from);
  if (opts.to) q = q.lt("occurred_on", opts.to);
  if (opts.limit) q = q.limit(opts.limit);
  const { data } = await q;
  return (data ?? []) as unknown as Txn[];
}

export async function getTransaction(supabase: Supabase, id: string) {
  const { data } = await supabase.from("transactions").select(SELECT).eq("id", id).maybeSingle();
  return data as unknown as Txn | null;
}

export type TxnView = {
  title: string;
  detail: string;
  amount: number; // signed for display: negative = money out of the household
  tone: "out" | "in" | "move";
};

/** How a transaction reads in a list, from the household's point of view. */
export function describe(t: Txn, accounts: Map<string, Account>): TxnView {
  const entries = t.ledger_entries ?? [];
  const name = (id: string) => accounts.get(id)?.name ?? "Personal account";
  const first = entries[0];
  const total = entries.reduce((s, e) => s + Number(e.amount), 0);

  switch (t.type) {
    case "expense":
    case "bill_payment":
      return {
        title: t.categories?.name ?? "Gastos",
        detail: [first ? name(first.account_id) : null, t.description].filter(Boolean).join(", "),
        amount: total,
        tone: "out",
      };
    case "income":
    case "refund":
      return {
        title: t.type === "refund" ? `Refund: ${t.categories?.name ?? ""}`.trim() : (t.categories?.name ?? "Kita"),
        detail: [first ? name(first.account_id) : null, t.description].filter(Boolean).join(", "),
        amount: total,
        tone: "in",
      };
    case "transfer":
    case "savings_contribution": {
      const from = entries.find((e) => Number(e.amount) < 0);
      const to = entries.find((e) => Number(e.amount) > 0);
      const toAcc = to ? accounts.get(to.account_id) : undefined;
      const title =
        t.type === "savings_contribution"
          ? "Inipon"
          : toAcc?.class === "liability"
            ? `Bayad sa ${toAcc.name}`
            : "Lipat";
      return {
        title,
        detail: `${from ? name(from.account_id) : "?"} papunta sa ${to ? name(to.account_id) : "?"}`,
        amount: Math.abs(Number(to?.amount ?? from?.amount ?? 0)),
        tone: "move",
      };
    }
    case "opening_balance":
    case "adjustment":
      return {
        title: t.type === "opening_balance" ? "Simulang balanse" : "Pagtatama ng balanse",
        detail: first ? name(first.account_id) : "",
        amount: total,
        tone: "move",
      };
  }
}
