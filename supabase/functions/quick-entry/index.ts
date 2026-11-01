// KABAN quick-entry endpoint for Apple Shortcuts (Back Tap) and Android shortcuts.
//
//   POST /functions/v1/quick-entry          log an expense {amount, category, account?, request_id?}
//   GET  /functions/v1/quick-entry/options  {names: [categories], accounts: [accounts]} for the menus
//
// Auth: "Authorization: Bearer kbn_qe_<64 hex>" — a quick-entry token, NOT a Supabase key.
// The service_role key lives only in this function's secrets and never leaves the server.
// All permission checks (token validity, expiry, revocation, membership, amount cap,
// daily limit, allowed accounts) happen inside Postgres in quick_entry_submit().
//
// Deploy with JWT verification off (the token is not a Supabase JWT):
//   supabase functions deploy quick-entry --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const TOKEN_RE = /^kbn_qe_[0-9a-f]{64}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 2048;

// Best-effort brake on token guessing per instance. The real limits (daily cap,
// amount cap) are enforced in the database and survive cold starts.
const failures = new Map<string, { n: number; until: number }>();
function tooManyFailures(ip: string): boolean {
  const f = failures.get(ip);
  return !!f && f.n >= 10 && Date.now() < f.until;
}
function noteFailure(ip: string) {
  const f = failures.get(ip) ?? { n: 0, until: 0 };
  f.n += 1;
  f.until = Date.now() + 15 * 60_000;
  failures.set(ip, f);
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

// Map database errors to safe, generic messages. Never echo internals.
function fail(err: { message?: string } | null) {
  const msg = err?.message ?? "";
  if (msg.includes("invalid token")) return json(401, { ok: false, error: "Token invalid, expired or revoked" });
  if (msg.includes("daily quick-entry limit")) return json(429, { ok: false, error: "Daily limit reached" });
  if (msg.includes("amount must be")) return json(422, { ok: false, error: "Amount outside allowed range" });
  if (msg.includes("not allowed") || msg.includes("not available")) {
    return json(403, { ok: false, error: "Not allowed for this token" });
  }
  console.error("quick-entry error", msg);
  return json(400, { ok: false, error: "Could not save entry" });
}

// "250", "250.5", "₱1,250.75" -> centavos (bigint-safe integer), or null
function toCentavos(input: unknown): number | null {
  const s = String(input ?? "").replace(/[₱,\s]/g, "");
  if (!/^\d{1,7}(\.\d{1,2})?$/.test(s)) return null;
  const [whole, frac = ""] = s.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

Deno.serve(async (req) => {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  if (tooManyFailures(ip)) return json(429, { ok: false, error: "Too many attempts" });

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!TOKEN_RE.test(token)) {
    noteFailure(ip);
    return json(401, { ok: false, error: "Missing or malformed token" });
  }

  const url = new URL(req.url);

  // One call gives the Shortcut both menus: category names and account names.
  // Plain string lists feed straight into "Choose from List". No amounts, no balances.
  if (req.method === "GET" && (url.pathname.endsWith("/options") || url.pathname.endsWith("/categories"))) {
    const [cats, accts] = await Promise.all([
      supabase.rpc("quick_entry_categories", { p_token: token }),
      supabase.rpc("quick_entry_accounts", { p_token: token }),
    ]);
    const error = cats.error ?? accts.error;
    if (error) {
      if (error.message.includes("invalid token")) noteFailure(ip);
      return fail(error);
    }
    // Accounts arrive sorted by group, then your own order. Build:
    //   groups: ["Cash", "E-wallet", "Credit Card"]
    //   "E-wallet": ["GoTyme", "GCash", "Maya"], ... (one key per group, for the second menu)
    const rows = (accts.data ?? []) as { name: string; menu_group: string }[];
    const byGroup: Record<string, string[]> = {};
    for (const a of rows) (byGroup[a.menu_group] ??= []).push(a.name);
    return json(200, {
      ok: true,
      names: (cats.data ?? []).map((c: { name: string }) => c.name),
      accounts: rows.map((a) => a.name),
      groups: Object.keys(byGroup),
      ...byGroup,
    });
  }

  if (req.method !== "POST") return json(405, { ok: false, error: "Use POST" });

  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return json(413, { ok: false, error: "Body too large" });

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return json(400, { ok: false, error: "Body must be JSON" });
  }

  const amount = toCentavos(body.amount);
  if (amount === null || amount <= 0) return json(422, { ok: false, error: "Amount must be a positive number" });
  // Accept a category id, or a category name as picked in the Shortcut ("Pagkain").
  let categoryId: string | null = null;
  if (typeof body.category_id === "string" && UUID_RE.test(body.category_id)) {
    categoryId = body.category_id;
  } else if (typeof body.category === "string" && body.category.trim()) {
    const { data: cats, error: catErr } = await supabase.rpc("quick_entry_categories", { p_token: token });
    if (catErr) {
      if (catErr.message.includes("invalid token")) noteFailure(ip);
      return fail(catErr);
    }
    const wanted = body.category.trim().toLowerCase();
    categoryId = (cats ?? []).find((c: { id: string; name: string }) => c.name.toLowerCase() === wanted)?.id ?? null;
    if (!categoryId) return json(422, { ok: false, error: "Unknown category" });
  } else {
    return json(422, { ok: false, error: "category or category_id required" });
  }
  // Account: an id, a name as picked in the Shortcut ("GCash"), or omitted (token's default).
  let accountId: string | null = null;
  let accountName: string | null = null;
  if (body.account_id != null) {
    if (typeof body.account_id !== "string" || !UUID_RE.test(body.account_id)) {
      return json(422, { ok: false, error: "account_id invalid" });
    }
    accountId = body.account_id;
  } else if (typeof body.account === "string" && body.account.trim()) {
    const { data: accts, error: accErr } = await supabase.rpc("quick_entry_accounts", { p_token: token });
    if (accErr) {
      if (accErr.message.includes("invalid token")) noteFailure(ip);
      return fail(accErr);
    }
    const wanted = body.account.trim().toLowerCase();
    const list = (accts ?? []) as { id: string; name: string; menu_group: string }[];
    // Exact account name; or a group name that holds exactly one account (e.g. "Cash").
    const inGroup = list.filter((a) => a.menu_group.toLowerCase() === wanted);
    const hit = list.find((a) => a.name.toLowerCase() === wanted) ?? (inGroup.length === 1 ? inGroup[0] : undefined);
    if (!hit) return json(422, { ok: false, error: "Unknown account" });
    accountId = hit.id;
    accountName = hit.name;
  }

  // The Shortcut sends a fresh UUID per tap; a network retry reuses it and logs once.
  const idem = typeof body.request_id === "string" ? body.request_id.slice(0, 80) : crypto.randomUUID();

  const { data, error } = await supabase.rpc("quick_entry_submit", {
    p_token: token,
    p_amount: amount,
    p_category_id: categoryId,
    p_type: "expense",
    p_account_id: accountId,
    p_note: typeof body.note === "string" ? body.note.slice(0, 200) : null,
    p_idempotency_key: idem,
  });

  if (error) {
    if (error.message.includes("invalid token")) noteFailure(ip);
    return fail(error);
  }

  // Confirmation only: no balances, no history.
  return json(201, {
    ok: true,
    message: `Logged ₱${(amount / 100).toLocaleString("en-PH", { minimumFractionDigits: 2 })} · ${data.category}` +
      (accountName ? ` · ${accountName}` : ""),
    transaction_id: data.transaction_id,
  });
});
