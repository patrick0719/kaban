"use client";

import { useActionState, useState } from "react";
import { useSubmit } from "@/components/useSubmit";
import { dayLabel, FREQUENCY_LABEL, type Frequency, type RecurringKind } from "@/lib/recurring";
import { saveRecurring, type RecurringState } from "./actions";

type Acc = { id: string; name: string; group: string; cls: "asset" | "liability"; spendable: boolean };
type Cat = { id: string; name: string; kind: "income" | "expense" };
export type RecurringInitial = {
  id?: string;
  name?: string;
  kind?: RecurringKind;
  amount?: string;
  category?: string;
  account?: string;
  to?: string;
  frequency?: Frequency;
  day1?: number;
  day2?: number;
  next: string;
  auto?: boolean;
};

const KINDS: { value: RecurringKind; label: string }[] = [
  { value: "income", label: "Income" },
  { value: "expense", label: "Expense" },
  { value: "transfer", label: "Transfer" },
];
const DAYS = Array.from({ length: 31 }, (_, i) => i + 1);

export function RecurringForm({ initial, accounts, categories }: { initial: RecurringInitial; accounts: Acc[]; categories: Cat[] }) {
  const [kind, setKind] = useState<RecurringKind>(initial.kind ?? "income");
  const [frequency, setFrequency] = useState<Frequency>(initial.frequency ?? "twice_a_month");
  const [state, action, pending] = useActionState<RecurringState, FormData>(saveRecurring, {});
  const { onSubmit, ready } = useSubmit(action);
  const isNew = !initial.id;

  const cats = categories.filter((c) => c.kind === (kind === "income" ? "income" : "expense"));
  // Income lands in money accounts; spending can also go on a card.
  const from = accounts.filter((a) => (kind === "income" ? a.cls === "asset" : kind === "expense" ? a.spendable || a.cls === "liability" : true));

  return (
    <form onSubmit={onSubmit} className="mt-6 space-y-5">
      {initial.id && <input type="hidden" name="id" value={initial.id} />}
      <input type="hidden" name="kind" value={kind} />

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
        <span className="mb-1.5 block text-sm font-medium">Name</span>
        <input
          name="name"
          required
          maxLength={60}
          defaultValue={initial.name}
          placeholder={kind === "income" ? "e.g. Salary" : kind === "expense" ? "e.g. Netflix" : "e.g. Weekly allowance"}
          className="field"
        />
      </label>

      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Usual amount</span>
        <div className="flex items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
          <span className="text-muted">₱</span>
          <input
            name="amount"
            inputMode="decimal"
            required
            autoComplete="off"
            defaultValue={initial.amount}
            placeholder="0.00"
            className="w-full bg-transparent px-1.5 py-2.5 text-[16px] outline-none"
          />
        </div>
      </label>

      {kind !== "transfer" && (
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Category</span>
          <select key={kind} name="category" required defaultValue={cats.some((c) => c.id === initial.category) ? initial.category : ""} className="field">
            <option value="" disabled>
              Choose…
            </option>
            {cats.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
      )}

      <AccountSelect
        key={`from-${kind}`}
        name="account"
        label={kind === "income" ? "Goes into" : "Comes from"}
        accounts={from}
        defaultValue={initial.account}
      />
      {kind === "transfer" && <AccountSelect name="to" label="Goes to" accounts={accounts} defaultValue={initial.to} />}

      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Repeats</span>
          <select name="frequency" value={frequency} onChange={(e) => setFrequency(e.target.value as Frequency)} className="field">
            {(Object.keys(FREQUENCY_LABEL) as Frequency[]).map((f) => (
              <option key={f} value={f}>
                {FREQUENCY_LABEL[f]}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">{frequency === "weekly" || frequency === "every_2_weeks" ? "Next date" : "Starting from"}</span>
          <input name="next" type="date" required defaultValue={initial.next} className="field" />
        </label>
      </div>

      {frequency === "monthly" && <DaySelect name="day1" label="On the" defaultValue={initial.day1 ?? 15} />}
      {frequency === "twice_a_month" && (
        <div className="grid grid-cols-2 gap-3">
          <DaySelect name="day1" label="First day" defaultValue={initial.day1 ?? 15} max={27} />
          <DaySelect name="day2" label="Second day" defaultValue={initial.day2 ?? 31} />
        </div>
      )}
      {(frequency === "monthly" || frequency === "twice_a_month") && (
        <p className="-mt-2 text-[13px] text-muted">In shorter months, the 29th to 31st falls on the last day.</p>
      )}

      <fieldset>
        <legend className="mb-1.5 block text-sm font-medium">When it comes around</legend>
        <div className="divide-y divide-line rounded-lg border border-line bg-white">
          <label className="flex items-start gap-3 px-3 py-3 text-[15px]">
            <input type="radio" name="mode" value="ask" defaultChecked={!initial.auto} className="mt-1 h-4 w-4 accent-jade" />
            <span>
              Ask me first
              <span className="block text-[13px] text-muted">
                Shows on Home when it is due. You confirm the real amount and date, or skip. Best for pay that does not
                always arrive on the same day.
              </span>
            </span>
          </label>
          <label className="flex items-start gap-3 px-3 py-3 text-[15px]">
            <input type="radio" name="mode" value="auto" defaultChecked={initial.auto} className="mt-1 h-4 w-4 accent-jade" />
            <span>
              Record it automatically
              <span className="block text-[13px] text-muted">
                Saved on its date with the usual amount. Good for fixed charges like a subscription on your card.
              </span>
            </span>
          </label>
        </div>
      </fieldset>

      {kind === "expense" && (
        <p className="text-[13px] text-muted">
          For bills you pay yourself, like Meralco or rent, use Bills instead. Bills remind you and set the money aside in Safe to
          spend.
        </p>
      )}

      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}

      <button className="btn-primary w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : isNew ? "Save repeating entry" : "Save changes"}
      </button>
    </form>
  );
}

function AccountSelect({ name, label, accounts, defaultValue }: { name: string; label: string; accounts: Acc[]; defaultValue?: string }) {
  const groups = new Map<string, Acc[]>();
  for (const a of accounts) groups.set(a.group, [...(groups.get(a.group) ?? []), a]);
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium">{label}</span>
      <select name={name} required defaultValue={accounts.some((a) => a.id === defaultValue) ? defaultValue : ""} className="field">
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
    </label>
  );
}

function DaySelect({ name, label, defaultValue, max = 31 }: { name: string; label: string; defaultValue: number; max?: number }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium">{label}</span>
      <select name={name} defaultValue={Math.min(defaultValue, max)} className="field">
        {DAYS.filter((d) => d <= max).map((d) => (
          <option key={d} value={d}>
            {d === 31 ? "Last day" : dayLabel(d)}
          </option>
        ))}
      </select>
    </label>
  );
}
