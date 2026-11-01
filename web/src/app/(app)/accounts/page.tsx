import Link from "next/link";
import { getAccounts, getContext, groupAccounts } from "@/lib/context";
import { peso } from "@/lib/money";

export default async function AccountsPage() {
  const ctx = await getContext();
  const accounts = await getAccounts(ctx);
  const untouched = accounts.filter((a) => a.balance === 0).length;

  return (
    <div>
      <h1 className="text-[24px] font-semibold tracking-tight">Accounts</h1>
      {untouched > 0 && (
        <p className="mt-2 text-[14px] text-muted">
          Para tama ang kuwenta, buksan ang bawat account at ilagay ang totoong laman nito ngayon. Sa credit card, ilagay ang
          utang.
        </p>
      )}

      {groupAccounts(accounts).map(([label, list]) => (
        <section key={label} className="mt-7">
          <h2 className="border-b border-line pb-1.5 text-[13px] text-muted">{label}</h2>
          <ul className="divide-y divide-line">
            {list.map((a) => (
              <li key={a.id}>
                <Link href={`/accounts/${a.id}`} className="flex items-baseline justify-between py-3 text-[15px] active:bg-line/40">
                  <span>
                    {a.name}
                    {a.owner_user_id && <span className="ml-2 text-[12px] text-muted">personal</span>}
                    {a.kind === "savings" && <span className="ml-2 text-[12px] text-muted">hindi kasama sa panggastos</span>}
                  </span>
                  <Balance account={a} />
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

function Balance({ account }: { account: { class: string; balance: number } }) {
  if (account.class === "liability") {
    return account.balance < 0 ? (
      <span className="font-medium text-rust">Utang {peso(-account.balance)}</span>
    ) : (
      <span className="text-muted">Walang utang</span>
    );
  }
  return <span className={`font-medium ${account.balance < 0 ? "text-rust" : ""}`}>{peso(account.balance)}</span>;
}
