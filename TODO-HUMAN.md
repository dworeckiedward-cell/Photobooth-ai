# TODO — manual setup outside this repo

Actions Eduardo (or whoever owns the infra) needs to take. The iOS code is in
place; these unblock the corresponding features end-to-end.

---

## M3 — 360 cloud sync backend

iOS uploads raw .mov files + polls cloud job status. Currently the API
client tries the cloud first and silently falls back to the local
passthrough renderer on 404, so iOS works without these — operators just
won't get real share URLs until backend ships.

1. **Supabase: new table `booth360_jobs`** (rough shape — adapt to your
   migration conventions):
   ```
   id              uuid pk default gen_random_uuid()
   event_id        uuid references events(id) on delete cascade
   user_id         uuid references auth.users(id)
   status          text check (status in ('idle','uploading','queued',
                       'processing','completed','failed'))
   current_step    text  -- 'uploading'|'stabilizing'|'slowMotion'|...
   progress        numeric default 0
   raw_video_url   text
   final_video_url text
   public_share_url text
   settings_snapshot jsonb
   error_message   text
   created_at      timestamptz default now()
   completed_at    timestamptz
   ```

2. **Supabase Storage bucket**: `booth360-renders/` (public read for
   `final_video_url`, signed-url upload for `raw_video_url`).

3. **Backend (Next.js, `ai-photobooth/`) endpoints — wire shape matches
   `Booth360JobDTO` in iOS `APIModels.swift`:**
   - `POST /api/booth360/jobs` — multipart form with `eventId`, `settings`
     (JSON string), `file` (the .mov). Stores raw upload, enqueues render
     job, returns `{ job: Booth360JobDTO }` with status=`queued`.
   - `GET /api/booth360/jobs/{id}` — returns current job DTO. iOS polls
     this every 2s.
   - `GET /api/events/{slug}/booth360-jobs` — list jobs for an event.
   - `PATCH /api/events/{slug}` — accepts `{ share_mode: "public" | "private" }`,
     returns updated event.

4. **`share_mode` column on existing `events` table**:
   ```sql
   alter table events
     add column share_mode text default 'private'
     check (share_mode in ('private','public'));
   ```

5. **Render worker** (separate from iOS scope) — pulls queued jobs from
   `booth360_jobs`, runs whatever you chose (Cloud FFmpeg, Mux, RunPod,
   etc.), updates `progress`, sets `status=completed` + `final_video_url`
   + `public_share_url`.

---

## M2 — Apple Sign In activation

Required for the auth flow to actually exchange tokens once the user taps
"Sign in with Apple". iOS code is wired and will currently fail with a
500/timeout against `/api/auth/apple` until the backend side is configured.

1. **Apple Developer Portal** (https://developer.apple.com/account/resources)
   - Identifiers → app id `com.servify.Photobooth-ai` → enable
     "Sign In with Apple" capability (should already be checked, confirm).
   - Create a **Services ID** (e.g. `com.servify.boothify.web`) for the
     server-side callback used by Supabase.
   - Generate a **Sign in with Apple key (.p8)** and download it (one
     chance — Apple won't show it again). Note the Key ID.
   - Note the Team ID (visible in the top-right of the dev portal).

2. **Supabase Dashboard** (your project → Auth → Providers → Apple)
   - Enable Apple provider.
   - Paste in: Services ID, Key ID, Team ID, the .p8 secret key.
   - Set the OAuth callback URL on the Apple Service ID to the value
     Supabase shows in that screen (Supabase has a copy button for it).

3. **Backend (webapp repo `ai-photobooth/`)** — needs these endpoints
   (or to be confirmed they already exist; iOS calls them):
   - `POST /api/auth/apple` — accepts `{ identityToken, nonce,
     first_login_email?, first_login_full_name? }`, calls
     `supabase.auth.signInWithIdToken({ provider: "apple",
     token: identityToken, nonce })`. On the FIRST sign-in for a user,
     persist `first_login_email` + `first_login_full_name` to your `users`
     table — Apple never re-sends them.
   - `POST /api/auth/refresh` — accepts `{ refresh_token }`, returns a
     fresh session.
   - `DELETE /api/auth/account` — hard-deletes the Supabase user + cascades
     to events/photos/360 jobs. Until this exists the iOS UI shows
     "signed out locally — email support to finish".

4. **Testing:** Sign in with Apple **doesn't work in the simulator** for a
   user who hasn't already authenticated this app on a real device first.
   Test on a real iPhone/iPad signed into iCloud.

---

