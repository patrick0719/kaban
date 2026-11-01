"use client";

import { useSubmit } from "@/components/useSubmit";
import { useActionState, useEffect, useRef, useState } from "react";
import { createToken, invite, type FormState } from "./actions";

export function InviteForm() {
  const [state, action, pending] = useActionState<FormState, FormData>(invite, {});
  const { onSubmit, ready } = useSubmit(action);
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state.ok) formRef.current?.reset(); // done: ready for the next email
  }, [state]);
  return (
    <form ref={formRef} onSubmit={onSubmit} className="space-y-3">
      <div className="grid grid-cols-[1fr_auto] gap-2">
        <input name="email" type="email" required placeholder="email ng partner" autoComplete="off" className="field" />
        <select name="role" defaultValue="member" className="field w-auto" aria-label="Role">
          <option value="member">Member</option>
          <option value="admin">Admin</option>
          <option value="viewer">Viewer</option>
        </select>
      </div>
      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      {state.ok && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.ok}</p>}
      <button className="btn-quiet w-full" disabled={pending || !ready}>
        {pending ? "Ini-invite…" : "I-invite"}
      </button>
    </form>
  );
}

export function TokenForm() {
  const [state, action, pending] = useActionState<FormState, FormData>(createToken, {});
  const { onSubmit, ready } = useSubmit(action);
  const [copied, setCopied] = useState(false);

  if (state.token) {
    return (
      <div className="space-y-3 rounded-lg border border-jade/40 bg-jade-soft/50 p-4">
        <p className="text-[14px] font-medium">Kopyahin ito ngayon. Hindi na ito ipapakita ulit.</p>
        <code className="block break-all rounded-md bg-white p-3 text-[13px]">{state.token}</code>
        <button
          type="button"
          className="btn-primary w-full"
          onClick={async () => {
            await navigator.clipboard.writeText(state.token!);
            setCopied(true);
          }}
        >
          {copied ? "Nakopya na" : "Kopyahin ang token"}
        </button>
        <p className="text-[13px] text-muted">
          Ilagay ito sa unang Text action ng KABAN Gastos shortcut. Huwag i-share ang shortcut sa iba.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-3">
      <input name="label" maxLength={40} placeholder="Pangalan ng device, hal. iPhone ni Levi" className="field" />
      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
      <button className="btn-quiet w-full" disabled={pending || !ready}>
        {pending ? "Gumagawa…" : "Gumawa ng Back Tap token"}
      </button>
    </form>
  );
}
