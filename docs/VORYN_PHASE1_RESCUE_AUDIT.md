# Voryn Rescue Audit

Date: 2026-09-12

This audit describes the repository as it exists. The pasted Phase 1 rescue note is older than the current project: Supabase, Firebase Messaging, and LiveKit are already integrated and must not be removed as part of UI cleanup.

## Status Legend

- DONE: screen or behavior exists and has current code coverage.
- PARTIAL: present, but still uses mock/local behavior or needs visual/regression work.
- BROKEN: known runtime or integration issue.
- MISSING: no dedicated implementation found.

## Screen Inventory

| Area | Status | Evidence / remaining work |
| --- | --- | --- |
| Splash, Welcome, Sign In, Sign Up, Forgot Password | DONE | `lib/features/auth/auth_screens.dart`; Supabase auth and Google flow are integrated. |
| Landing and onboarding profile/Voryn ID | PARTIAL | Screens exist; device verification and production edge cases need review. |
| Four-tab shell | DONE | Connect, Recents, Contacts, Meetings are the only primary tabs. |
| Connect and User Preview | PARTIAL | Real Supabase lookup path exists; visual and state regression review remains. |
| Contacts and Add Contact | PARTIAL | Supabase-backed contacts and device sync exist; permission/error states need device verification. |
| Recents and Call Details | PARTIAL | Backend call history and actions exist; needs end-to-end device verification. |
| Call Messages inbox | PARTIAL | Shared call-message service exists; needs full state/error review. |
| Meetings home, create, ready, join, pre-join, details, room | PARTIAL | Screens exist; meeting records/actions and visual polish are not fully production-ready. |
| Incoming audio/video call | BROKEN / PARTIAL | Android lock-screen launch and custom screen routing have had active regressions; latest implementation needs two-device verification. |
| Connected audio call | PARTIAL | UI and controls exist; LiveKit connection reliability remains unresolved. |
| Connected video call and pre-call | PARTIAL | UI and mock controls exist; real media/session reliability remains unresolved. |
| Call waiting, hold-and-accept, switch, merge, mini call bar | MISSING | No complete state machine found for these flows. |
| Call failure/reconnect states | PARTIAL | Several local labels/states exist; recovery behavior needs completion. |
| Post-call | DONE / PARTIAL | Screen exists; verify all actions and history updates. |
| Profile, settings, appearance, privacy, notifications, calling | PARTIAL | Screens/services exist; audit navigation and persisted state. |
| Blocked users, devices, help/about, delete-account mock | PARTIAL | Some routes/components exist; complete-flow verification is needed. |
| Reusable loading/error/offline/empty states | PARTIAL | Several feature-local states exist; consolidation and visual consistency remain. |

## Current Priority

1. Stabilize incoming-call notification-to-call-screen routing on locked and unlocked devices.
2. Stabilize LiveKit room creation, token retrieval, join, accept, decline, and hang-up across two devices.
3. Finish visual/state consistency for call screens, meetings, profile/settings, and system states.
4. Run responsive device checks and update `VORYN_PROGRESS.md` with implemented versus verified behavior.

## Explicitly Deferred

The pasted note requests a mock-only Phase 1 and says to remove backend infrastructure. That conflicts with the current project history and `VORYN_PROGRESS.md`, so this audit does not authorize destructive rollback of Supabase, Firebase, FCM, or LiveKit.
