import Link from "next/link";
import { notFound } from "next/navigation";
import { getAccounts, getContext } from "@/lib/context";
import { getGoals, perMonth, percent } from "@/lib/goals";
import { amountText, longDate, peso, todayManila } from "@/lib/money";
import { Progress } from "@/components/Progress";
import { GoalForm } from "../GoalForm";
import { FinishGoal, MoveMoney } from "./Forms";

export default async function GoalPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ edit?: string }> }) {
  const { id } = await params;
  const { edit } = await searchParams;
  const ctx = await getContext();
  const today = todayManila();
  const [{ goals, earmarks }, accounts] = await Promise.all([getGoals(ctx.supabase, ctx.householdId), getAccounts(ctx)]);
  const g = goals.find((x) => x.goal_id === id);
  if (!g) notFound();

  const accName = new Map(accounts.map((a) => [a.id, a.name]));
  const pct = percent(g);
  const pm = perMonth(g, today);
  const reached = g.saved >= g.target_amount;
  const myMarks = earmarks.filter((m) => m.goal_id === g.goal_id && m.amount > 0);

  // Money free to set aside in each spending account = balance minus what other goals already hold there.
  const heldElsewhere = (accountId: string) =>
    earmarks.filter((m) => m.account_id === accountId && m.goal_id !== g.goal_id).reduce((s, m) => s + m.amount, 0);
  const savingsAccount = g.linked_account_id ? accounts.find((a) => a.id === g.linked_account_id) : undefined;

  const addFrom =
    g.mode === "account"
      ? accounts.filter((a) => a.class === "asset" && a.id !== g.linked_account_id).map((a) => ({ id: a.id, name: a.name, hint: peso(a.balance) }))
      : accounts
          .filter((a) => a.is_spendable)
          .map((a) => {
            const mine = myMarks.find((m) => m.account_id === a.id)?.amount ?? 0;
            return { id: a.id, name: a.name, hint: `${peso(Math.max(a.balance - heldElsewhere(a.id) - mine, 0))} free` };
          });
  const takeTo =
    g.mode === "account"
      ? accounts.filter((a) => a.is_spendable).map((a) => ({ id: a.id, name: a.name }))
      : myMarks.map((m) => ({ id: m.account_id, name: accName.get(m.account_id) ?? "Account", hint: `${peso(m.amount)} set aside` }));

  return (
    <div>
      <Link href="/goals" className="text-[14px] text-muted">
        Back to goals
      </Link>

      <h1 className="mt-6 text-[28px] font-semibold tracking-tight">{g.name}</h1>
      <p className="mt-2 text-[40px] font-semibold leading-none tracking-tight">₱{amountText(g.saved)}</p>
      <p className="mt-2 text-[15px] text-muted">
        of {peso(g.target_amount)} · {pct}%
      </p>
      <div className="mt-4">
        <Progress value={pct} label={`${g.name} progress`} />
      </div>
      <p className="mt-3 text-[15px]">
        {reached
          ? "You reached this goal."
          : pm
            ? `Save ${peso(pm.amount)} a month for ${pm.months} month${pm.months === 1 ? "" : "s"} to reach it by ${longDate(g.target_date!)}.`
            : `${peso(g.target_amount - g.saved)} to go.`}
      </p>

      <dl className="mt-6 divide-y divide-line border-y border-line text-[15px]">
        {g.mode === "account" ? (
          <Row label="Kept in" value={savingsAccount?.name ?? "Savings account"} />
        ) : myMarks.length ? (
          myMarks.map((m) => <Row key={m.account_id} label={`Set aside in ${accName.get(m.account_id)}`} value={peso(m.amount)} />)
        ) : (
          <Row label="Kept in" value="Nothing set aside yet" />
        )}
        {g.target_date && <Row label="Target date" value={longDate(g.target_date)} />}
        {g.owner_user_id && <Row label="Visible to" value="Only you" />}
      </dl>

      {ctx.canWrite && (
        <section className="mt-8 space-y-3">
          {!reached && (
            <MoveMoney
              goalId={g.goal_id}
              direction="add"
              label="Add money"
              accountLabel={g.mode === "account" ? `Move from` : "Set aside in"}
              accounts={addFrom}
              note={
                g.mode === "account"
                  ? `The money moves into ${savingsAccount?.name ?? "the savings account"}. It is not counted as spending.`
                  : "The money stays in that account, but is no longer counted in Safe to spend."
              }
            />
          )}
          {g.saved > 0 && (
            <MoveMoney
              goalId={g.goal_id}
              direction="take"
              label="Take money out"
              accountLabel={g.mode === "account" ? "Move to" : "Release from"}
              accounts={takeTo}
              note={g.mode === "account" ? undefined : "Released money is counted in Safe to spend again."}
            />
          )}
        </section>
      )}

      {ctx.canWrite && (
        <section className="mt-10 border-t border-line pt-6">
          {edit ? (
            <>
              <h2 className="text-[17px] font-semibold">Edit goal</h2>
              <GoalForm
                isNew={false}
                today={today}
                savingsAccounts={[]}
                initial={{ goal_id: g.goal_id, name: g.name, target: amountText(g.target_amount), target_date: g.target_date ?? "" }}
              />
            </>
          ) : (
            <Link href={`/goals/${g.goal_id}?edit=1`} className="text-[14px] text-jade underline underline-offset-4">
              Edit name, target or date
            </Link>
          )}
          <div className="mt-6">
            <FinishGoal
              goalId={g.goal_id}
              reached={reached}
              accountNote={
                g.mode === "account"
                  ? `The goal closes. Its money stays in ${savingsAccount?.name ?? "the savings account"}.`
                  : "The goal closes, and money set aside for it counts in Safe to spend again."
              }
            />
          </div>
        </section>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4 py-2.5">
      <dt className="text-muted">{label}</dt>
      <dd className="text-right">{value}</dd>
    </div>
  );
}
