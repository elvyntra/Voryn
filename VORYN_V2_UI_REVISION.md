# VORYN V2 — FROZEN UI REQUIREMENTS REVISION

## IMPORTANT: READ BEFORE WRITING CODE

You are working on an EXISTING Flutter application named **Voryn**.

The application already contains the Phase 1 UI implementation.

DO NOT rebuild the application from scratch.

Your task is to inspect the existing repository and MODIFY the current Phase 1 UI so that it matches the frozen **Voryn Requirements v2** defined below.

This is still a UI / local mock implementation phase.

---

# 0. HARD SCOPE RULES

## DO

- Inspect the existing project before modifying anything.
- Reuse the current:
  - architecture
  - theme
  - design tokens
  - Riverpod/providers if already used
  - GoRouter/navigation if already used
  - models
  - reusable widgets
  - mock repositories
  - existing screens
- Modify existing screens instead of creating duplicates.
- Preserve the premium dark Voryn visual language.
- Keep the existing four-tab application structure.
- Implement all V2 behavior using local/mock state.
- Keep code readable and properly formatted.
- Test the entire existing application after the revision.

## DO NOT

Do NOT integrate:

- Supabase
- Firebase
- LiveKit
- WebRTC
- FCM
- real authentication
- real phone verification
- real presence
- real contact permission
- real phone-book reading
- real push notifications
- real message delivery
- real audio/video
- real call waiting
- real screen sharing
- real account deletion
- real backend search

All of those belong to later phases.

For this revision, simulate them locally.

---

# 1. PRODUCT IDENTITY

Application:

**Voryn**

Tagline:

**Connect your way.**

Primary Voryn identity:

`@VorynID`

Example:

`@vikash`

Phone number is a private discovery identifier.

Email is NOT a calling/contact/discovery identifier anymore.

---

# 2. PRIMARY NAVIGATION — MUST REMAIN EXACTLY FOUR TABS

The bottom navigation must remain:

1. Connect
2. Recents
3. Contacts
4. Meetings

DO NOT add:

- Chats tab
- Messages tab
- Profile tab
- Settings tab

There must never be a fifth primary tab in V2.

---

# 3. GLOBAL DASHBOARD HEADER

All four primary screens must provide global access to:

- Call Messages / Inbox
- Profile avatar

Examples:

Connect                     [message icon] [VM]
Recents                     [message icon] [VM]
Contacts                    [message icon] [VM]
Meetings                    [message icon] [VM]

Use the same reusable header/action implementation where practical.

## Message icon

Show a small unread badge when mock unread messages exist.

Example:

message icon + badge "2"

Tapping it opens:

**Call Messages**

## Profile avatar

Circular avatar / initials.

Example:

`VM`

Tapping it opens the Profile / Account area.

Remove old temporary snackbar behavior from the avatar.

---

# 4. REMOVE EMAIL FROM VORYN DISCOVERY

This is a major V2 change.

Email must NOT be usable for:

- Connect search
- Add Contact
- User discovery
- User Preview identity
- calling
- contact matching
- phone-book matching
- public profile
- contact details

Remove old UI such as:

`rahul@example.com`

from calling/contact/discovery flows.

Email may remain internally/mock under Account information if the existing authentication UI requires it.

Do NOT treat email as a Voryn calling identity.

The two discovery identifiers are:

1. Voryn ID
2. Phone number

---

# 5. CONNECT SEARCH — MAJOR BEHAVIOR CHANGE

The previous live global search behavior is obsolete.

## New rule

Typing MUST NOT trigger backend/global discovery.

Typing can search ONLY:

- saved Voryn contacts
- cached contacts
- imported/matched phone contacts
- previously discovered users stored locally

This filtering is local and immediate.

## Unknown/global discovery

Only perform a mock "server search" when the user explicitly presses:

**Search**

The Search action should exist clearly in the Connect UI/custom keyboard experience.

Do NOT simulate server requests after every typed character.

---

# 6. EXACT UNKNOWN-USER DISCOVERY

Unknown users may be discovered only through:

### Exact Voryn ID

Example:

`@rahul`

### Exact phone number

Example:

`+91 99123 45678`

No global fuzzy-name discovery.

For unknown/global users:

`Rahul`

must NOT query a global directory.

`@rah`

must NOT return:

- @rahul
- @rahul_work
- @rahul123

Require the complete ID.

If invalid/incomplete:

**Enter an exact Voryn ID or phone number.**

If exact lookup fails:

**No Voryn user found**

**Check the Voryn ID or phone number and try again.**

---

# 7. LOCAL CONTACT SEARCH

Partial search IS allowed for data already stored locally.

Example saved contact:

Private/device name:
`Bhai`

Canonical profile:
`Rahul Sharma`

Voryn ID:
`@rahul`

Known phone:
`+91 99123 45678`

