"use client";

import { useActionState } from "react";
import { useSubmit } from "@/components/useSubmit";
import { setRemindDays } from "./reminders";

export function RemindDays({ current }: { current: number }) {
  const [state, action, pending] = useActionState<{ ok?: string; error?: string }, FormData>(setRemindDays, {});
  const { onSubmit, ready } = useSubmit(action);
  return (
    <form onSubmit={onSubmit} className="mt-4 text-[15px]">
      <div className="flex items-center justify-between gap-3">
        <label htmlFor="days">Remind before the due date</label>
        <span className="flex items-center gap-2">
          <select id="days" name="days" defaultValue={String(current)} className="field w-auto py-2">
            <option value="0">Same day only</option>
            <option value="1">1 day</option>
            <option value="2">2 days</option>
            <option value="3">3 days</option>
            <option value="5">5 days</option>
            <option value="7">7 days</option>
          </select>
          <button className="text-[14px] text-jade underline underline-offset-4" disabled={pending || !ready}>
            {pending ? "Saving…" : "Save"}
          </button>
        </span>
      </div>
      {state.ok && <p className="mt-2 text-[13px] text-jade">{state.ok}</p>}
      {state.error && <p className="mt-2 text-[13px] text-rust">{state.error}</p>}
    </form>
  );
}
