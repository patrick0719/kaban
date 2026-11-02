"use client";

import { useEffect, useState } from "react";
import { removePushSubscription, savePushSubscription, sendTestReminder } from "./reminders";

type Status = "checking" | "unsupported" | "install" | "denied" | "off" | "on";

function toKey(base64url: string) {
  const pad = "=".repeat((4 - (base64url.length % 4)) % 4);
  const raw = atob((base64url + pad).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

function deviceName() {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return "iPhone";
  if (/iPad/.test(ua)) return "iPad";
  if (/Android/.test(ua)) return "Android phone";
  return "This browser";
}

async function registration() {
  const existing = await navigator.serviceWorker.getRegistration("/");
  return existing ?? navigator.serviceWorker.register("/sw.js", { scope: "/" });
}

export function ReminderToggle({ vapidKey }: { vapidKey: string | null }) {
  const [status, setStatus] = useState<Status>("checking");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ ok?: string; error?: string }>({});

  useEffect(() => {
    (async () => {
      const ios = /iPhone|iPad/.test(navigator.userAgent);
      const standalone =
        window.matchMedia("(display-mode: standalone)").matches ||
        (navigator as Navigator & { standalone?: boolean }).standalone === true;
      if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) {
        setStatus(ios && !standalone ? "install" : "unsupported");
        return;
      }
      if (Notification.permission === "denied") return setStatus("denied");
      const reg = await registration();
      const sub = await reg.pushManager.getSubscription();
      setStatus(sub ? "on" : "off");
    })().catch(() => setStatus("unsupported"));
  }, []);

  async function turnOn() {
    if (!vapidKey) return;
    setBusy(true);
    setNote({});
    try {
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        setStatus(permission === "denied" ? "denied" : "off");
        return;
      }
      const reg = await registration();
      await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: toKey(vapidKey) });
      const saved = await savePushSubscription(sub.toJSON(), deviceName());
      if (saved.error) {
        await sub.unsubscribe();
        setNote({ error: saved.error });
        return;
      }
      setStatus("on");
      setNote({ ok: "Reminders are on for this device." });
    } catch {
      setNote({ error: "Could not turn on reminders on this device." });
    } finally {
      setBusy(false);
    }
  }

  async function turnOff() {
    setBusy(true);
    setNote({});
    try {
      const reg = await registration();
      const sub = await reg.pushManager.getSubscription();
      if (sub) {
        await removePushSubscription(sub.endpoint);
        await sub.unsubscribe();
      }
      setStatus("off");
    } finally {
      setBusy(false);
    }
  }

  async function test() {
    setBusy(true);
    setNote(await sendTestReminder());
    setBusy(false);
  }

  if (!vapidKey) {
    return <p className="text-[14px] text-muted">Reminders are not set up on the server yet.</p>;
  }
  if (status === "checking") return <p className="text-[14px] text-muted">Checking this device…</p>;
  if (status === "install") {
    return (
      <p className="text-[14px] text-muted">
        On iPhone, reminders work in the installed app. In Safari, tap Share, then Add to Home Screen. Open KABAN from your Home
        Screen and come back here.
      </p>
    );
  }
  if (status === "unsupported") return <p className="text-[14px] text-muted">This browser cannot show reminders.</p>;
  if (status === "denied") {
    return (
      <p className="text-[14px] text-muted">
        Notifications are blocked for KABAN. Turn them on in your phone&apos;s Settings, under Notifications, then KABAN.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {status === "on" ? (
        <>
          <p className="text-[15px]">Reminders are on for this device.</p>
          <div className="grid grid-cols-2 gap-2">
            <button type="button" className="btn-quiet" onClick={test} disabled={busy}>
              Send a test
            </button>
            <button type="button" className="btn-quiet" onClick={turnOff} disabled={busy}>
              Turn off
            </button>
          </div>
        </>
      ) : (
        <button type="button" className="btn-primary w-full" onClick={turnOn} disabled={busy}>
          {busy ? "Turning on…" : "Turn on bill reminders"}
        </button>
      )}
      {note.ok && <p className="rounded-lg bg-jade-soft px-3 py-2 text-sm text-jade">{note.ok}</p>}
      {note.error && <p className="rounded-lg bg-rust-soft px-3 py-2 text-sm text-rust">{note.error}</p>}
    </div>
  );
}
