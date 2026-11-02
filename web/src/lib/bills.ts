import type { createClient } from "./supabase/server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

export type Occurrence = {
  id: string;
  bill_id: string;
  name: string;
  due_on: string;
  amount_due: number;
  paid: number;
  remaining: number;
  is_skipped: boolean;
  owner_user_id: string | null;
  pay_from_account_id: string | null;
};

export type Bill = {
  id: string;
  name: string;
  category_id: string;
  estimated_amount: number;
  starts_on: string;
  recurrence_months: number | null;
  pay_from_account_id: string | null;
  settles_account_id: string | null;
  owner_user_id: string | null;
  is_active: boolean;
};

const OCC = "id, bill_id, name, due_on, amount_due, paid, remaining, is_skipped, owner_user_id, pay_from_account_id";
const BILL =
  "id, name, category_id, estimated_amount, starts_on, recurrence_months, pay_from_account_id, settles_account_id, owner_user_id, is_active";

export function addDays(iso: string, days: number) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

export function daysBetween(fromIso: string, toIso: string) {
  return Math.round((Date.parse(`${toIso}T00:00:00Z`) - Date.parse(`${fromIso}T00:00:00Z`)) / 864e5);
}

/** Bills grouped the way people think about them: overdue, coming up, later, recently paid. */
export async function getBillOverview(supabase: Supabase, householdId: string, today: string, soonDays: number) {
  const [{ data: occ }, { data: bills }] = await Promise.all([
    supabase
      .from("bill_occurrence_status")
      .select(OCC)
      .eq("household_id", householdId)
      .lte("due_on", addDays(today, 400))
      .or(`due_on.gte.${addDays(today, -40)},remaining.gt.0`)
      .order("due_on"),
    supabase.from("bills").select(BILL).eq("household_id", householdId),
  ]);
  const all = ((occ ?? []) as Occurrence[]).map((o) => ({ ...o, paid: Number(o.paid), remaining: Number(o.remaining), amount_due: Number(o.amount_due) }));
  const billById = new Map(((bills ?? []) as Bill[]).map((b) => [b.id, b]));

  const open = all.filter((o) => o.remaining > 0 && !o.is_skipped);
  const overdue = open.filter((o) => o.due_on < today);

  // The next unpaid due date of each bill (one row per bill).
  const nextByBill = new Map<string, Occurrence>();
  for (const o of open) if (o.due_on >= today && !nextByBill.has(o.bill_id)) nextByBill.set(o.bill_id, o);
  const upcoming = [...nextByBill.values()].sort((a, b) => a.due_on.localeCompare(b.due_on));
  const soonLimit = addDays(today, soonDays);

  const paid = all
    .filter((o) => o.paid > 0 && o.remaining === 0 && o.due_on >= addDays(today, -40))
    .sort((a, b) => b.due_on.localeCompare(a.due_on));

  return {
    billById,
    overdue,
    soon: upcoming.filter((o) => o.due_on <= soonLimit),
    later: upcoming.filter((o) => o.due_on > soonLimit),
    paid,
    hasBills: billById.size > 0,
  };
}

export async function getOccurrence(supabase: Supabase, id: string) {
  const { data } = await supabase.from("bill_occurrence_status").select(OCC).eq("id", id).maybeSingle();
  if (!data) return null;
  const o = data as Occurrence;
  return { ...o, paid: Number(o.paid), remaining: Number(o.remaining), amount_due: Number(o.amount_due) };
}

export async function getBill(supabase: Supabase, id: string) {
  const { data } = await supabase.from("bills").select(BILL).eq("id", id).maybeSingle();
  return (data as Bill | null) ?? null;
}

export const REPEAT_LABEL: Record<string, string> = {
  "1": "Every month",
  "2": "Every 2 months",
  "3": "Every 3 months",
  "6": "Every 6 months",
  "12": "Every year",
  "": "One time",
};
