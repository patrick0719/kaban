"use client";

import { useEffect, useState, useTransition, type FormEvent } from "react";

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
  const [ready, setReady] = useState(false);
  useEffect(() => setReady(true), []);
  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    startTransition(() => dispatch(form));
  };
  return { onSubmit, ready };
}