Local searches such as:

- `Bha`
- `Rah`
- `@rah`
- known phone digits

may immediately show Bhai.

This must NOT simulate a server request.

---

# 8. USER PREVIEW IS REQUIRED FOR UNKNOWN USERS

An exact server discovery must NOT immediately call someone.

Show User Preview first.

Example:

--------------------------------

[Avatar]

Rahul Sharma
@rahul

● Online

[ Call ]   [ Message ]

[ Save Contact ]

Block
Report

--------------------------------

If the viewer is permitted to know the phone number, show it.

Otherwise DO NOT show an empty/hidden phone row.

Do not show:

Phone: Hidden

Prefer simply omitting the field.

---

# 9. PROGRESSIVE PHONE PRIVACY

Implement this behavior in local/mock state.

## Case A — discovered using Voryn ID

Vikash searches:

`@rahul`

Result:

Rahul Sharma
@rahul

Phone is NOT visible.

The viewer may:

- call
- message
- save contact

but does not learn Rahul's phone number.

---

## Case B — discovered using exact phone

Vikash searches:

`+91 99123 45678`

and the number belongs to Rahul.

Result:

Rahul Sharma
@rahul
+91 99123 45678

The phone number is now a known identifier for Vikash.

---

## Case C — progressive knowledge

Suppose Vikash originally discovered Rahul through:

`@rahul`

Phone remains hidden.

Later Vikash enters Rahul's exact phone number.

The mock system recognizes the same linked user.

From that point onward, Vikash may see:

Rahul Sharma
@rahul
+91 99123 45678

The relationship gained phone visibility.

This must NOT create a duplicate Rahul contact.

---

# 10. IMPORTANT PRIVACY MODEL

Conceptually maintain:

User:
- stable internal userId
- canonicalDisplayName
- vorynId
- verifiedPhone

Contact relationship:
- linkedUserId
- customName
- phoneKnown
- source
- favorite

Example:

linkedUserId: rahul_uid
customName: Bhai
phoneKnown: true
source: phone
favorite: true

Do NOT key relationships only by Voryn ID or phone number.

The stable internal user ID is the conceptual identity.

---

# 11. MOCK USERS

Reuse existing mock users where possible.

Current user:

Vikash Mishra
@vikash
+91 98765 43210

Contacts:

Bhai
canonical: Rahul Sharma
@rahul
+91 99123 45678
Online

College Aman
canonical: Aman Verma
@aman
+91 98111 22334
Online

Sarah
@sarah
Busy / In Call where required by mock scenario

Rahul Office
canonical: Rahul Mehta
@rahul_work
Offline

Alex Johnson
@alex
Online

Do not add email fields to discovery/contact UI.

---

# 12. PHONE-BOOK CONTACTS

Add mock phone-book contact support to Contacts.

This remains UI/local state only.

DO NOT request actual OS Contacts permission yet.

Provide:

**Import / Sync Phone Contacts**

When selected, show a permission-education UI.

Example:

# Find people you know

Voryn can match phone numbers from your contacts with people already using Voryn.

Voryn will never automatically modify your phone contacts.

[ Continue ]

Then simulate permission locally.

Possible mock states:

- Not requested
- Allowed
- Denied
- Permanently denied

---

# 13. PHONE CONTACTS MUST NOT BE DUPLICATED

Suppose device phone book contains:

Bhai
+91 99123 45678

and this belongs to:

Rahul Sharma
@rahul

Do NOT create:

Bhai
AND
Rahul Sharma

as two independent contacts.

Instead link the device contact with the Voryn account.

Render:

Bhai

Rahul Sharma · @rahul

+91 99123 45678

Optional subtle label:

Phone contact

---

# 14. VORYN-ONLY CONTACTS

If someone is found through:

`@sarah`

and Sarah is not in the device phone book:

Allow:

**Save to Voryn Contacts**

This does NOT write Sarah into the device phone book.

The user may choose a private custom name.

Example:

College Sarah

Sarah · @sarah

---

# 15. MANUAL PHONE SEARCH FOR UNSAVED NUMBER

Suppose the user searches an exact phone number not currently in the phone book.

Voryn finds:

Aman Verma
@aman

Provide:

**Save to Voryn**

Optionally provide:

**Save to phone contacts**

BUT:

"Save to phone contacts" must only show mock feedback during this phase.

Do NOT modify actual device contacts.

Never automatically write Voryn users into the device phone book.

---

# 16. AUTOMATIC FUTURE CONTACT DISCOVERY

Implement this as a local/mock demonstration.

Important V2 behavior:

Suppose device phone book contains:

Lucky
+91 98000 11223

Initially:

Lucky is NOT on Voryn.

Show:

Lucky
Not on Voryn

Optional:
Invite to Voryn

Later, a mock "Sync Contacts" action can simulate Lucky creating:

