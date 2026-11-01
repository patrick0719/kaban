/** Turn a database error into a short message for the person using the app. */
export function friendly(message: string | undefined): string {
  const m = message ?? "";
  if (/not allowed to write/i.test(m)) return "Viewer ka lang sa household na ito, kaya hindi ka makakapagtala.";
  if (/exceeds remaining due/i.test(m)) return "Mas malaki ang bayad kaysa sa natitirang utang ng bill.";
  if (/would exceed the account balance/i.test(m)) return "Mas malaki ito kaysa sa laman ng account.";
  if (/not allowed to void/i.test(m)) return "Ang gumawa lang nito o ang admin ang puwedeng mag-void.";
  if (/already a member/i.test(m)) return "Member na ang email na iyan.";
  if (/only owners and admins/i.test(m)) return "Owner o admin lang ang puwedeng mag-invite.";
  if (/invite not valid/i.test(m)) return "Hindi na valid ang invite na ito. Humingi ng bago.";
  if (/at most 5 active/i.test(m)) return "Hanggang 5 Back Tap token lang ang puwede. Mag-revoke muna ng isa.";
  if (/cannot be used for quick entry/i.test(m)) return "Hindi puwedeng gamitin ang ipon sa Back Tap.";
  return m.replace(/^KABAN:\s*/, "") || "May nangyaring mali. Subukan ulit.";
}
