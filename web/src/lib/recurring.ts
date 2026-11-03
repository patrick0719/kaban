import type { SupabaseClient } from "@supabase/supabase-js";
import { shortDate } from "./money";

export type Frequency = "weekly" | "every_2_weeks" | "monthly" | "twice_a_month";
export type RecurringKind = "income" | "expense" | "transfer";

export type Recurring = {
  id: string;
  name: string;
  kind: RecurringKind;
  amount: number;
  category_id: string | null;
  account_id: string;
  to_account_id: string | null;
  frequency: Frequency;
  day1: number | null;
  day2: number | null;
  next_due: string;
  auto_post: boolean;
  is_active: boolean;
  last_error: string | null;
  owner_user_id: string | null;
};

const COLUMNS =
  "id, name, kind, amount, category_id, account_id, to_account_id, frequency, day1, day2, next_due, auto_post, is_active, last_error, owner_user_id";

function normalize(r: Recurring): Recurring {
  return { ...r, amount: Number(r.amount) };
}

/** Active repeating entries, soonest first. */
export async function getRecurring(supabase: SupabaseClient, householdId: string) {
  const { data } = await supabase
    .from("recurring_entries")
    .select(COLUMNS)
    .eq("household_id", householdId)
    .eq("is_active", true)
    .order("next_due")
    .order("name");
  return ((data ?? []) as Recurring[]).map(normalize);
}

export async function getOneRecurring(supabase: SupabaseClient, id: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await supabase.from("recurring_entries").select(COLUMNS).eq("id", id).maybeSingle();
  return data ? normalize(data as Recurring) : null;
}

/** Ask-first entries that are due, and automatic ones that could not be recorded. */
export function needsAttention(list: Recurring[], today: string) {
  return {
    toConfirm: list.filter((r) => !r.auto_post && r.next_due <= today),
    failed: list.filter((r) => r.auto_post && r.last_error),
  };
}

export const FREQUENCY_LABEL: Record<Frequency, string> = {
  weekly: "Every week",
  every_2_weeks: "Every 2 weeks",
  monthly: "Every month",
  twice_a_month: "Twice a month",
};

/** 31 -> "last day", 1 -> "1st", 15 -> "15th" */
export function dayLabel(d: number) {
  if (d >= 31) return "last day";
  const s = d % 10 === 1 && d !== 11 ? "st" : d % 10 === 2 && d !== 12 ? "nd" : d % 10 === 3 && d !== 13 ? "rd" : "th";
  return `${d}${s}`;
}

/** "Every month on the 5th", "15th and last day of the month", "Every week" */
export function scheduleText(r: Pick<Recurring, "frequency" | "day1" | "day2">) {
  if (r.frequency === "monthly" && r.day1) return `Every month on the ${dayLabel(r.day1)}`;
  if (r.frequency === "twice_a_month" && r.day1 && r.day2) return `The ${dayLabel(r.day1)} and ${dayLabel(r.day2)} of each month`;
  return FREQUENCY_LABEL[r.frequency];
}

export function dueText(due: string, today: string) {
  if (due < today) return `Was due ${shortDate(due)}`;
  if (due === today) return "Due today";
  return `Next ${shortDate(due)}`;
}
