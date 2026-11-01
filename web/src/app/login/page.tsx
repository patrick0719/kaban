"use client";

import { useActionState, useState } from "react";
import { signIn, signUp, type AuthState } from "./actions";
import { Wordmark } from "@/components/Wordmark";

export default function LoginPage() {
  const [mode, setMode] = useState<"in" | "up">("in");
  const [state, action, pending] = useActionState<AuthState, FormData>(mode === "in" ? signIn : signUp, {});

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center px-6 py-12">
      <Wordmark className="mb-10" />
      <h1 className="text-[28px] font-semibold leading-tight tracking-tight">
        {mode === "in" ? "Mag-log in" : "Gumawa ng account"}
      </h1>
      <p className="mt-2 text-[15px] text-muted">
        {mode === "in"
          ? "Pera ng bahay, nasa isang lugar."
          : "Gamitin ang email kung saan ka in-invite, para makapasok ka sa household."}
      </p>

      <form action={action} className="mt-8 space-y-4">
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Email</span>
          <input name="email" type="email" autoComplete="email" required defaultValue={state.email ?? ""} className="field" />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Password</span>
          <input
            name="password"
            type="password"
            autoComplete={mode === "in" ? "current-password" : "new-password"}
            required
            className="field"
          />
        </label>

        {state.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{state.error}</p>}
        {state.info && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{state.info}</p>}

        <button className="btn-primary w-full" disabled={pending}>
          {pending ? "Sandali…" : mode === "in" ? "Mag-log in" : "Gumawa ng account"}
        </button>
      </form>

      <button
        type="button"
        onClick={() => setMode(mode === "in" ? "up" : "in")}
        className="mt-6 text-sm text-muted underline underline-offset-4"
      >
        {mode === "in" ? "In-invite ka? Gumawa ng account" : "May account na? Mag-log in"}
      </button>
    </main>
  );
}
