"use client";

import { useSubmit } from "@/components/useSubmit";
import { useActionState, useState } from "react";
import { addTransaction, type AddState } from "./actions";
import { GROUP_LABEL, type Account, type Category } from "@/lib/shared";

type Acc = { id: string; name: string; kind: Account["kind"]; cls: Account["class"]; is_spendable: boolean };
type Kind = "expense" | "income" | "transfer";

const KINDS: { value: Kind; label: string }[] = [
  { value: "expense", label: "Expense" },
  { value: "income", label: "Income" },
  { value: "transfer", label: "Transfer" },
];

export function AddForm({ accounts, categories, today }: { accounts: Acc[]; categories: Category[]; today: string }) {
  const [kind, setKind] = useState<Kind>("expense");
  const [requestId] = useState(() => crypto.randomUUID()); // one id per screen: a double tap saves once
  const [state, action, pending] = useActionState<AddState, FormData>(addTransaction, {});
  const { onSubmit, ready } = useSubmit(action);

  const cats = categories.filter((c) => c.kind === (kind === "income" ? "income" : "expense"));
  // Spending can come from cash, wallets, banks or cards; income only lands in money accounts.
  const sources = accounts.filter((a) => (kind === "income" ? a.cls === "asset" : a.is_spendable || a.cls === "liability"));

  return (
    <form onSubmit={onSubmit} className="mt-5 space-y-6">
      <input type="hidden" name="kind" value={kind} />
      <input type="hidden" name="request_id" value={requestId} />

      <div role="radiogroup" aria-label="Type" className="grid grid-cols-3 rounded-lg border border-line bg-white p-1">
        {KINDS.map((k) => (
          <button
            key={k.value}
            type="button"
            role="radio"
            aria-checked={kind === k.value}
            onClick={() => setKind(k.value)}
            className={`rounded-md py-2 text-[15px] font-medium ${kind === k.value ? "bg-ink text-white" : "text-muted"}`}
          >
            {k.label}
          </button>
        ))}
      </div>

      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Amount</span>
        <div className="flex items-baseline gap-2 border-b-2 border-ink pb-1">
          <span className="text-[28px] font-medium text-muted">₱</span>
          <input
            name="amount"
            inputMode="decimal"
            autoComplete="off"
            placeholder="0.00"
            required
            autoFocus
            className="w-full bg-transparent text-[40px] font-semibold tracking-tight outline-none placeholder:text-line"
          />
        </div>
      </label>

      {kind !== "transfer" ? (
        <>
          <fieldset>
            <legend className="mb-2 text-sm font-medium">{kind === "income" ? "Income type" : "What was it for"}</legend>
            <div className="flex flex-wrap gap-2">
              {cats.map((c) => (
                <label key={c.id} className="cursor-pointer">
                  <input type="radio" name="category" value={c.id} className="peer sr-only" required />
                  <span className="block rounded-full border border-line bg-white px-3 py-1.5 text-[14px] peer-checked:border-ink peer-checked:bg-ink peer-checked:text-white peer-focus-visible:outline-2 peer-focus-visible:outline-jade">
                    {c.name}
                  </span>
                </label>
              ))}
            </div>
          </fieldset>
          <AccountSelect name="account" label={kind === "income" ? "Received in" : "Paid from"} accounts={sources} />
        </>
      ) : (
        <>
          <AccountSelect name="from" label="From" accounts={accounts.filter((a) => a.cls === "asset")} />
          <AccountSelect name="to" label="To" accounts={accounts} hint="To pay a credit card, choose the card here." />
        </>
      )}

      <div className="grid grid-cols-[1fr_1.4fr] gap-3">
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Date</span>
          <input name="date" type="date" defaultValue={today} max={today} required className="field" />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Note (optional)</span>
          <input name="note" maxLength={200} placeholder="e.g. Jollibee" className="field" />
        </label>
      </div>

      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}

      <button className="btn-primary w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : kind === "expense" ? "Save expense" : kind === "income" ? "Save income" : "Save transfer"}
      </button>
    </form>
  );
}

function AccountSelect({ name, label, accounts, hint }: { name: string; label: string; accounts: Acc[]; hint?: string }) {
  const groups = new Map<string, Acc[]>();
  for (const a of accounts) groups.set(GROUP_LABEL[a.kind], [...(groups.get(GROUP_LABEL[a.kind]) ?? []), a]);
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium">{label}</span>
      <select name={name} required defaultValue="" className="field appearance-none">
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
      {hint && <span className="mt-1.5 block text-[13px] text-muted">{hint}</span>}
    </label>
  );
}
