// All money in KABAN is integer centavos (PHP 1.00 = 100).

const fmt = new Intl.NumberFormat("en-PH", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** 125075 -> "1,250.75" (no sign, no peso). */
export function amountText(centavos: number): string {
  return fmt.format(Math.abs(centavos) / 100);
}

/** 125075 -> "₱1,250.75", -125075 -> "−₱1,250.75". */
export function peso(centavos: number): string {
  return `${centavos < 0 ? "−" : ""}₱${amountText(centavos)}`;
}

/** "1,250.75" / "₱ 1250.5" / "1250" -> 125075 centavos; null if invalid. */
export function toCentavos(input: string): number | null {
  const s = input.replace(/[₱,\s]/g, "");
  if (!/^\d{1,9}(\.\d{1,2})?$/.test(s)) return null;
  const [whole, frac = ""] = s.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

/** Today's date in Manila as YYYY-MM-DD. */
export function todayManila(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Manila" }).format(new Date());
}

const dayFmt = new Intl.DateTimeFormat("fil-PH", { month: "short", day: "numeric", timeZone: "UTC" });
const longDayFmt = new Intl.DateTimeFormat("fil-PH", {
  weekday: "long",
  month: "long",
  day: "numeric",
  timeZone: "UTC",
});

/** "2026-11-16" -> "Nob 16" */
export function shortDate(iso: string): string {
  return dayFmt.format(new Date(`${iso}T00:00:00Z`));
}

/** "2026-11-01" -> "Linggo, Nobyembre 1" */
export function longDate(iso: string): string {
  return longDayFmt.format(new Date(`${iso}T00:00:00Z`));
}
