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
        I-void ang talang ito
      </button>
    );
  }
  return (
    <form onSubmit={onSubmit} className="space-y-3 rounded-lg border border-rust/30 bg-rust-soft/40 p-4">
      <input type="hidden" name="id" value={id} />
      <p className="text-[14px]">
        Mawawala ito sa balanse at sa mga report. Mananatili ito sa history bilang void, kaya puwede pa ring makita.
      </p>
      <input name="reason" maxLength={120} placeholder="Bakit? (hal. test lang, doble)" className="field" />
      {state.error && <p className="text-sm text-rust">{state.error}</p>}
      <div className="grid grid-cols-2 gap-2">
        <button type="button" className="btn-quiet" onClick={() => setConfirming(false)}>
          Huwag na
        </button>
        <button className="btn bg-rust text-white" disabled={pending || !ready}>
          {pending ? "Vino-void…" : "I-void"}
        </button>
      </div>
    </form>
  );
}
