"use server";

import { revalidatePath } from "next/cache";
import { getContext } from "@/lib/context";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/supabase/server";

const FN = `${SUPABASE_URL}/functions/v1/bill-reminders`;

/** The public half of the push key pair, from the bill-reminders function. Null if not set up yet. */
export async function getVapidPublicKey(): Promise<string | null> {
  try {
    const r = await fetch(`${FN}/public-key`, {
      headers: { apikey: SUPABASE_KEY },
      next: { revalidate: 3600 },
      signal: AbortSignal.timeout(4000),
    });
    if (!r.ok) return null;
    const { key } = (await r.json()) as { key?: string };
    return key ?? null;
  } catch {
    return null;
  }
}

type SubJSON = { endpoint?: string; keys?: { p256dh?: string; auth?: string } };

export async function savePushSubscription(sub: SubJSON, device: string): Promise<{ error?: string }> {
  const { supabase } = await getContext();
  if (!sub.endpoint || !sub.keys?.p256dh || !sub.keys?.auth) return { error: "This browser did not return a push address." };
  const { error } = await supabase.rpc("save_push_subscription", {
    p_endpoint: sub.endpoint,
    p_p256dh: sub.keys.p256dh,
    p_auth: sub.keys.auth,
    p_device: device.slice(0, 80),
  });
  return error ? { error: "Could not save this device. Try again." } : {};
}

export async function removePushSubscription(endpoint: string) {
  const { supabase } = await getContext();
  await supabase.rpc("remove_push_subscription", { p_endpoint: endpoint });
}

export async function sendTestReminder(): Promise<{ ok?: string; error?: string }> {
  const { supabase } = await getContext();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return { error: "Sign in again." };
  try {
    const r = await fetch(FN, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${session.access_token}`, apikey: SUPABASE_KEY },
      body: JSON.stringify({ mode: "test" }),
      signal: AbortSignal.timeout(10000),
    });
    const body = (await r.json().catch(() => ({}))) as { ok?: boolean; error?: string };
    return body.ok ? { ok: "Sent. It should appear in a few seconds." } : { error: body.error ?? "Could not send the test." };
  } catch {
    return { error: "Could not reach the reminder service." };
  }
}

export async function setRemindDays(_: { ok?: string; error?: string }, form: FormData): Promise<{ ok?: string; error?: string }> {
  const { supabase, householdId, isAdmin } = await getContext();
  if (!isAdmin) return { error: "Only owners and admins can change this." };
  const days = Number(form.get("days"));
  if (!Number.isInteger(days) || days < 0 || days > 14) return { error: "Choose a number of days." };
  const { error } = await supabase.from("households").update({ remind_days_before: days }).eq("id", householdId);
  if (error) return { error: "Could not save. Try again." };
  revalidatePath("/household");
  return { ok: days === 0 ? "Saved. Reminders come on the due date." : `Saved. Reminders come ${days} day${days === 1 ? "" : "s"} before.` };
}
