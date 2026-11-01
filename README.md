# KABAN

Pera ng bahay, nasa isang lugar. A shared household finance PWA for the Philippines.

```
supabase/
  migrations/        0001-0006, run in order in the Supabase SQL Editor
  functions/         quick-entry Edge Function (Back Tap / Apple Shortcuts)
  tests/             Postgres test suites (run on a local DB, never on Supabase)
  *.sql              one-off household scripts (setup, menu, settings)
web/                 Next.js 15 app (deploy this folder to Vercel)
```

## Deploy the app (Vercel)

1. Import this repository in Vercel and set **Root Directory** to `web`.
2. Add two environment variables (Supabase Dashboard -> Project Settings -> API):
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` (the anon/publishable key, never the service_role key)
3. Deploy. Then in Supabase -> Authentication -> URL Configuration, set **Site URL** to the Vercel URL
   so sign-up confirmation emails link back to the app.

## Database

Apply `supabase/migrations/*.sql` in order. Security model:

- Every money movement is a ledger transaction; balances and "available to spend" are computed, never stored.
- Row Level Security on every table; clients write only through `SECURITY DEFINER` functions in the
  unexposed `kaban_private` schema, reached through `SECURITY INVOKER` wrappers in `public`.
- Quick entry uses hashed, scoped, expiring, revocable tokens. The service_role key lives only in the Edge Function.

## Local tests

```
psql -f supabase/tests/00_supabase_stubs.sql      # Supabase stand-ins, local only
psql -f supabase/migrations/0001_kaban_core.sql   # ...through 0006
psql -f supabase/tests/10_ledger_scenarios.sql    # 60 checks
psql -f supabase/tests/20_decisions.sql           # 32 checks (fresh DB)
```
