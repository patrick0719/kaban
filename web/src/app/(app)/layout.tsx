import { BottomNav } from "@/components/BottomNav";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-dvh max-w-md">
      <main className="px-5 pb-32 pt-[max(env(safe-area-inset-top),1.25rem)]">{children}</main>
      <BottomNav />
    </div>
  );
}