Lucky Kumar
@lucky

using the same verified phone number.

After sync:

Lucky

Lucky Kumar · @lucky

+91 98000 11223

On Voryn

The user must NOT need to manually search for Lucky again.

---

# 17. DISPLAY NAME PRIORITY

Display-name priority is:

1. Device phone-book name
2. Private Voryn custom name
3. Canonical Voryn profile name

Example:

Phone book:
Lucky

Voryn profile:
Lakshya Sharma

Voryn ID:
@lucky

Display:

Lucky

Lakshya Sharma · @lucky

Never automatically rename the user's device contact.

---

# 18. CONTACT SYNC SETTINGS

Add under appropriate Settings / Privacy / Contacts area:

**Sync phone contacts** [ON/OFF]

Default mock state:

ON

Also provide:

**Refresh contacts**

This performs a local mock sync and may demonstrate Lucky becoming available on Voryn.

Turning sync OFF prevents automatic mock synchronization.

---

# 19. PRESENCE — AUTOMATIC ONLY

Remove manual presence selection.

Users must NOT manually choose:

- Online
- Offline
- Busy

Online/Offline is system controlled.

For Phase V2 UI, simulate it from mock state.

Conceptually:

Online = connected/reachable

Offline = not connected/reachable

Do not expose a manual Online/Offline toggle.

---

# 20. BUSY STATE

Busy should conceptually mean:

**currently involved in another call**

It is not a manually selected profile status.

Important:

Busy does NOT automatically block another incoming call.

See Call Waiting section below.

---

# 21. DO NOT DISTURB — MANUAL

DND is different from presence.

Profile/account area must provide:

**Do Not Disturb** [ON/OFF]

The user controls this.

DND should persist in local mock state across normal navigation.

When ON:

- new calls are blocked
- messages remain allowed
- user may still manually open/join a meeting
- existing active call does not need to end

Profile may display:

● Online
Do Not Disturb

Do NOT convert DND into Offline.

---

# 22. DND CALL ATTEMPT

If someone attempts to call a user whose mock state has DND ON:

Do not start the call.

Show:

# Do Not Disturb

Bhai isn't accepting calls right now.

You can send a message instead.

[ Message ]

[ Close ]

Do not use alarming red styling.

---

# 23. DND AND MEETINGS

DND blocks disruptive incoming meeting-call invitations.

But a DND user can still:

- open Meetings
- enter a code/link
- use Pre-Join
- join manually

DND means:

"Do not interrupt me"

not:

"Disable Voryn."

---

# 24. CALL MESSAGES — NOT FULL CHAT

Voryn V2 supports lightweight asynchronous call-related messages.

This is NOT a general messaging application.

Messages remain short.

Target maximum:

approximately 120 characters.

Presets include:

- Call me when you're free.
- Are you free for a call?
- I'll call you later.
- Can we talk for a minute?

Incoming-call quick replies:

- Can't talk right now.
- I'll call you back.
- Can I call you later?
- I'm in a meeting.

Allow short custom text.

---

# 25. MESSAGES WORK WHILE OFFLINE

A message may be sent when the receiver is:

- Online
- Offline
- DND
- In another call

For Phase V2, simulate this locally.

Example:

Rahul Office
Offline

User taps Message.

After Send:

**Message sent**

Do NOT claim:

Delivered

unless the mock state explicitly simulates delivery.

Conceptual future states:

sending
sent
delivered
failed

No read receipts.

---

# 26. CALL MESSAGES INBOX

Because offline messages can exist, Voryn needs a persistent place to view them.

DO NOT add a fifth bottom tab.

Use the global message icon near the profile avatar.

Open:

# Call Messages

Example mock entries:

Bhai
"Call me when you're free."
2 min ago
Unread

College Aman
"Are you free for a call?"
18 min ago

Rahul Office
"I'll call you later."
Yesterday

Provide:

- unread/read visual state
- sender avatar
- sender display name
- message
- timestamp
- Call action where appropriate
- Message/reply action

Keep this lightweight.

DO NOT implement:

- chat threads
- typing indicator
- read receipts
- image messages
- video messages
- files
- voice notes
- reactions
- stickers
- general chat inbox

---

# 27. MESSAGE BADGE

Global message icon should show unread count.

Example:

2

Opening/reading mock messages may update the local unread count.

Keep state consistent across all four main tabs.

---

# 28. PROFILE ACCESS FROM ALL FOUR TABS

The top-right avatar must work from:

- Connect
- Recents
- Contacts
- Meetings

It opens the same Profile / Account experience.

---

# 29. PROFILE SCREEN

Example:

[ VM ]

Vikash Mishra
@vikash

● Online

Do Not Disturb              [ OFF ]

[ Edit Profile ]

--------------------------------

Settings

