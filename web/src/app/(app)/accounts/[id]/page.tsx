import Link from "next/link";
import { notFound } from "next/navigation";
import { getAccounts, getContext, GROUP_LABEL } from "@/lib/context";
import { amountText, peso } from "@/lib/money";
import { FixBalanceForm } from "./FixBalanceForm";

export default async function AccountPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = await getContext();
  const account = (await getAccounts(ctx)).find((a) => a.id === id);
  if (!account) notFound();

  const isDebt = account.class === "liability";
  const shown = isDebt ? Math.max(-account.balance, 0) : account.balance;

  return (
    <div>
      <Link href="/accounts" className="text-[14px] text-muted">
        Back to accounts
      </Link>
      <p className="mt-6 text-[15px] text-muted">{GROUP_LABEL[account.kind]}</p>
      <h1 className="mt-1 text-[28px] font-semibold tracking-tight">{account.name}</h1>
      <p className="mt-1 text-[15px]">
        {isDebt ? (shown > 0 ? `Owe ${peso(shown)}` : "No debt") : `Balance ${peso(account.balance)}`}
      </p>
      <p className="mt-3 text-[14px] text-muted">
        {account.kind === "savings"
          ? "This is savings, so it is not counted in \"Safe to spend\" and does not appear in Back Tap."
          : isDebt
            ? "What you owe here is subtracted from \"Safe to spend\" right away."
            : "This counts toward \"Safe to spend\"."}
      </p>

      {ctx.canWrite && (
        <section className="mt-8 border-t border-line pt-6">
          <h2 className="mb-1 text-[17px] font-semibold">Correct the balance</h2>
          <p className="mb-4 text-[14px] text-muted">
            Enter what you really {isDebt ? "owe" : "have"}. The difference is saved as a correction, not as income or an expense.
          </p>
          <FixBalanceForm id={account.id} isDebt={isDebt} current={amountText(shown)} />
        </section>
      )}
    </div>
  );
}
