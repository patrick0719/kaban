import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/app/login/actions";
import { Wordmark } from "@/components/Wordmark";

async function accept(form: FormData) {
  "use server";
  const supabase = await createClient();
  const { error } = await supabase.rpc("accept_invite", { p_invite: String(form.get("id")) });
  if (error) redirect("/welcome?e=1");
  revalidatePath("/", "layout");
  redirect("/");
}

export default async function Welcome({ searchParams }: { searchParams: Promise<{ e?: string }> }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { count } = await supabase.from("household_members").select("user_id", { count: "exact", head: true }).eq("user_id", user.id);
  if ((count ?? 0) > 0) redirect("/");

  const { data: invites } = await supabase.rpc("my_pending_invites");
  const { e } = await searchParams;

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center px-6 py-12">
      <Wordmark className="mb-10" />
      {(invites ?? []).length > 0 ? (
        <>
          <h1 className="text-[28px] font-semibold leading-tight tracking-tight">May naghihintay sa&apos;yo</h1>
          <p className="mt-2 text-[15px] text-muted">Tanggapin para makita ang pera ng bahay at makapagtala.</p>
          <ul className="mt-8 space-y-3">
            {invites!.map((i: { invite_id: string; household_name: string; role: string }) => (
              <li key={i.invite_id} className="rounded-lg border border-line bg-white p-4">
                <p className="text-[17px] font-semibold">{i.household_name}</p>
                <p className="text-[14px] text-muted">Papasok ka bilang {i.role === "viewer" ? "viewer" : i.role}.</p>
                <form action={accept} className="mt-3">
                  <input type="hidden" name="id" value={i.invite_id} />
                  <button className="btn-primary w-full">Sumali sa {i.household_name}</button>
                </form>
              </li>
            ))}
          </ul>
        </>
      ) : (
        <>
          <h1 className="text-[28px] font-semibold leading-tight tracking-tight">Wala ka pang household</h1>
          <p className="mt-2 text-[15px] text-muted">
            Hilingin sa may-ari ng household na i-invite ang <span className="text-ink">{user.email}</span>. Pagkatapos, i-refresh
            ang page na ito.
          </p>
        </>
      )}
      {e && <p className="mt-4 rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">Hindi na valid ang invite. Humingi ng bago.</p>}
      <form action={signOut} className="mt-10">
        <button className="text-sm text-muted underline underline-offset-4">Mag-log out</button>
      </form>
    </main>
  );
}