Privacy
Notifications
Calling
Appearance
Blocked Users
Devices

--------------------------------

Help & About
Report a Problem

--------------------------------

Log Out

Delete Account

Do NOT display phone/email prominently on the normal public Profile.

Phone/email are account/authentication information.

---

# 30. EDIT PROFILE

Allow local/mock editing of:

- profile avatar
- full name
- Voryn ID

Do not make phone/email public profile fields.

Voryn ID validation:

- 3–24 characters
- letters
- numbers
- underscore
- globally unique conceptually

Mock taken IDs:

- rahul
- admin
- support
- voryn
- test

Do not actually contact a backend.

---

# 31. VORYN ID CHANGE SAFETY

Conceptually the account has a stable internal UUID.

Changing:

@vikash

to:

@vikash_m

must NOT create a new account/contact.

Existing:

- contacts
- messages
- recents
- meetings

must conceptually remain associated through the stable internal user ID.

For UI phase, preserve local state accordingly where practical.

---

# 32. PHONE NUMBER CHANGE PRINCIPLE

Do not build full real phone-number changing yet.

But the UI/data model must assume:

Changing verified phone number does NOT create a new Voryn account.

The stable user ID remains unchanged.

People who only knew the OLD phone number must NOT automatically learn the NEW number.

Do not implement behavior that contradicts this future requirement.

---

# 33. PRIVACY SETTINGS

Provide a Privacy screen.

Include:

### Who can call me

Options:

- Everyone who knows my Voryn ID or phone number
- Saved contacts only
- Nobody

Default mock:

Everyone who knows my Voryn ID or phone number

This setting is separate from DND.

DND is temporary interruption control.

"Who can call me" is a privacy policy.

---

# 34. CALL PRIVACY BEHAVIOR

Before starting a mock call, check:

1. Is receiver offline?
2. Is receiver DND?
3. Does receiver privacy allow this caller?
4. Otherwise allow call.

Offline:

Show unavailable/offline state + Message.

DND:

Show DND state + Message.

Privacy blocked:

Show:

**Calls aren't available for this user.**

[ Message ]
[ Close ]

Do not expose unnecessary private reasons.

---

# 35. BLOCKING

Blocking a user means:

- they cannot call
- they cannot message
- their interactions should be prevented by local mock checks

Blocked Users screen should support:

- list blocked users
- Unblock
- confirmation

Unknown User Preview must provide:

Block
Report

---

# 36. REPORTING

Keep/reuse existing report UI.

Possible reasons:

- Spam
- Harassment
- Impersonation
- Suspicious activity
- Other

Local success feedback only.

---

# 37. CALL WAITING — NOW REQUIRED V2 UI

The previous Phase 1 rule that dual-call waiting was outside v1 is obsolete.

V2 MUST contain call-waiting UI.

If Vikash is currently speaking with:

Bhai

and Aman calls:

Do NOT automatically reject Aman because Vikash is busy.

Show compact incoming overlay:

Aman Verma
@aman

Incoming audio call

[ Decline ]

[ Hold & Accept ]

[ Message ]

Existing Bhai call remains alive underneath.

---

# 38. HOLD & ACCEPT

When selected:

Existing call:

Bhai
ON HOLD

Second call:

Aman
CONNECTED

Only one independent conversation is active at a time before merging.

Provide:

**Switch Calls**

**Merge Calls**

---

# 39. SWITCH CALLS

Example initial:

Aman
ACTIVE

Bhai
ON HOLD

Tap:

Switch Calls

Result:

Bhai
ACTIVE

Aman
ON HOLD

Switching must update local mock UI/state clearly.

---

# 40. ENDING ACTIVE CALL WITH HELD CALL

If:

Aman = active
Bhai = held

and Aman call ends:

DO NOT send user directly to the main dashboard.

Return/resume the remaining Bhai call.

Mock behavior should clearly demonstrate this.

---

# 41. MERGE CALLS

If:

Bhai = held
Aman = active

user can select:

**Merge Calls**

Then convert the UI into the existing Voryn group-room experience.

Example:

Voryn Call

3 participants

Vikash
Bhai
Aman

After merge:

- remove independent active/held distinction
- use group call UI
- participant count updates
- standard group controls apply

This is local simulation only.

---

# 42. DND OVERRIDES CALL WAITING

If the user has DND ON:

A second incoming call must NOT interrupt the active call.

The caller can still send a message.

No call-waiting overlay should appear.

---

# 43. EXISTING AUDIO CALL CONTROLS

Preserve Voryn's locked audio call control layout:

Audio | Video | Mute

Hold  | Share | End

Do not redesign this unnecessarily.

---

# 44. EXISTING VIDEO CALL CONTROLS

Preserve:

Mute | Camera | Flip

Audio | Share | End

Do not redesign unnecessarily.

---

# 45. EXISTING MEETING/GROUP UI

