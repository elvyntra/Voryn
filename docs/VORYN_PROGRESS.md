# Voryn Progress

## Current Phase
Phase 2 — Backend + Local Cache Foundation

## Current Checkpoint
Phase 2.5 — Contacts and synchronization

## Supabase Environment

- Live project `nrkaqtrsrfozqyzqbwth` now has migrations `202609110001` through `202609110003` applied.
- Backend foundation includes profiles, privacy/settings, devices, contacts, favorites, blocks, calls, meetings, call messages, notifications, reports, and the public `avatars` storage bucket.
- All 12 application tables have row-level security enabled. Calls and meetings are exposed through authenticated RPCs to avoid participant-policy recursion.
- Exact Voryn ID and phone discovery, presence, call records, meeting lifecycle, call messages, read state, and user reports have authenticated RPC boundaries.
- Phone contact matching no longer depends on the retired phone-verification flow.
- Project reference: `nrkaqtrsrfozqyzqbwth`
- Project API URL: `https://nrkaqtrsrfozqyzqbwth.supabase.co`
- Publishable key: supplied locally by the user; not committed to the repository.
- Runtime configuration uses `--dart-define=VORYN_SUPABASE_URL=...` and `--dart-define=VORYN_SUPABASE_ANON_KEY=...`.

## Completed
- Connect and Add Contact now use exact Supabase Voryn ID/phone lookups; Contacts and Favorites start empty and load only saved or synced Supabase records. Seeded sample people and their legacy local cache are excluded.
- Phase 2.5 contact boundary: local contact/favorite/block persistence, Supabase contact and block repositories, explicit device-contact permission and sync, verified-phone matching, and offline-safe reconciliation.
- Phase 2.4 discovery boundary: exact Voryn ID and normalized phone lookup services; mock Connect searches now use exact matching after explicit Search.
- Phase 2.3 identity boundary: typed profile model, profile persistence service, exact Voryn ID availability boundary, and phone verification service boundary.
- Phase 2.2 auth boundary: Supabase email sign-in, sign-up, password reset, session access, auth-state stream, and sign-out service methods. Local mock behavior remains available when Supabase is not configured.
- Phase 2.1 foundation: compile-time Supabase configuration, guarded client initialization boundary, and local cache abstraction.
- Light/Dark/System theme support with local persistence.
- Android and iOS display name set to `Voryn`.
- User-facing branding normalized to `Voryn`.
- Custom Connect keyboard removed; Connect uses native search input.
- Connect redesigned around Voryn ID/Phone search, local matches, recently connected users, favorites, and User Preview.
- My Profile removed from Contacts.
- Recents Call Details and active-call message actions remain available.

## Needs Verification
- Device launcher icon/name after reinstall.
- Responsive visual checks at mobile target sizes.
- Light, Dark, and System visual checks on device/emulator.

## Known Issues
- Kotlin incremental-cache warnings may appear during Android builds, but the debug APK completes successfully.
- `flutter run` and device visual inspection have not been performed here.

## Next
Apply the Phase 2.5 Supabase migration and validate contact sync on a physical device. Do not start Phase 2.6 without explicit approval.

## Rescue Audit
- Added `docs/VORYN_PHASE1_RESCUE_AUDIT.md` on 2026-09-12.
- The audit records the actual current repository state and preserves the already-integrated Phase 2/backend work.
- Incoming-call routing and LiveKit two-device reliability remain the highest-priority unresolved areas.

## Last Validation
- dart format: passed
- flutter analyze: passed
- flutter test: passed
- flutter build apk --debug: passed
- flutter run: not executed
# Call routing and lifecycle rescue — 2026-09-12

- Moved Firebase Messaging initialization and contact hydration post-frame so auth/onboarding can render without competing startup work.
- Added post-frame notification launch routing to the dedicated `/incoming-call` route after messaging launch details are available.
- Made LiveKit session teardown idempotent and detach room listeners before disconnecting; `CallRequestScreen` now prevents duplicate end/dispose teardown.
- Preserved existing Supabase, Firebase Messaging, LiveKit, and WebRTC integrations.
- Validation run: `dart format` completed; `flutter analyze` and `flutter test` were started but produced no terminal output in this environment and require device/Flutter process confirmation.
