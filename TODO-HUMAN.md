# TODO — manual setup for RUN B (iOS)

Actions Eduardo needs to take to test the new upload pipeline end-to-end.
The iOS code is in place; these unblock the realistic flow.

---

## RUN B test prerequisites

Backend must be live first (RUN A → `pnpm supabase db push` + Vercel
redeploy of commit `1076c84` or newer). Once it is:

1. **Point iOS at the right backend.** In Xcode → Edit Scheme → Run →
   Arguments → Environment Variables (or `Info.plist`
   `BOOTHIFY_API_BASE_URL`), set to your prod / staging URL.
   Currently defaults to `http://localhost:3000`.

2. **Real-device test of the direct-upload flow:**
   - Install on iPhone 12+ (FFmpeg needs hardware encoder).
   - Sign in with Apple → confirm session lands (check `AccountSettingsView`).
   - Record a 360 → wait for FFmpeg to finish → wait a few seconds for
     upload.
   - In Xcode's Network tab confirm the file PUT goes to a
     `*.supabase.co` host (NOT your Vercel domain). That's how you
     prove direct upload is bypassing the 4.5 MB cap.
   - Open the SMS share link on a guest phone — video plays.

3. **Resilience test (BM1):**
   - Record a 360.
   - Immediately enable Airplane mode after FFmpeg finishes but before
     upload completes (~3-5s window).
   - Confirm: upload marked `.failed`, "Send again" surfaces in
     Result/Gallery (BM1 UI).
   - Disable Airplane mode → tap Send again → upload succeeds, real
     share URL replaces the mock.
   - Kill + reopen the app while upload is queued → check that on the
     next launch `Booth360UploadQueue.replayPending` re-fires it
     automatically.

4. **SMS counter test (BM2):**
   - After a successful upload, send the link via SMS through the
     in-app TwilioClient.
   - Check the Cloud Status panel — `sent` counter should tick to 1.

---

## Known constraints

- Apple Sign In does NOT work in the simulator for fresh accounts. Use
  a real device signed into iCloud for first login.
- BoothifyAPI.shared.uploadVideoDirect uses a transient URLSession with
  default timeouts (60s request, 300s resource). Larger takes on very
  slow networks may need an iPad on cellular hotspot rather than
  congested venue WiFi.

---

(End of RUN B TODO-HUMAN. See backend repo `ai-photobooth/TODO-HUMAN.md`
for RUN A's deploy block.)
