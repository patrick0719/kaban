/** KABAN wordmark: a chest (domed lid, seam, latch) beside the name. Same drawing as the app icon. */
export function Wordmark({ className = "" }: { className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M2 11.5a10 6 0 0 1 20 0z" fill="var(--color-jade)" />
        <rect x="2" y="12.6" width="20" height="9" rx="1.6" fill="var(--color-jade)" />
        <rect x="10.4" y="10.1" width="3.2" height="5.4" rx="0.8" fill="var(--color-paper)" />
      </svg>
      <span className="text-[15px] font-bold tracking-[0.08em]">KABAN</span>
    </div>
  );
}