Preserve the unified Voryn room design.

Meetings and group calls should continue using the same Voryn calling language.

Do not create a completely separate corporate-style meeting interface.

---

# 46. ACCOUNT SETTINGS

Profile/account area should include:

- Edit Profile
- Privacy
- Notifications
- Calling
- Appearance
- Blocked Users
- Devices
- Help & About
- Report a Problem
- Log Out
- Delete Account

Keep organization clean and not cluttered.

---

# 47. LOG OUT

Log Out is NOT Delete Account.

Mock confirmation:

# Log out of Voryn?

You'll need to sign in again to continue.

[ Cancel ]

[ Log Out ]

Local mock logout routes to Welcome / Sign In.

Do not delete account data.

---

# 48. DELETE ACCOUNT — REQUIRED

Add a clearly separated destructive action:

**Delete Account**

Use restrained destructive styling.

Do not place it where accidental taps are likely.

Flow:

Delete Account
    ↓
Warning
    ↓
Re-authentication concept
    ↓
Final confirmation
    ↓
Mock account deletion
    ↓
Clear mock account-specific local state
    ↓
Welcome screen

---

# 49. DELETE ACCOUNT WARNING

Example:

# Delete your Voryn account?

This permanently deletes your Voryn account and account data.

You'll be signed out and will need to create a new account if you want to use Voryn again.

[ Cancel ]

[ Continue ]

Then show a second confirmation.

Example:

# Are you sure?

This action cannot be undone in this UI preview.

[ Keep Account ]

[ Delete Account ]

Do NOT actually delete anything from a backend.

---

# 50. RE-AUTHENTICATION UI

Before final account deletion, include a mock re-authentication step.

Example:

# Confirm it's you

For your security, confirm your identity before deleting your account.

[ Continue ]

Simulate successful confirmation locally.

Do not implement real authentication here.

---

# 51. DELETED VORYN ID PRINCIPLE

The UI/data model should not assume a deleted Voryn ID becomes instantly available.

Conceptually:

deleted IDs may remain reserved for a server-defined period.

No backend implementation now.

---

# 52. CONTACT/CACHE SECURITY PRINCIPLE

Account-specific cached data must conceptually belong to the signed-in user.

On mock Delete Account:

clear relevant local mock:

- contacts
- messages
- call history
- meeting history
- discovery permissions
- blocked users
- cached profiles

as appropriate for the simulated deleted account.

On normal Logout:

do not pretend the server account was deleted.

---

# 53. LOCAL-FIRST ARCHITECTURE PREPARATION

Future backend will use Supabase.

DO NOT integrate Supabase now.

However, structure local repositories/models so the UI does not assume every render requires a network query.

The future architecture is:

LOCAL CACHE
     +
SUPABASE SYNCHRONIZATION
     +
REALTIME LIVE STATE

For Phase V2:

simulate these layers locally.

---

# 54. CACHE-FIRST DISPLAY

Screens such as:

- Contacts
- Recents
- Call Messages
- Meeting history
- previously discovered users

should conceptually render from local/cache state.

Do not add fake network loaders every time these screens open.

---

# 55. DATA THAT WILL REQUIRE FRESHNESS LATER

Do not permanently assume cached values are authoritative for:

- Online/Offline
- DND
- active-call state
- incoming calls
- blocks
- account deletion
- privacy settings
- new messages
- meeting participation

These will use realtime/server state later.

For now use local mock state.

---

# 56. OFFLINE APP STATE

Keep cached information viewable while the device is mock-offline.

User should still be able to view:

- contacts
- previous call history
- previous messages
- meeting history

Actions requiring server behavior should show:

# You're offline

Check your internet connection and try again.

[ Retry ]

Do not show endless loading indicators.

---

# 57. CONTACT SYNC MOCK STATES

Provide local mock handling for:

- Syncing contacts...
- Contacts updated
- No new Voryn contacts
- Lucky is now on Voryn
- Contacts permission denied
- Contacts permission blocked
- You're offline

Do not perform real synchronization.

---

# 58. PERMISSION EDUCATION

Contacts permission should be added to the existing permission-education system.

Example:

Contacts

Used to find people from your phone book who are already on Voryn.

Voryn will not automatically modify your device contacts.

Possible UI states:

Not requested
Allowed
Denied
Blocked

If blocked:

[ Open Settings ]

Mock action only.

---

# 59. UNKNOWN CALLER SAFETY

Incoming calls from unsaved users must clearly show:

- avatar
- canonical name
- @VorynID
- call type

Provide normal:

- Accept
- Decline
- Message

Block/Report should be accessible from the relevant incoming/user-detail flow without cluttering the main accept/decline controls.

Do not expose hidden phone numbers.

---

# 60. RATE LIMITING — FUTURE ARCHITECTURAL REQUIREMENT

