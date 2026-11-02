import Link from "next/link";
import { getContext } from "@/lib/context";
import { shortDate } from "@/lib/money";
import { signOut } from "@/app/login/actions";
import { InviteForm, TokenForm } from "./Forms";
import { revokeInvite, revokeToken } from "./actions";
import { ReminderToggle } from "./ReminderToggle";
import { getVapidPublicKey, setRemindDays } from "./reminders";

const ROLE: Record<string, string> = { owner: "Owner", admin: "Admin", member: "Member", viewer: "Viewer" };

export default async function HouseholdPage() {
  const ctx = await getContext();
  const { supabase, householdId, user, household, isAdmin } = ctx;

  const [{ data: members }, { data: invites }, { data: tokens }, vapidKey] = await Promise.all([
    supabase.from("household_members").select("user_id, role, joined_at").eq("household_id", householdId).order("joined_at"),
    supabase
      .from("household_invites")
      .select("id, email, role, accepted_by, accepted_at, revoked_at, expires_at")
      .eq("household_id", householdId)
      .order("created_at", { ascending: false }),
    supabase
      .from("quick_entry_tokens")
      .select("id, label, token_prefix, last_used_at, expires_at")
      .eq("user_id", user.id)
      .is("revoked_at", null)
      .order("created_at", { ascending: false }),
    getVapidPublicKey(),
  ]);

  // Members don't expose emails; invites tell us who joined with which email.
  const emailOf = new Map((invites ?? []).filter((i) => i.accepted_by).map((i) => [i.accepted_by as string, i.email as string]));
  const now = new Date().toISOString();
  const pending = (invites ?? []).filter((i) => !i.accepted_at && !i.revoked_at && i.expires_at > now);
  const liveTokens = (tokens ?? []).filter((t) => t.expires_at > now);

  return (
    <div>
      <h1 className="text-[24px] font-semibold tracking-tight">{household.name}</h1>

      <Link href="/accounts" className="mt-6 flex items-baseline justify-between border-y border-line py-3 text-[15px] active:bg-line/40">
        <span>
          Accounts
          <span className="block text-[13px] text-muted">Balances, and correcting them to what you really have</span>
        </span>
        <span aria-hidden="true" className="text-muted">›</span>
      </Link>

      <section className="mt-8">
        <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Bill reminders</h2>
        <div className="pt-3">
          <ReminderToggle vapidKey={vapidKey} />
        </div>
        {isAdmin ? (
          <form action={setRemindDays} className="mt-4 flex items-center justify-between gap-3 text-[15px]">
            <label htmlFor="days">Remind before the due date</label>
            <span className="flex items-center gap-2">
              <select id="days" name="days" defaultValue={String(household.remind_days_before)} className="field w-auto py-2">
                <option value="0">Same day only</option>
                <option value="1">1 day</option>
                <option value="2">2 days</option>
                <option value="3">3 days</option>
                <option value="5">5 days</option>
                <option value="7">7 days</option>
              </select>
              <button className="text-[14px] text-jade underline underline-offset-4">Save</button>
            </span>
          </form>
        ) : null}
        <p className="mt-3 text-[13px] text-muted">
          {household.remind_days_before === 0
            ? "You get a reminder on the due date, and the day after if a bill is still unpaid."
            : `You get a reminder ${household.remind_days_before} day${household.remind_days_before === 1 ? "" : "s"} before, on the due date, and the day after if a bill is still unpaid.`}
        </p>
      </section>

      <section className="mt-10">
        <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Members</h2>
        <ul className="divide-y divide-line">
          {(members ?? []).map((m) => (
            <li key={m.user_id} className="flex items-baseline justify-between py-3 text-[15px]">
              <span className="truncate">{m.user_id === user.id ? `You (${user.email})` : (emailOf.get(m.user_id) ?? "Member")}</span>
              <span className="shrink-0 pl-3 text-[13px] text-muted">{ROLE[m.role]}</span>
            </li>
          ))}
          {pending.map((i) => (
            <li key={i.id} className="flex items-baseline justify-between gap-3 py-3 text-[15px]">
              <span className="min-w-0">
                <span className="block truncate">{i.email}</span>
                <span className="block text-[13px] text-muted">
                  Not joined yet. Invite valid until {shortDate(i.expires_at.slice(0, 10))}.
                </span>
              </span>
              {isAdmin && (
                <form action={revokeInvite}>
                  <input type="hidden" name="id" value={i.id} />
                  <button className="text-[13px] text-rust underline underline-offset-2">Cancel invite</button>
                </form>
              )}
            </li>
          ))}
        </ul>
        {isAdmin && (
          <div className="mt-4">
            <InviteForm />
          </div>
        )}
      </section>

      <section className="mt-10">
        <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Your Back Tap</h2>
        <ul className="divide-y divide-line">
          {liveTokens.map((t) => (
            <li key={t.id} className="flex items-baseline justify-between gap-3 py-3 text-[15px]">
              <span className="min-w-0">
                <span className="block truncate">{t.label}</span>
                <span className="block text-[13px] text-muted">
                  {t.last_used_at ? `Last used ${shortDate(t.last_used_at.slice(0, 10))}` : "Not used yet"}, valid until{" "}
                  {shortDate(t.expires_at.slice(0, 10))}
                </span>
              </span>
              <form action={revokeToken}>
                <input type="hidden" name="id" value={t.id} />
                <button className="text-[13px] text-rust underline underline-offset-2">Revoke</button>
              </form>
            </li>
          ))}
        </ul>
        <p className="mb-3 mt-3 text-[13px] text-muted">
          {liveTokens.length === 0
            ? "You have no active Back Tap token. Create one for the shortcut on your iPhone."
            : "If a phone is lost or replaced, revoke its token and create a new one."}
        </p>
        <TokenForm />
      </section>

      <form action={signOut} className="mt-12">
        <button className="btn-quiet w-full">Log out</button>
      </form>
    </div>
  );
}
