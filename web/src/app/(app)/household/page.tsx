import { getContext } from "@/lib/context";
import { shortDate } from "@/lib/money";
import { signOut } from "@/app/login/actions";
import { InviteForm, TokenForm } from "./Forms";
import { revokeInvite, revokeToken } from "./actions";

const ROLE: Record<string, string> = { owner: "May-ari", admin: "Admin", member: "Member", viewer: "Viewer" };

export default async function HouseholdPage() {
  const ctx = await getContext();
  const { supabase, householdId, user, household, isAdmin } = ctx;

  const [{ data: members }, { data: invites }, { data: tokens }] = await Promise.all([
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
  ]);

  // Members don't expose emails; invites tell us who joined with which email.
  const emailOf = new Map((invites ?? []).filter((i) => i.accepted_by).map((i) => [i.accepted_by as string, i.email as string]));
  const now = new Date().toISOString();
  const pending = (invites ?? []).filter((i) => !i.accepted_at && !i.revoked_at && i.expires_at > now);
  const liveTokens = (tokens ?? []).filter((t) => t.expires_at > now);

  return (
    <div>
      <h1 className="text-[24px] font-semibold tracking-tight">{household.name}</h1>

      <section className="mt-7">
        <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Mga kasama</h2>
        <ul className="divide-y divide-line">
          {(members ?? []).map((m) => (
            <li key={m.user_id} className="flex items-baseline justify-between py-3 text-[15px]">
              <span className="truncate">{m.user_id === user.id ? `Ikaw (${user.email})` : (emailOf.get(m.user_id) ?? "Kasama")}</span>
              <span className="shrink-0 pl-3 text-[13px] text-muted">{ROLE[m.role]}</span>
            </li>
          ))}
          {pending.map((i) => (
            <li key={i.id} className="flex items-baseline justify-between gap-3 py-3 text-[15px]">
              <span className="min-w-0">
                <span className="block truncate">{i.email}</span>
                <span className="block text-[13px] text-muted">
                  Hindi pa sumasali. Valid ang invite hanggang {shortDate(i.expires_at.slice(0, 10))}.
                </span>
              </span>
              {isAdmin && (
                <form action={revokeInvite}>
                  <input type="hidden" name="id" value={i.id} />
                  <button className="text-[13px] text-rust underline underline-offset-2">Bawiin</button>
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
        <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">Back Tap mo</h2>
        <ul className="divide-y divide-line">
          {liveTokens.map((t) => (
            <li key={t.id} className="flex items-baseline justify-between gap-3 py-3 text-[15px]">
              <span className="min-w-0">
                <span className="block truncate">{t.label}</span>
                <span className="block text-[13px] text-muted">
                  {t.last_used_at ? `Huling gamit ${shortDate(t.last_used_at.slice(0, 10))}` : "Hindi pa nagagamit"}, valid hanggang{" "}
                  {shortDate(t.expires_at.slice(0, 10))}
                </span>
              </span>
              <form action={revokeToken}>
                <input type="hidden" name="id" value={t.id} />
                <button className="text-[13px] text-rust underline underline-offset-2">I-revoke</button>
              </form>
            </li>
          ))}
        </ul>
        <p className="mb-3 mt-3 text-[13px] text-muted">
          {liveTokens.length === 0
            ? "Wala kang aktibong Back Tap token. Gumawa ng isa para sa shortcut sa iPhone mo."
            : "Kapag nawala o napalitan ang phone, i-revoke ang token niya at gumawa ng bago."}
        </p>
        <TokenForm />
      </section>

      <form action={signOut} className="mt-12">
        <button className="btn-quiet w-full">Mag-log out</button>
      </form>
    </div>
  );
}
