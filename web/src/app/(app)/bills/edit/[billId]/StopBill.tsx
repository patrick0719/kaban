"use client";

import { useState } from "react";
import { stopBill } from "../../actions";

export function StopBill({ billId, name }: { billId: string; name: string }) {
  const [confirming, setConfirming] = useState(false);
  if (!confirming) {
    return (
      <button type="button" className="btn-danger w-full" onClick={() => setConfirming(true)}>
        Stop this bill
      </button>
    );
  }
  return (
    <form action={stopBill} className="space-y-3 rounded-lg border border-rust/30 bg-rust-soft/40 p-4">
      <input type="hidden" name="bill_id" value={billId} />
      <p className="text-[14px]">
        {name} will no longer appear or send reminders. Payments you already recorded stay in your history.
      </p>
      <div className="grid grid-cols-2 gap-2">
        <button type="button" className="btn-quiet" onClick={() => setConfirming(false)}>
          Cancel
        </button>
        <button className="btn bg-rust text-white">Stop bill</button>
      </div>
    </form>
  );
}
