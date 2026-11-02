/** Turn a database error into a short message for the person using the app. */
export function friendly(message: string | undefined): string {
  const m = message ?? "";
  if (/not allowed to write/i.test(m)) return "You are a viewer in this household, so you cannot add or change entries.";
  if (/exceeds remaining due/i.test(m)) return "The payment is more than what is left on this bill.";
  if (/would exceed the account balance/i.test(m)) return "That is more than this account holds.";
  if (/not allowed to void/i.test(m)) return "Only the person who recorded this, or an admin, can void it.";
  if (/already a member/i.test(m)) return "That email is already a member.";
  if (/only owners and admins/i.test(m)) return "Only owners and admins can invite people.";
  if (/invite not valid/i.test(m)) return "This invite is no longer valid. Ask for a new one.";
  if (/at most 5 active/i.test(m)) return "You can have up to 5 Back Tap tokens. Revoke one first.";
  if (/cannot be used for quick entry/i.test(m)) return "Savings accounts cannot be used with Back Tap.";
  return m.replace(/^KABAN:\s*/, "") || "Something went wrong. Try again.";
}
