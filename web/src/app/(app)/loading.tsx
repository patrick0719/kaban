// Shown the instant a tab is tapped, while the server prepares the page.
export default function Loading() {
  return (
    <div aria-busy="true" aria-label="Loading" className="animate-pulse">
      <div className="h-6 w-32 rounded bg-line" />
      <div className="mt-8 space-y-3">
        <div className="h-4 w-full rounded bg-line/70" />
        <div className="h-4 w-5/6 rounded bg-line/70" />
      </div>
      <div className="mt-6 h-12 w-48 rounded bg-line" />
      <div className="mt-10 space-y-4">
        {[0, 1, 2, 3, 4].map((i) => (
          <div key={i} className="flex justify-between">
            <div className="h-4 w-40 rounded bg-line/70" />
            <div className="h-4 w-20 rounded bg-line/70" />
          </div>
        ))}
      </div>
    </div>
  );
}
