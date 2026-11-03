"use client";

import { useState, useSyncExternalStore, useTransition, type FormEvent } from "react";

const noop = () => () => {};

/** False during server render and hydration, true once the page is interactive. */
export function useHydrated() {
  return useSyncExternalStore(noop, () => true, () => false);
}

/**
 * Submit a form to a server action WITHOUT React clearing the fields.
 * (A plain `<form action>` resets every input after each submit, so a typo
 * in the amount would also wipe the chosen category and account.)
 * Browser validation (`required`, `type=email`) still runs first.
 *
 * `ready` is false until the page is interactive. Keep the submit button
 * disabled until then, so an early tap can't do a plain page submit that
 * saves nothing.
 */
export function useSubmit(dispatch: (form: FormData) => void) {
  const [, startTransition] = useTransition();
  const ready = useHydrated();
  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    startTransition(() => dispatch(form));
  };
  return { onSubmit, ready };
}

/**
 * Run `fn` once each time an action returns a new result, during render
 * (React's "adjust state when a prop changes" pattern, no extra effect pass).
 * `fn` may only set this component's own state.
 */
export function useOnResult<T>(result: T, fn: (result: T) => void) {
  const [seen, setSeen] = useState(result);
  if (seen !== result) {
    setSeen(result);
    fn(result);
  }
}

/**
 * One idempotency key per attempt: a double tap saves once, a failed save
 * retries with the same key, and a successful save gets a new key for the next one.
 */
export function useRequestKey(result: { ok?: unknown }) {
  const [key, setKey] = useState(() => crypto.randomUUID());
  useOnResult(result, (r) => {
    if (r.ok) setKey(crypto.randomUUID());
  });
  return key;
}
