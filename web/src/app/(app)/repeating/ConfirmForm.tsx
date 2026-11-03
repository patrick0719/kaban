"use client";

import { useActionState } from "react";
import { useRequestKey, useSubmit } from "@/components/useSubmit";
import { recordRecurring, skipRecurring, type RecurringState } from "./actions";

/** Record (or skip) the occurrence of a repeating entry that is due. */
export function ConfirmForm({
  id,
  due,
  amount,
  date,
  today,
  verb,
  compact,
}: {
  id: string;
  due: string;
  amount: string;
  date: string;
  today: string;
  verb: string;
  compact?: boolean;
}) {
  const [state, action, pending] = useActionState<RecurringState, FormData>(recordRecurring, {});
  const { onSubmit, ready } = useSubmit(action);
  const requestId = useRequestKey(state); // a double tap records once

  return (
    <div className={compact ? "mt-2" : "space-y-3"}>
      <form key={due} onSubmit={onSubmit} className={compact ? "space-y-2" : "space-y-3"}>
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="due" value={due} />
        <input type="hidden" name="request_id" value={requestId} />
        <div className={compact ? "grid grid-cols-2 gap-2" : "grid grid-cols-2 gap-3"}>
          <label className="block min-w-0 flex-1">
            <span className={compact ? "sr-only" : "mb-1.5 block text-sm font-medium"}>Amount</span>
            <div className="flex items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
              <span className="text-muted">₱</span>
              <input
                name="amount"
                inputMode="decimal"
                required
                autoComplete="off"
                defaultValue={amount}
                className="w-full min-w-0 bg-transparent px-1.5 py-2 text-[16px] outline-none"
              />
            </div>
          </label>
          <label className="block min-w-0">
            <span className={compact ? "sr-only" : "mb-1.5 block text-sm font-medium"}>Date</span>
            <input name="date" type="date" required defaultValue={date} max={today} className="field py-2!" />
          </label>
        </div>
        <button className={compact ? "btn-primary w-full py-2!" : "btn-primary w-full"} disabled={pending || !ready}>
          {pending ? "Saving…" : verb}
        </button>
      </form>
      {state.error && <p className="mt-2 rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      {state.ok && !compact && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.ok}</p>}
      <form action={skipRecurring} className={compact ? "mt-1" : ""}>
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="due" value={due} />
        <button className="text-[13px] text-muted underline underline-offset-4">Skip this one</button>
      </form>
    </div>
  );
}
