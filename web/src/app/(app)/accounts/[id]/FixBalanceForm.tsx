"use client";

import { useSubmit } from "@/components/useSubmit";
import { useActionState, useEffect, useState } from "react";
import { fixBalance, type FixState } from "./actions";

export function FixBalanceForm({ id, isDebt, current }: { id: string; isDebt: boolean; current: string }) {
  const [state, action, pending] = useActionState<FixState, FormData>(fixBalance, {});
  const { onSubmit, ready } = useSubmit(action);
  // One key per attempt: a double tap saves once; after a save, the next correction gets a new key.
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  useEffect(() => {
    if (state.ok) setRequestId(crypto.randomUUID());
  }, [state]);
  return (
    <form onSubmit={onSubmit} className="space-y-3">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="request_id" value={requestId} />
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">{isDebt ? "Amount owed now" : "Balance now"}</span>
        <div className="flex items-baseline gap-2 border-b-2 border-ink pb-1">
          <span className="text-[24px] font-medium text-muted">₱</span>
          <input
            name="value"
            inputMode="decimal"
            autoComplete="off"
            defaultValue={current}
            required
            className="w-full bg-transparent text-[32px] font-semibold tracking-tight outline-none"
          />
        </div>
        <span className="mt-1.5 block text-[13px] text-muted">
          {isDebt
            ? "Check the card app for the total amount owed, not just the minimum."
            : "Check your bank or e-wallet app, or count your cash."}
        </span>
      </label>
      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      {state.ok && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.ok}</p>}
      <button className="btn-primary w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : "Save balance"}
      </button>
    </form>
  );
}