No real implementation in this UI phase.

But add documentation/TODO architecture notes where appropriate that future Supabase backend must rate-limit:

- Voryn ID discovery
- phone-number discovery
- repeated calls
- repeated messages
- spam behavior

Do NOT implement fake client-side security and claim it is secure.

---

# 61. MESSAGE DELIVERY STATES

Use local states where useful:

sending
sent
delivered
failed

Do not add:

read
seen
typing

Example offline recipient:

Message sent

Do not falsely show Delivered.

---

# 62. PROFILE PUBLIC VS ACCOUNT INFORMATION

Keep public-facing Voryn identity minimal:

- avatar
- canonical name
- @VorynID
- automatic presence
- DND when relevant

Phone visibility depends on relationship/discovery permission.

Email is account-only.

Do not publicly expose authentication information.

---

# 63. REMOVE OLD QR / SHARE PROFILE REQUIREMENT

The current frozen V2 does NOT require:

- profile QR
- Share Profile
- Scan QR
- Copy profile QR

If these exist from Phase 1.10 and are isolated, remove them cleanly if doing so will not destabilize unrelated code.

Do not build new QR functionality.

---

# 64. REMOVE MANUAL AVAILABILITY SELECTOR

Remove old UI allowing:

Online
Busy
Do Not Disturb
Offline

as one selector.

Replace it with:

automatic presence:
Online / Offline

plus independent:

Do Not Disturb [ON/OFF]

Busy is system/call-derived.

---

# 65. REMOVE OLD EMAIL SEARCH TESTS

Any tests expecting:

rahul@example.com

to find Bhai must be removed/updated.

Email is no longer part of Connect discovery.

---

# 66. UPDATED CONNECT TEST CASES

Test local cached behavior.

### Local

Input:

`Bha`

Expected:

Bhai appears locally.

No mock backend search required.

Input:

`Rah`

Expected:

locally known matching contacts may appear.

### Unknown exact Voryn ID

Input:

`@lucky`

Press Search.

Expected:

mock exact lookup.

### Incomplete Voryn ID

Input:

`@luc`

Press Search.

Expected:

NO fuzzy global results.

### Exact phone

Input exact known mock phone.

Press Search.

Expected:

one exact mock discovery.

### Normal unknown name

Input:

`Random Person`

Press Search.

Expected:

Enter an exact Voryn ID or phone number.

---

# 67. PHONE PRIVACY TEST CASES

Test:

1. Discover Rahul by @rahul.
2. Verify phone is absent.
3. Save Rahul.
4. Reopen contact.
5. Phone remains absent.
6. Search Rahul's exact phone.
7. Resolve to same linkedUserId.
8. Verify no duplicate contact created.
9. Verify phone now appears.
10. Reopen Rahul.
11. Phone remains known in local mock relationship.

---

# 68. PHONE-BOOK LINK TEST

Mock device contact:

Bhai
+91 99123 45678

Mock Voryn account:

Rahul Sharma
@rahul
same phone

After mock contact sync:

Expected:

ONE contact.

Primary:

Bhai

Secondary:

Rahul Sharma · @rahul

No duplicate Rahul row.

---

# 69. LUCKY FUTURE-DISCOVERY TEST

Initial:

Lucky
+91 98000 11223
Not on Voryn

Trigger mock future sync.

Expected:

Lucky

Lucky Kumar · @lucky

+91 98000 11223

On Voryn

No manual user search required.

---

# 70. DND TESTS

Test:

DND OFF
→ normal calls allowed.

DND ON
→ call attempt blocked.
→ Message remains available.

DND ON while active call
→ existing call remains.
→ second incoming call does not interrupt.

DND user manually joins meeting
→ allowed.

---

# 71. CALL WAITING TESTS

Test:

Call Bhai.
Connect.

Trigger mock incoming call from Aman.

Expected:

call-waiting overlay.

Tap Hold & Accept.

Expected:

Bhai = held.
Aman = active.

Tap Switch Calls.

Expected:

Bhai = active.
Aman = held.

Tap Switch again.

Expected reverse.

End Aman.

Expected:

Bhai becomes available/resumed.

Repeat scenario.

Tap Merge Calls.

Expected:

group Voryn room with:

Vikash
Bhai
Aman

---

# 72. MESSAGE TESTS

Test message to:

- Online user
- Offline user
- DND user
- user in another call

All should allow sending unless blocked/privacy restrictions explicitly prevent messages.

Offline:

show Sent, not falsely Delivered.

Unread incoming messages should update global badge.

---

# 73. BLOCK TEST

Block Aman.

Then verify:

- Aman cannot be called/messaged through local flows where block applies.
- User Preview reflects blocked state appropriately.
- Blocked Users lists Aman.
- Unblock restores normal mock behavior.

---

# 74. PROFILE GLOBAL ACCESS TEST

