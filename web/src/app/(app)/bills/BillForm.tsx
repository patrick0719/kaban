"use client";

import { useActionState } from "react";
import { useSubmit } from "@/components/useSubmit";
import { saveBill, type BillState } from "./actions";

type Option = { id: string; name: string };
type Initial = {
  bill_id?: string;
  name?: string;
  amount?: string;
  next_due: string;
  repeat?: string;
  category?: string;
  card?: string;
  pay_from?: string;
};

export function BillForm({
  initial,
  categories,
  cards,
  payAccounts,
  isNew,
}: {
  initial: Initial;
  categories: Option[];
  cards: Option[];
  payAccounts: Option[];
  isNew: boolean;
}) {
  const [state, action, pending] = useActionState<BillState, FormData>(saveBill, {});
  const { onSubmit, ready } = useSubmit(action);
  const utilities = categories.find((c) => /electric|utilit|kuryente/i.test(c.name));

  return (
    <form onSubmit={onSubmit} className="mt-6 space-y-5">
      {initial.bill_id && <input type="hidden" name="bill_id" value={initial.bill_id} />}

      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Name</span>
        <input name="name" required maxLength={60} defaultValue={initial.name} placeholder="e.g. Meralco" className="field" />
      </label>

      <div className="grid grid-cols-2 gap-3">
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
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Next due date</span>
          <input name="next_due" type="date" required defaultValue={initial.next_due} className="field" />
        </label>
      </div>

      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Repeats</span>
        <select name="repeat" defaultValue={initial.repeat ?? "1"} className="field">
          <option value="1">Every month</option>
          <option value="2">Every 2 months</option>
          <option value="3">Every 3 months</option>
          <option value="6">Every 6 months</option>
          <option value="12">Every year</option>
          <option value="">One time only</option>
        </select>
      </label>

      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Category</span>
        <select name="category" required defaultValue={initial.category ?? utilities?.id ?? ""} className="field">
          <option value="" disabled>
            Choose…
          </option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>

      {cards.length > 0 && (
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Is this a credit card bill?</span>
          <select name="card" defaultValue={initial.card ?? ""} className="field">
            <option value="">No</option>
            {cards.map((c) => (
              <option key={c.id} value={c.id}>
                Yes, {c.name}
              </option>
            ))}
          </select>
          <span className="mt-1.5 block text-[13px] text-muted">
            Card purchases already count as spending, so paying the card bill just moves money into the card.
          </span>
        </label>
      )}

      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Usually paid from (optional)</span>
        <select name="pay_from" defaultValue={initial.pay_from ?? ""} className="field">
          <option value="">Not set</option>
          {payAccounts.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name}
            </option>
          ))}
        </select>
      </label>

      {isNew && (
        <label className="flex items-start gap-3 text-[15px]">
          <input type="checkbox" name="personal" className="mt-1 h-4 w-4 accent-jade" />
          <span>
            Only visible to me
            <span className="block text-[13px] text-muted">Leave unchecked for household bills everyone shares.</span>
          </span>
        </label>
      )}

      {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}

      <button className="btn-primary w-full" disabled={pending || !ready}>
        {pending ? "Saving…" : isNew ? "Add bill" : "Save changes"}
      </button>
    </form>
  );
}
