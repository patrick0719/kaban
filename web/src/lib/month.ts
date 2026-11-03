import { todayManila } from "./money";

/** "2026-11" for the current Manila month. */
export function currentMonth() {
  return todayManila().slice(0, 7);
}

/**
 * A `?m=YYYY-MM` value from the URL, or the current month when it is missing,
 * malformed, or an impossible month like 2026-13. Months after the current one
 * also fall back to it unless `allowFuture` (scheduled entries can be dated ahead).
 */
export function parseMonth(m: string | undefined, { allowFuture = false } = {}) {
  const now = currentMonth();
  if (!m || !/^\d{4}-(0[1-9]|1[0-2])$/.test(m) || m < "2000-01" || m > "2100-12") return now;
  return m > now && !allowFuture ? now : m;
}

/** "2026-11", -1 -> "2026-10" */
export function shiftMonth(ym: string, by: number) {
  const [y, mo] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, mo - 1 + by, 1)).toISOString().slice(0, 7);
}

/** "2026-11" or "2026-11-01" -> "November 2026" (long) / "Nov" (short) */
export function monthName(iso: string, style: "long" | "short" = "long") {
  return new Intl.DateTimeFormat("en-PH", {
    month: style,
    ...(style === "long" ? { year: "numeric" as const } : {}),
    timeZone: "UTC",
  }).format(new Date(`${iso.slice(0, 7)}-01T00:00:00Z`));
}
