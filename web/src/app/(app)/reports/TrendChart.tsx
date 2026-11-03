"use client";

import { useState } from "react";

export type TrendPoint = { key: string; label: string; long: string; income: number; spent: number; saved: number };

// Validated pair (colorblind-safe against the paper surface): income vs spending.
const INCOME = "#178f78";
const SPENT = "#b8601a";

const fmt = new Intl.NumberFormat("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const peso = (c: number) => `₱${fmt.format(c / 100)}`;
const short = (c: number) => {
  const p = c / 100;
  return p >= 1_000_000 ? `₱${(p / 1_000_000).toFixed(1)}M` : p >= 1000 ? `₱${Math.round(p / 1000)}k` : `₱${Math.round(p)}`;
};

/** Six months of income vs spending as grouped bars. Tap a month to read its numbers. */
export function TrendChart({ points }: { points: TrendPoint[] }) {
  const [sel, setSel] = useState(points.length - 1);
  const W = 340, H = 168, top = 10, bottom = 22, left = 34;
  const plotH = H - top - bottom, plotW = W - left;
  const max = Math.max(1, ...points.flatMap((p) => [p.income, p.spent]));
  const step = niceStep(max / 3);
  const ceiling = Math.ceil(max / step) * step;
  const y = (v: number) => top + plotH - (v / ceiling) * plotH;
  const group = plotW / points.length;
  const bw = Math.min(14, group / 3);
  const p = points[sel];

  return (
    <figure>
      <div className="mb-3 text-[13px]">
        <p className="font-medium">{p.long}</p>
        <span className="mt-1 flex flex-wrap gap-x-4 gap-y-1">
          <span className="flex items-center gap-1.5">
            <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: INCOME }} />
            Income {peso(p.income)}
          </span>
          <span className="flex items-center gap-1.5">
            <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: SPENT }} />
            Spent {peso(p.spent)}
          </span>
        </span>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full" role="img" aria-label="Income and spending for the last six months">
        {[0, 1, 2, 3].map((i) => {
          const v = (ceiling / 3) * i;
          if (v > ceiling) return null;
          return (
            <g key={i}>
              <line x1={left} x2={W} y1={y(v)} y2={y(v)} stroke="var(--color-line)" strokeWidth={i === 0 ? 1 : 0.6} />
              <text x={left - 6} y={y(v) + 3.5} textAnchor="end" fontSize="9.5" fill="var(--color-muted)">
                {short(v)}
              </text>
            </g>
          );
        })}
        {points.map((pt, i) => {
          const cx = left + group * i + group / 2;
          const on = i === sel;
          return (
            <g key={pt.key} onClick={() => setSel(i)} style={{ cursor: "pointer" }}>
              {on && <rect x={cx - group / 2 + 2} y={top} width={group - 4} height={plotH} rx="6" fill="var(--color-line)" opacity="0.45" />}
              <Bar x={cx - bw - 1} w={bw} y0={y(0)} y1={y(pt.income)} fill={INCOME} />
              <Bar x={cx + 1} w={bw} y0={y(0)} y1={y(pt.spent)} fill={SPENT} />
              <text x={cx} y={H - 6} textAnchor="middle" fontSize="10.5" fontWeight={on ? 600 : 400} fill={on ? "var(--color-ink)" : "var(--color-muted)"}>
                {pt.label}
              </text>
              <title>{`${pt.long}: income ${peso(pt.income)}, spent ${peso(pt.spent)}`}</title>
              {/* full-height hit target, bigger than the bars */}
              <rect x={cx - group / 2} y={top} width={group} height={plotH + bottom} fill="transparent" />
            </g>
          );
        })}
      </svg>
      <figcaption className="sr-only">Tap a month to see its income and spending. The table below lists every month.</figcaption>
    </figure>
  );
}

/** A bar with a 4px rounded top, anchored square on the baseline. */
function Bar({ x, w, y0, y1, fill }: { x: number; w: number; y0: number; y1: number; fill: string }) {
  const h = y0 - y1;
  if (h <= 0.5) return null;
  const r = Math.min(4, w / 2, h);
  return <path d={`M${x} ${y0}V${y1 + r}Q${x} ${y1} ${x + r} ${y1}H${x + w - r}Q${x + w} ${y1} ${x + w} ${y1 + r}V${y0}Z`} fill={fill} />;
}

function niceStep(raw: number) {
  const pow = 10 ** Math.floor(Math.log10(Math.max(raw, 1)));
  const n = raw / pow;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * pow;
}
