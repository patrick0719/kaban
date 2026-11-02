"use client";

import { useSubmit } from "@/components/useSubmit";
import { useActionState, useState } from "react";
import { voidTransaction, type VoidState } from "./actions";

export function VoidButton({ id }: { id: string }) {
  const [confirming, setConfirming] = useState(false);
  const [state, action, pending] = useActionState<VoidState, FormData>(voidTransaction, {});
  const { onSubmit, ready } = useSubmit(action);

  if (!confirming) {
    return (
      <button type="button" className="btn-danger w-full" onClick={() => setConfirming(true)}>
        Void this entry
      </button>
    );
  }
  return (
    <form onSubmit={onSubmit} className="space-y-3 rounded-lg border border-rust/30 bg-rust-soft/40 p-4">
      <input type="hidden" name="id" value={id} />
      <p className="text-[14px]">
        It will be removed from balances and reports. It stays in history, marked as void.
      </p>
      <input name="reason" maxLength={120} placeholder="Why? (e.g. test entry, duplicate)" className="field" />
      {state.error && <p className="text-sm text-rust">{state.error}</p>}
      <div className="grid grid-cols-2 gap-2">
        <button type="button" className="btn-quiet" onClick={() => setConfirming(false)}>
          Cancel
        </button>
        <button className="btn bg-rust text-white" disabled={pending || !ready}>
          {pending ? "Voiding…" : "Void"}
        </button>
      </div>
    </form>
  );
}
