/** Turn a database error into a short message for the person using the app. */
export function friendly(message: string | undefined): string {
  const m = message ?? "";
  if (/not allowed to write/i.test(m)) return "You are a viewer in this household, so you cannot add or change entries.";
  if (/exceeds remaining due/i.test(m)) return "The payment is more than what is left on this bill.";
  if (/would exceed the account balance/i.test(m)) return "That is more than this account has free. Some of it may already be set aside for other goals.";
  if (/not allowed to void/i.test(m)) return "Only the person who recorded this, or an admin, can void it.";
  if (/already a member/i.test(m)) return "That email is already a member.";
  if (/only owners and admins/i.test(m)) return "Only owners and admins can invite people.";
  if (/invite not valid/i.test(m)) return "This invite is no longer valid. Ask for a new one.";
  if (/at most 5 active/i.test(m)) return "You can have up to 5 Back Tap tokens. Revoke one first.";
  if (/cannot be used for quick entry/i.test(m)) return "Savings accounts cannot be used with Back Tap.";
  if (/less than what was already paid/i.test(m)) return "That is less than what was already paid for this month.";
  if (/within the last month or later/i.test(m)) return "Choose a due date from the last month or later.";
  if (/pay a credit card bill with a transfer/i.test(m)) return "Credit card bills are paid by moving money into the card.";
  if (/bill not available/i.test(m)) return "This bill is not available to you.";
  if (/already belongs to another goal/i.test(m)) return "That savings account is already used by another goal.";
  if (/not used for spending/i.test(m)) return "Choose a savings account that is not used for everyday spending.";
  if (/more than the goal has saved/i.test(m)) return "That is more than this goal has saved.";
  if (/target date must be today or later/i.test(m)) return "Choose a target date from today onward.";
  if (/goal not available/i.test(m)) return "This goal is not available to you.";
  if (/set money aside in a spending account/i.test(m)) return "Set money aside in cash, a bank or an e-wallet.";
  return m.replace(/^KABAN:\s*/, "") || "Something went wrong. Try again.";
}
