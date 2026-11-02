// KABAN bill reminders: Web Push notifications before bills are due.
//
//   GET  /functions/v1/bill-reminders/public-key   VAPID public key for the app (not secret)
//   POST /functions/v1/bill-reminders              x-cron-secret: <CRON_SECRET>
//        -> sends today's reminders (called once a day by pg_cron)
//   POST /functions/v1/bill-reminders              Authorization: Bearer <user's session token>
//        body {"mode":"test"} -> sends a test notification to that person's devices
//
// Secrets (Edge Functions -> Secrets): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY,
// VAPID_SUBJECT (mailto:you@example.com), CRON_SECRET.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
//
// Deploy with JWT verification OFF: the cron call carries a secret header,
// and test calls are verified here against Supabase Auth.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@example.com",
  VAPID_PUBLIC,
  Deno.env.get("VAPID_PRIVATE_KEY") ?? "",
);

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

const pesoFmt = new Intl.NumberFormat("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const peso = (centavos: number) => `₱${pesoFmt.format(centavos / 100)}`;
const dayFmt = new Intl.DateTimeFormat("en-PH", { month: "short", day: "numeric", timeZone: "UTC" });
const day = (iso: string) => dayFmt.format(new Date(`${iso}T00:00:00Z`));

type Reminder = {
  user_id: string;
  occurrence_id: string;
  kind: "before" | "due" | "overdue";
  bill_name: string;
  due_on: string;
  amount_left: number;
  days_left: number;
};
type Sub = { id: string; user_id: string; endpoint: string; p256dh: string; auth: string };
type Payload = { title: string; body: string; tag: string; url: string };

export function message(r: Reminder): Payload {
  const title =
    r.kind === "overdue"
      ? `${r.bill_name} is overdue`
      : r.kind === "due"
        ? `${r.bill_name} is due today`
        : `${r.bill_name} is due in ${r.days_left} day${r.days_left === 1 ? "" : "s"}`;
  const body =
    r.kind === "overdue"
      ? `${peso(r.amount_left)} was due ${day(r.due_on)}. Tap to record the payment.`
      : `${peso(r.amount_left)} due ${day(r.due_on)}. Tap to pay or mark it paid.`;
  return { title, body, tag: `bill-${r.occurrence_id}`, url: `/bills/${r.occurrence_id}` };
}

/** Send to one device. Returns "sent", "gone" (device unsubscribed) or "failed". */
async function push(sub: Sub, payload: Payload): Promise<"sent" | "gone" | "failed"> {
  try {
    await webpush.sendNotification(
      { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
      JSON.stringify(payload),
      { TTL: 60 * 60 * 20, urgency: "normal" },
    );
    return "sent";
  } catch (e) {
    const status = (e as { statusCode?: number }).statusCode;
    if (status === 404 || status === 410) return "gone";
    console.error("push failed", status, (e as Error).message);
    return "failed";
  }
}

async function devicesOf(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, Sub[]>();
  const { data, error } = await supabase
    .from("push_subscriptions")
    .select("id, user_id, endpoint, p256dh, auth")
    .in("user_id", userIds);
  if (error) throw error;
  const map = new Map<string, Sub[]>();
  for (const s of (data ?? []) as Sub[]) map.set(s.user_id, [...(map.get(s.user_id) ?? []), s]);
  return map;
}

async function forget(gone: string[]) {
  if (gone.length) await supabase.from("push_subscriptions").delete().in("id", gone);
}

async function runReminders() {
  const { data, error } = await supabase.rpc("bill_reminders_due");
  if (error) throw error;
  const reminders = (data ?? []) as Reminder[];
  const devices = await devicesOf([...new Set(reminders.map((r) => r.user_id))]);

  const delivered: { user_id: string; occurrence_id: string; kind: string }[] = [];
  const gone = new Set<string>();
  const sentTo = new Set<string>();
  for (const r of reminders) {
    let reached = false;
    for (const d of devices.get(r.user_id) ?? []) {
      if (gone.has(d.id)) continue; // unsubscribed device: don't try it again this run
      const result = await push(d, message(r));
      if (result === "sent") {
        reached = true;
        sentTo.add(d.id);
      }
      if (result === "gone") gone.add(d.id);
    }
    // Only mark as sent if at least one device got it; otherwise tomorrow's run tries again.
    if (reached) delivered.push({ user_id: r.user_id, occurrence_id: r.occurrence_id, kind: r.kind });
  }

  if (delivered.length) await supabase.rpc("mark_bill_reminders_sent", { p_items: delivered });
  if (sentTo.size) {
    await supabase.from("push_subscriptions").update({ last_sent_at: new Date().toISOString() }).in("id", [...sentTo]);
  }
  await forget([...gone]);
  return { reminders: reminders.length, delivered: delivered.length, removed_devices: gone.size };
}

async function runTest(userId: string) {
  const devices = (await devicesOf([userId])).get(userId) ?? [];
  if (devices.length === 0) return { ok: false, error: "No device is set up for reminders yet." };
  const gone: string[] = [];
  let sent = 0;
  for (const d of devices) {
    const result = await push(d, {
      title: "KABAN reminders are on",
      body: "You'll get a notice before each bill is due.",
      tag: "kaban-test",
      url: "/bills",
    });
    if (result === "sent") sent++;
    if (result === "gone") gone.push(d.id);
  }
  await forget(gone);
  return sent > 0
    ? { ok: true, sent }
    : { ok: false, error: "Could not reach this device. Turn reminders off and on again." };
}

/** Constant-time string comparison for the cron secret. */
function sameSecret(a: string, b: string) {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length || x.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

export async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);

  if (req.method === "GET" && url.pathname.endsWith("/public-key")) {
    return VAPID_PUBLIC ? json(200, { key: VAPID_PUBLIC }) : json(503, { error: "VAPID_PUBLIC_KEY is not set" });
  }
  if (req.method !== "POST") return json(405, { error: "Use POST" });

  try {
    const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
    if (sameSecret(req.headers.get("x-cron-secret") ?? "", cronSecret)) {
      return json(200, await runReminders());
    }

    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const body = await req.json().catch(() => ({}));
    if (token && body?.mode === "test") {
      const { data, error } = await supabase.auth.getUser(token);
      if (error || !data.user) return json(401, { error: "Sign in again." });
      return json(200, await runTest(data.user.id));
    }
    return json(401, { error: "Not allowed" });
  } catch (e) {
    console.error("bill-reminders error", (e as Error).message);
    return json(500, { error: "Reminder run failed" });
  }
}

Deno.serve(handler);
