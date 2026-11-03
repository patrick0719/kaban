"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { useRequestKey, useSubmit } from "@/components/useSubmit";
import { archiveGoal, moveGoalMoney, type GoalState } from "../actions";

type Option = { id: string; name: string; hint?: string };

export function MoveMoney({
  goalId,
  direction,
  accounts,
  label,
  accountLabel,
  note,
  startOpen,
}: {
  goalId: string;
  direction: "add" | "take";
  accounts: Option[];
  label: string;
  accountLabel: string;
  note?: string;
  startOpen?: boolean;
}) {
  const [open, setOpen] = useState(Boolean(startOpen));
  const [state, action, pending] = useActionState<GoalState, FormData>(moveGoalMoney, {});
  const { onSubmit, ready } = useSubmit(action);
  const requestId = useRequestKey(state); // a double tap moves money once
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state.ok) {
      // ready for the next amount; keep the chosen account
      const amount = formRef.current?.querySelector<HTMLInputElement>('input[name="amount"]');
      if (amount) amount.value = "";
    }
  }, [state]);

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className={direction === "add" ? "btn-primary w-full" : "btn-quiet w-full"}>
        {label}
      </button>
    );
  }
  return (
    <form ref={formRef} onSubmit={onSubmit} className="space-y-3 rounded-lg border border-line bg-white p-4">
      <p className="text-[15px] font-semibold">{label}</p>
      <input type="hidden" name="goal_id" value={goalId} />
      <input type="hidden" name="direction" value={direction} />
      <input type="hidden" name="request_id" value={requestId} />
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Amount</span>
        <div className="flex items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
          <span className="text-muted">₱</span>
          <input name="amount" inputMode="decimal" required autoComplete="off" placeholder="0.00" className="w-full bg-transparent px-1.5 py-2.5 text-[16px] outline-none" />
        </div>
      </label>
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">{accountLabel}</span>
        <select name="account" required defaultValue={accounts.length === 1 ? accounts[0].id : ""} className="field">
          <option value="" disabled>
            Choose…
          </option>
          {accounts.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name}
              {a.hint ? ` (${a.hint})` : ""}
            </option>
          ))}
        </select>
      </label>
      {note && <p className="text-[13px] text-muted">{note}</p>}
      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      {state.ok && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.ok}</p>}
      <div className="grid grid-cols-2 gap-2">
        <button type="button" className="btn-quiet" onClick={() => setOpen(false)}>
          Close
        </button>
        <button className={direction === "add" ? "btn-primary" : "btn-quiet"} disabled={pending || !ready}>
          {pending ? "Saving…" : direction === "add" ? "Add" : "Take out"}
        </button>
      </div>
    </form>
  );
}

export function FinishGoal({ goalId, reached, accountNote }: { goalId: string; reached: boolean; accountNote: string }) {
  const [confirming, setConfirming] = useState(false);
  if (!confirming) {
    return (
      <button type="button" className={reached ? "btn-primary w-full" : "btn-danger w-full"} onClick={() => setConfirming(true)}>
        {reached ? "Mark as done" : "Remove goal"}
      </button>
    );
  }
  return (
    <form action={archiveGoal} className="space-y-3 rounded-lg border border-line bg-white p-4">
      <input type="hidden" name="goal_id" value={goalId} />
      <p className="text-[14px]">{accountNote}</p>
      <div className="grid grid-cols-2 gap-2">
        <button type="button" className="btn-quiet" onClick={() => setConfirming(false)}>
          Cancel
        </button>
        <button className={reached ? "btn-primary" : "btn bg-rust text-white"}>{reached ? "Mark as done" : "Remove"}</button>
      </div>
    </form>
  );
}
