"use client";

import { useActionState, useEffect, useState } from "react";
import { useSubmit } from "@/components/useSubmit";
import { setBudget, type BudgetState } from "./actions";

const fmt = new Intl.NumberFormat("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const peso = (c: number) => `₱${fmt.format(Math.abs(c) / 100)}`;

type Props = {
  categoryId: string;
  name: string;
  budget: number | null;
  spent: number;
  suggested: number | null;
  status: "ok" | "pace" | "over";
  projected: number;
  canWrite: boolean;
};

export function BudgetItem({ categoryId, name, budget, spent, suggested, status, projected, canWrite }: Props) {
  const [editing, setEditing] = useState(false);
  const [state, action, pending] = useActionState<BudgetState, FormData>(setBudget, {});
  const { onSubmit, ready } = useSubmit(action);
  useEffect(() => {
    if (state.ok) setEditing(false);
  }, [state]);

  const pct = budget ? Math.min(100, Math.round((spent / budget) * 100)) : 0;

  // Nothing spent, no budget, no suggestion: one quiet line.
  if (budget == null && spent === 0 && suggested == null && !editing) {
    return (
      <li className="flex items-baseline justify-between gap-3 py-2.5">
        <span className="truncate text-[15px] text-muted">{name}</span>
        {canWrite && (
          <button type="button" onClick={() => setEditing(true)} className="shrink-0 text-[13px] text-jade underline underline-offset-4">
            Set budget
          </button>
        )}
      </li>
    );
  }
  const bar = status === "over" ? "bg-rust" : status === "pace" ? "bg-amber" : "bg-jade";

  return (
    <li className="py-3">
      <div className="flex items-baseline justify-between gap-3">
        <span className="truncate text-[15px] font-medium">{name}</span>
        <span className="shrink-0 text-[14px]">
          <span className={status === "over" ? "font-medium text-rust" : "font-medium"}>{peso(spent)}</span>
          {budget != null && <span className="text-muted"> of {peso(budget)}</span>}
        </span>
      </div>

      {budget != null ? (
        <>
          <div
            role="progressbar"
            aria-label={`${name} budget used`}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={pct}
            className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-line"
          >
            <div className={`h-full rounded-full ${bar}`} style={{ width: `${pct}%` }} />
          </div>
          <p className={`mt-1.5 text-[13px] ${status === "over" ? "text-rust" : status === "pace" ? "text-amber" : "text-muted"}`}>
            {status === "over"
              ? `Over by ${peso(spent - budget)}`
              : status === "pace"
                ? `At this pace you will spend about ${peso(projected)} this month`
                : `${peso(budget - spent)} left`}
          </p>
        </>
      ) : (
        suggested != null && <p className="mt-1 text-[13px] text-muted">Suggested {peso(suggested)} a month from your recent spending.</p>
      )}

      {canWrite &&
        (editing ? (
          <form onSubmit={onSubmit} className="mt-2 flex items-center gap-2">
            <input type="hidden" name="category_id" value={categoryId} />
            <div className="flex flex-1 items-center rounded-lg border border-line bg-white px-3 focus-within:border-jade">
              <span className="text-muted">₱</span>
              <input
                name="amount"
                inputMode="decimal"
                autoComplete="off"
                autoFocus
                aria-label={`Monthly budget for ${name}`}
                defaultValue={budget != null ? fmt.format(budget / 100) : suggested != null ? fmt.format(suggested / 100) : ""}
                className="w-full bg-transparent px-1.5 py-2 text-[16px] outline-none"
              />
            </div>
            <button className="btn-primary px-3 py-2" disabled={pending || !ready}>
              {pending ? "Saving…" : "Save"}
            </button>
            <button type="button" className="px-1 text-[14px] text-muted" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </form>
        ) : (
          <button type="button" onClick={() => setEditing(true)} className="mt-1 text-[13px] text-jade underline underline-offset-4">
            {budget != null ? "Change budget" : "Set budget"}
          </button>
        ))}
      {state.error && <p className="mt-1.5 text-[13px] text-rust">{state.error}</p>}
    </li>
  );
}