From each:

Connect
Recents
Contacts
Meetings

tap avatar.

Expected:

same Profile area.

Return.

Expected:

return to correct originating tab.

---

# 75. CALL MESSAGES GLOBAL ACCESS TEST

From each of the four tabs:

tap Call Messages icon.

Expected:

same inbox.

Return.

Expected:

return to originating screen/tab correctly.

---

# 76. RESPONSIVE REQUIREMENTS

Mandatory testing widths/sizes:

360 × 800
393 × 873
412 × 915
432 × 960

The app must not overflow.

Pay particular attention to:

- custom Voryn keyboard
- new Search action
- header message/profile icons
- unread badges
- call-waiting overlay
- dual-call management UI
- Profile menu
- Delete Account confirmations
- contact-sync cards
- Call Messages inbox

Respect SafeArea.

---

# 77. ACCESSIBILITY

Maintain:

- minimum approximately 48dp touch targets
- readable contrast
- semantic labels for icon-only actions
- no status represented by color alone
- text scaling without catastrophic overflow
- clear destructive-action labels
- disabled-state semantics
- accessible modal/bottom-sheet behavior

---

# 78. DESIGN LANGUAGE

Do NOT redesign Voryn.

Continue existing premium dark visual language.

Expected direction:

background:
#000000

alternate:
#08090C

surface:
#121316

secondary surface:
#191A1F

elevated:
#27282E

primary text:
#F7F7F8

secondary:
#A5A6AD

accent:
#6C7CFF

call:
#34C759

end/destructive:
#FF453A

warning:
#FFB340

offline:
#8E8E93

Use existing project tokens instead of hardcoding these repeatedly if tokens already exist.

---

# 79. CODE QUALITY

Do not create huge one-line Flutter widget trees.

Use readable multiline widgets.

Extract reusable components where they clearly reduce duplication.

Do not over-engineer.

Avoid unnecessary new dependencies.

Dispose:

- controllers
- timers
- focus nodes
- animation controllers

correctly.

Avoid:

setState() after dispose

Timer callbacks after dispose

navigation after disposed context

---

# 80. STATE MANAGEMENT

Use the project's existing state-management solution.

If Riverpod is already used, continue using Riverpod.

Do NOT introduce another state-management framework.

Important V2 local state should be shared where appropriate:

- current profile
- DND
- mock presence
- contacts
- phoneKnown relationship
- phone-book mappings
- blocked users
- messages
- unread count
- call state
- active/held calls
- meetings
- mock offline state

Avoid each screen maintaining contradictory copies of the same mock data.

---

# 81. ROUTING

Reuse existing routing.

Do not replace GoRouter if it already works.

Add/update routes only as necessary for:

- Call Messages
- Profile/account
- Privacy
- Contact Sync
- call waiting/dual-call management
- account deletion flow

Avoid duplicate routes to existing screens.

---

# 82. REGRESSION — EXISTING FEATURES MUST STILL WORK

After implementing V2 revisions, verify:

## Authentication UI

Splash
Welcome
Sign In
Create Account

## Onboarding

Complete Profile
Phone verification
Create Voryn ID

## Connect

custom keyboard
local search
explicit exact discovery
User Preview

## Contacts

saved contacts
favorites
phone-book mock contacts
Add Contact
Edit Contact
Remove Contact
sync

## Recents

history
Call Details
callbacks

## Meetings

New Meeting
Meeting Created
Join
Pre-Join
Meeting Details

## Calling

audio
video
incoming
outgoing
DND
hold
screen-share mock
add people
mini-call bar
group calls
post-call
call waiting
switch calls
merge calls

## Profile

Profile
Edit Profile
Settings
Privacy
Notifications
Calling
Appearance
Blocked Users
Devices
Help
Logout
Delete Account

## Messages

send
offline send
DND send
Call Messages inbox
unread badge

---

# 83. REMOVE / REPLACE OBSOLETE V1 BEHAVIOR

Search the repository for obsolete assumptions and update them.

Specifically look for:

- email discovery
- email contact lookup
- live global search per character
- fuzzy unknown-user lookup
- manual Online selector
- manual Offline selector
- manual Busy selector
- "Busy means reject new call"
- dual-call waiting marked unsupported
- temporary profile-avatar snackbar
- temporary call-selector feedback that should now use existing call UI
- QR/share profile functionality no longer required
- phone/email always displayed on User Preview
- duplicate phone-book/Voryn contacts

Do not blindly delete code.

Understand its usage first.

---

# 84. DO NOT EXPAND PRODUCT SCOPE

Voryn V2 is now frozen.

Do NOT add:

- full chat
- fifth Chats tab
- media messaging
- voice notes
- stories
- status feed
- reactions
- typing indicators
- read receipts
- social feed
- recording
- AI summaries
- calendar scheduling
- new calling SDK
- backend
- Firebase
- Supabase
- LiveKit
- WebRTC

