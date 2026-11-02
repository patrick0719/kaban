"use client";

import { useActionState, useEffect, useState } from "react";
import { useSubmit } from "@/components/useSubmit";
import { payBill, setAmount, type BillState } from "../actions";

type Option = { id: string; name: string; group: string };

export function PayForm({
  occurrenceId,
  remaining,
  accounts,
  defaultFrom,
  today,
  cardName,
}: {
  occurrenceId: string;
  remaining: string;
  accounts: Option[];
  defaultFrom: string;
  today: string;
  cardName: string | null;
}) {
  const [state, action, pending] = useActionState<BillState, FormData>(payBill, {});
  const { onSubmit, ready } = useSubmit(action);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID()); // a double tap pays once
  useEffect(() => {
    if (state.ok) setRequestId(crypto.randomUUID());
  }, [state]);

  const groups = new Map<string, Option[]>();
  for (const a of accounts) groups.set(a.group, [...(groups.get(a.group) ?? []), a]);

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <input type="hidden" name="occurrence_id" value={occurrenceId} />
      <input type="hidden" name="request_id" value={requestId} />
      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Amount paid</span>
          <div className="flex items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
            <span className="text-muted">₱</span>
            <input name="amount" inputMode="decimal" required autoComplete="off" defaultValue={remaining} className="w-full bg-transparent px-1.5 py-2.5 text-[16px] outline-none" />
          </div>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Date paid</span>
          <input name="date" type="date" required defaultValue={today} max={today} className="field" />
        </label>
      </div>
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Paid from</span>
        <select name="from" required defaultValue={defaultFrom} className="field">
          <option value="" disabled>
            Choose…
          </option>
          {[...groups.entries()].map(([g, list]) => (
            <optgroup key={g} label={g}>
              {list.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </optgroup>
          ))}
        </select>
        {cardName && (
          <span className="mt-1.5 block text-[13px] text-muted">
            This moves money into {cardName}. Your card purchases were already counted as spending, so this is not counted again.
          </span>
        )}
      </label>
      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      {state.ok && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.ok}</p>}
      <button className="btn-primary w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : "Record payment"}
      </button>
    </form>
  );
}

export function AmountForm({ occurrenceId, current }: { occurrenceId: string; current: string }) {
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<BillState, FormData>(setAmount, {});
  const { onSubmit, ready } = useSubmit(action);

  if (!open && !state.ok) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[14px] text-jade underline underline-offset-4">
        Change this month&apos;s amount
      </button>
    );
  }
  return (
    <form onSubmit={onSubmit} className="space-y-3">
      <input type="hidden" name="occurrence_id" value={occurrenceId} />
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">This month&apos;s amount</span>
        <div className="flex items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
          <span className="text-muted">₱</span>
          <input name="amount" inputMode="decimal" required autoComplete="off" defaultValue={current} className="w-full bg-transparent px-1.5 py-2.5 text-[16px] outline-none" />
        </div>
        <span className="mt-1.5 block text-[13px] text-muted">Only this month changes. Edit the bill to change every month.</span>
      </label>
      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      {state.ok && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.ok}</p>}
      <button className="btn-quiet w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : "Save amount"}
      </button>
    </form>
  );
}
