# Voryn Master Project Context

Authoritative context for the existing Voryn Flutter project. Inspect the repository before changing architecture or rebuilding working features. The latest explicit user instruction wins; update this document when a permanent requirement changes.

## Product
The official user-facing name is **Voryn**. Use that capitalization in visible text, native launcher labels, and accessibility labels. Internal identifiers such as `voryn`, `VorynUser`, package names, routes, and asset paths may remain unchanged. Official tagline: **Connect your way.**

Voryn is a premium communication app for audio/video calls, meetings, call history, contacts, presence, DND, and lightweight call-related messages. The current phase is UI plus local/mock state.

## Design, Theme, And Navigation
Preserve the existing Voryn design system, approved logo/assets, shared widgets, routing, and theme tokens. Light, Dark, and System are real working modes; System follows the device dynamically, is the default, and persists locally.

Primary tabs are exactly `Connect` | `Recents` | `Contacts` | `Meetings`. Each primary screen keeps the global Call Messages/Inbox action and exactly one Profile avatar. Do not add a fifth tab or duplicate profile access.

## Connect
Connect is a discovery and quick-interaction hub, not a dialer. The custom Flutter keyboard is permanently removed; use the native device keyboard. Supported modes are exactly Voryn ID and Phone. Do not add email search, fuzzy global search, or lookup during typing. Typing may filter local/cached users; explicit Search or the keyboard Search action performs the current mock exact lookup.

Connect provides a compact introduction, Voryn ID/Phone selector, native input, Search, Recently connected local users, local Matches, Favorites where supported, and exact not-found state. Tapping a user opens User Preview with Audio call, Video call, Message, Save Contact where allowed, and existing Block/Report behavior. Reuse mock flows; do not start backend or real media work.

## Contacts, Recents, And Calls
Contacts manages saved/matched people, favorites, search/filter, sync/import UI, and details. It must not contain a My Profile section/card/row; Profile is accessed through the global avatar.

Recents remains call history. Call Details uses Audio call, Video call, and Message actions. Active-call controls remain intact; Message is secondary. Preserve shared lightweight Call Messages state, exact discovery privacy, blocking, DND, presence, and offline/local-first behavior.

## Phase Boundaries
Phase 1 is UI and local/mock state, currently in final V2 cleanup/regression. Phase 2 is Supabase/backend and cache foundations. Phase 3 is real communication/media. Phase 4 is integration and release. Do not start a later phase without explicit approval. Do not start Supabase, Firebase, LiveKit, WebRTC, or other real infrastructure during Phase 1.

## Startup And Validation
Read this file and `docs/VORYN_PROGRESS.md` before each task. Inspect actual code and report discrepancies. Make targeted changes and reuse existing architecture. Validate with:

```text
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

Run and visually inspect on a device when available. Report implemented and verified work separately.