If you notice a potentially useful future feature:

DO NOT IMPLEMENT IT.

Mention it in the completion report under:

**Future consideration**

---

# 85. IMPLEMENTATION ORDER

Use this order to reduce regressions.

## Step 1 — Inspect

Inspect:

- project structure
- pubspec
- routes
- providers/state
- models
- Connect implementation
- Contacts implementation
- call state implementation
- Profile implementation
- existing tests

Do not modify blindly.

## Step 2 — Fix current baseline

Before V2 changes:

run analyzer/tests.

If existing compilation errors exist, fix them first without expanding scope.

## Step 3 — Update shared models/state

Introduce V2 concepts cleanly:

- stable userId
- vorynId
- verifiedPhone
- phoneKnown
- contact source
- deviceName/customName
- DND
- automatic mock presence
- message state
- active/held call state

## Step 4 — Update global shell

Add consistent:

- Call Messages icon
- unread badge
- Profile avatar

to all four main screens.

## Step 5 — Update Connect

Remove email/global live lookup.

Implement:

local filtering
+
explicit Search
+
exact Voryn ID/phone discovery.

## Step 6 — Update Contacts

Implement:

phone-book mock contacts
linking
sync
Lucky future-discovery demo
progressive phone visibility.

## Step 7 — Update User Preview/privacy

Only expose permitted phone information.

## Step 8 — Add Call Messages

Inbox + unread state + offline/DND message behavior.

## Step 9 — Update Profile/settings

DND
privacy
contact sync
account menu
delete-account flow.

## Step 10 — Update calling

Implement mock:

second incoming call
Hold & Accept
Switch Calls
Merge Calls
DND override.

## Step 11 — Remove obsolete V1 behavior

Clean old assumptions.

## Step 12 — Regression/testing

Complete app regression.

---

# 86. MANDATORY VALIDATION

After implementation run:

```bash
dart format .
```

Then:

```bash
flutter analyze
```

Target:

NO analyzer errors.

Then:

```bash
flutter test
```

Fix failures caused by V2 changes.

Then:

```bash
flutter build apk --debug
```

This MUST succeed.

If a Flutter device/emulator is available:

```bash
flutter run
```

Inspect runtime logs.

Look specifically for:

- RenderFlex overflow
- setState() after dispose
- Timer after dispose
- Provider/Riverpod exceptions
- route exceptions
- asset errors
- font errors
- unhandled exceptions
- keyboard overflow
- modal overflow
- call-state transition exceptions

---

# 87. MANUAL VISUAL TEST

Manually inspect at minimum:

### Connect

- custom keyboard
- local partial search
- explicit Search
- exact @VorynID lookup
- exact phone lookup
- invalid lookup
- unknown User Preview
- phone hidden/revealed correctly

### Contacts

- phone contacts
- Voryn-only contacts
- no duplicate linked contacts
- Lucky before sync
- Lucky after sync
- private/device name priority

### Messages

- inbox
- unread badge
- online send
- offline send
- DND send

### Profile

- accessible from all four tabs
- automatic presence
- DND
- Settings
- Privacy
- contact sync
- Logout
- Delete Account

### Calls

- normal audio
- normal video
- DND block
- second incoming call
- Hold & Accept
- Switch Calls
- End active → held call
- Merge Calls

### Meetings

Verify existing meeting flows were not broken.

---

# 88. COMPLETION REPORT

When finished, provide a concise report containing:

## Files changed

List important files.

## V2 features implemented

List what actually works.

## Removed/replaced V1 behavior

List obsolete behavior removed.

## Validation

Report exact results of:

- dart format .
- flutter analyze
- flutter test
- flutter build apk --debug
- flutter run, if executed

Do NOT claim a command succeeded unless it was actually run.

## Known limitations

Clearly state anything incomplete.

## Future consideration

Only mention useful ideas.

Do NOT implement them.

---

# 89. HARD STOP

After this V2 UI revision is complete:

STOP.

Do NOT start:

- Supabase setup
- database schema
- authentication backend
- Realtime
- contact backend sync
- message backend
- LiveKit
- WebRTC
- push notifications
- production calling

Wait for explicit authorization.

The next phase will be planned separately.

---

# FINAL PRODUCT RULE

Treat this requirement as frozen:

**Voryn is a privacy-focused calling and meeting application where users connect through an exact Voryn ID or phone number, maintain phone-book and Voryn contacts without unnecessary duplication, use automatic presence and manual DND, exchange lightweight asynchronous call-related messages, and manage audio/video/group calls including call waiting, holding, switching, and merging.**

Voryn is NOT a general social network or full messaging application.

Implement this revision against the EXISTING application without rebuilding working functionality unnecessarily.
