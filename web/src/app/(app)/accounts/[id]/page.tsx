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
        Bumalik sa accounts
      </Link>
      <p className="mt-6 text-[15px] text-muted">{GROUP_LABEL[account.kind]}</p>
      <h1 className="mt-1 text-[28px] font-semibold tracking-tight">{account.name}</h1>
      <p className="mt-1 text-[15px]">
        {isDebt ? (shown > 0 ? `Utang ${peso(shown)}` : "Walang utang") : `Laman ${peso(account.balance)}`}
      </p>
      <p className="mt-3 text-[14px] text-muted">
        {account.kind === "savings"
          ? "Ipon ito, kaya hindi kasama sa \"Puwedeng gastusin\" at hindi lumalabas sa Back Tap."
          : isDebt
            ? "Ang utang dito ay ibinabawas agad sa \"Puwedeng gastusin\"."
            : "Kasama ito sa \"Puwedeng gastusin\"."}
      </p>

      {ctx.canWrite && (
        <section className="mt-8 border-t border-line pt-6">
          <h2 className="mb-1 text-[17px] font-semibold">Itama ang balanse</h2>
          <p className="mb-4 text-[14px] text-muted">
            Ilagay ang totoong {isDebt ? "utang" : "laman"}. Ang diperensya ay itatala bilang pagtatama, hindi bilang kita o gastos.
          </p>
          <FixBalanceForm id={account.id} isDebt={isDebt} current={amountText(shown)} />
        </section>
      )}
    </div>
  );
}
