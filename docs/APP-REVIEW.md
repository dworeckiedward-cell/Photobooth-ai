# Boothify — App Store Connect: Privacy Labels & Review Notes

Author-ready copy for App Store Connect, derived from the actual code.
Verify against the current build before submitting.

---

## App Privacy labels (App Store Connect → App Privacy)

Boothify does **not** track users across apps/sites and shows **no ads**.
Answer "Used for Tracking? No" for every type.

| Data type | Collected? | Linked to identity? | Purpose |
|-----------|-----------|---------------------|---------|
| **Email address** | Yes | Yes | App Functionality — operator account (Sign in with Apple); guest photo delivery when a guest opts to receive by email |
| **Phone number** | Yes | Yes | App Functionality — guest photo delivery by SMS (only when the guest provides it) |
| **Name** | Yes | Yes | App Functionality — operator account display name (Apple, first sign-in only) |
| **Photos** (User Content) | Yes | Yes | App Functionality — the captured photo and its AI-styled result for the event |
| **User ID** | Yes | Yes | App Functionality — account + event ownership (Apple `sub` / internal user id) |
| **Other user content** (survey answers) | Yes | Yes | App Functionality — optional guest survey the operator enables |
| **Crash data / diagnostics** | Yes | No | Analytics/App Functionality — crash + error reporting (Sentry) to keep the app stable |

Not collected: location, contacts, browsing history, health, financial info,
advertising identifiers.

**Third parties that process data** (declare as needed): Supabase (hosting/DB),
Google Gemini (AI image generation), Apple/Stripe (payments), email/SMS provider
(photo delivery). No data is sold.

---

## Permission usage strings (already in the build — all verified used)

| Permission | Used by | String |
|-----------|---------|--------|
| Camera | Photobooth capture + 360 recording | "Boothify needs the camera to take photobooth shots and record 360 videos." |
| Microphone | Audio track on 360 video recording | "Boothify records audio together with your 360 videos so guests can include sound from the event." |
| Face ID | Unlock operator settings (PIN gate biometrics) | "Boothify uses Face ID to unlock operator settings without entering a PIN." |
| Photo Library (add) | Save AI photos / 360 videos | "Boothify saves your AI photos and 360 videos to your Photos library." |
| Photo Library (read) | Import an existing photo; pick a brand logo (`PhotosPicker`) | "Boothify needs photo library access to import existing photos." |

---

## Review Notes (paste into App Store Connect → App Review Information → Notes)

> **What Boothify is.** Boothify is an AI photo-booth tool for event operators
> (photographers, event companies). An operator creates an event, guests take a
> photo, and the app turns it into an AI portrait (or an on-device "Instant Look"
> that needs no internet). Photos can be printed, shared, or delivered by
> email/SMS. It is designed for both iPhone and iPad (kiosk use).
>
> **Sign in.** Login is **Sign in with Apple only**. Please sign in with your own
> Apple ID — no separate demo account is needed. Account deletion is available at
> Settings → Account → Delete account; it permanently deletes the account, its
> events and photos, and revokes the Apple token.
>
> **Reaching the paid features.** Subscription plans are shown on the paywall
> (Settings → Subscription). Premium features are currently reachable without an
> active subscription in this build, so no sandbox purchase is required to
> evaluate them. Restore Purchases is on the paywall.
>
> **AI generation.** Turning a photo into an AI portrait uses a cloud AI service.
> If cloud AI is unavailable, the booth still works fully offline via on-device
> "Instant Looks" (12 styles), a photo strip, and studio backdrops — so the core
> experience never dead-ends.
>
> **Kiosk Mode.** An operator can lock the app to a single event ("Start Kiosk
> Mode") so guests at a live event only see the capture flow. Exit is via a long
> press gated by the operator's PIN. This is intended, not a navigation trap.
>
> **Green screen / backdrops** use on-device person segmentation and require a
> real device (they no-op on Simulator).
>
> Contact for any questions: support@boothify.app

---

## Pre-submit sweep (Section 14 / 17)

- [ ] No dead buttons / placeholder screens visible (Settings info rows no longer
      show a disclosure chevron; legal rows open real pages; the **Effects** panel
      is hidden until wired — it persisted settings that never altered output).
- [ ] The 360 AI Booth is hidden from the guest entry until its backend ships
      (`MVP_HIDE_AI360_FROM_GUESTS`) — reviewers won't hit an unfinished feature.
- [ ] Dark mode: the app is dark-first by design; verify no unreadable contrast.
- [ ] Fresh install → sign in → create event → capture → result, with bad network.
- [ ] Purchase / Restore / cancel in Sandbox once products exist.
- [ ] Real iPad screenshots (target is iPhone **and** iPad).
