"use client";

import { useActionState, useState } from "react";
import { useSubmit } from "@/components/useSubmit";
import { saveGoal, type GoalState } from "./actions";

type Option = { id: string; name: string };

export function GoalForm({
  initial,
  savingsAccounts,
  isNew,
  today,
}: {
  initial?: { goal_id: string; name: string; target: string; target_date: string };
  savingsAccounts: Option[];
  isNew: boolean;
  today: string;
}) {
  const [state, action, pending] = useActionState<GoalState, FormData>(saveGoal, {});
  const { onSubmit, ready } = useSubmit(action);
  const [where, setWhere] = useState("earmark");

  return (
    <form onSubmit={onSubmit} className="mt-6 space-y-5">
      {initial && <input type="hidden" name="goal_id" value={initial.goal_id} />}
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Goal</span>
        <input name="name" required maxLength={60} defaultValue={initial?.name} placeholder="e.g. Emergency fund" className="field" />
      </label>
      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Target amount</span>
          <div className="flex items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
            <span className="text-muted">₱</span>
            <input name="target" inputMode="decimal" required autoComplete="off" defaultValue={initial?.target} placeholder="0.00" className="w-full bg-transparent px-1.5 py-2.5 text-[16px] outline-none" />
          </div>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">By when (optional)</span>
          <input name="target_date" type="date" min={today} defaultValue={initial?.target_date} className="field" />
        </label>
      </div>

      {isNew && (
        <fieldset>
          <legend className="mb-2 text-sm font-medium">Where will the money be kept?</legend>
          <div className="space-y-2">
            <Choice value="earmark" current={where} onPick={setWhere} title="Set aside in my spending accounts">
              The money stays in GCash, BPI or cash, but is no longer counted in Safe to spend. Good for short goals like a trip.
            </Choice>
            {savingsAccounts.map((a) => (
              <Choice key={a.id} value={a.id} current={where} onPick={setWhere} title={`Move it to ${a.name}`}>
                You move money into this savings account. Good for an emergency fund.
              </Choice>
            ))}
            <Choice value="new" current={where} onPick={setWhere} title="Move it to a new savings account">
              For a separate account you keep only for this goal.
            </Choice>
          </div>
          {where === "new" && (
            <input name="new_account_name" maxLength={60} required placeholder="Account name, e.g. Maya Savings" className="field mt-3" />
          )}
        </fieldset>
      )}

      {isNew && (
        <label className="flex items-start gap-3 text-[15px]">
          <input type="checkbox" name="personal" className="mt-1 h-4 w-4 accent-jade" />
          <span>
            Only visible to me
            <span className="block text-[13px] text-muted">Leave unchecked for goals you share with your household.</span>
          </span>
        </label>
      )}

      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      <button className="btn-primary w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : isNew ? "Create goal" : "Save changes"}
      </button>
    </form>
  );
}

function Choice({
  value,
  current,
  onPick,
  title,
  children,
}: {
  value: string;
  current: string;
  onPick: (v: string) => void;
  title: string;
  children: React.ReactNode;
}) {
  const on = value === current;
  return (
    <label className={`block cursor-pointer rounded-lg border bg-white p-3 ${on ? "border-ink" : "border-line"}`}>
      <span className="flex items-start gap-3">
        <input type="radio" name="where" value={value} checked={on} onChange={() => onPick(value)} className="mt-1 accent-jade" />
        <span>
          <span className="block text-[15px] font-medium">{title}</span>
          <span className="block text-[13px] text-muted">{children}</span>
        </span>
      </span>
    </label>
  );
}
