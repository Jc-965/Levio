# Privacy Policy for ParkiWell

**Effective Date: July 16, 2026**
**Last Updated: July 16, 2026**

<!-- MAINTAINER NOTE (not rendered on GitHub): This document is a product
draft. Before public launch, have qualified counsel review it for every
launch jurisdiction. -->

## 1. Introduction

ParkiWell ("ParkiWell," "the app," "we," "us," or "our") is a care-organization
app for people living with Parkinson's disease and the people who support
them. It helps users record symptoms, keep medication schedules, follow
guided speech and movement practice, and participate in an optional
community.

This Privacy Policy explains what information ParkiWell handles, why, where it
is stored, who can access it, and the choices and rights you have. It
applies to the ParkiWell mobile and web applications.

**Data controller:** Jesse Chen, the developer of ParkiWell.
For privacy requests, contact **jcscen@gmail.com**.

Because ParkiWell handles health-related information you choose to record, we
hold ourselves to the practices described here regardless of whether a
specific law requires them.

## 2. Summary of Key Points

- ParkiWell works **local-first**: your records live in the app's private
  storage on your device and remain usable offline.
- Cloud sync is **optional** and happens only when you create or sign in
  to a synced account.
- We do **not** sell personal data, show ads, use advertising SDKs, track
  you across other apps or websites, or run remote analytics or remote
  crash reporting in the current release.
- Practice recordings you capture with the camera **never leave your
  device**.
- You can delete your account and associated synced records from within
  the app at any time.

## 3. Information We Collect

### 3.1 Information you provide

- **Account and profile data** (synced accounts only): first and last
  name, email address, a password (stored only as a secure hash by our
  authentication provider), and an optional profile image you select from
  your photo library.
- **Symptom logs:** the symptom name, a severity rating (from "Very Mild"
  to "Very Severe"), and the date and time of each entry.
- **Medication information:** medication names, dose details you type
  (for example "25/100 mg — 1 tablet"), scheduled days, and medication
  adherence events (whether you marked a scheduled dose as taken).
- **Recovery activity:** your weekly speech and movement goals, and a
  history of completed guided sessions (session type, video title, and
  completion time).
- **Motion coach results** (synced accounts only, optional): when you use
  the camera-guided motion coach while signed in, derived results —
  movement scores, repetition counts, and short pre-written summary
  sentences — are backed up to your account so they survive a new phone.
  You can turn this backup off at any time in Motion coach settings.
  Camera images, video, and body-pose landmarks are **never** part of
  this backup and never leave your device.
- **Community content** (optional feature): posts, comments, likes,
  shares, group memberships, and the display name and profile image shown
  alongside them.

### 3.2 Information created on your device that stays on your device

- **Practice recordings:** you may record a short video of yourself (up
  to three minutes, using the camera and microphone) to compare your form
  against a guided exercise. These recordings are stored only on your
  device and are **never uploaded** to ParkiWell's servers or any third
  party. Deleting the app deletes them.
- **Camera frames and body-pose landmarks:** the motion coach analyzes
  camera frames on your device with an on-device pose model. Frames and
  the body landmark points computed from them are processed in memory and
  are never uploaded anywhere.
- **On-device insights:** trends, streaks, weekly progress, and pattern
  summaries (for example, comparisons of logged severity across therapy
  days) are computed locally from your own records.
- **Local diagnostic logs:** the app writes routine diagnostic messages
  (such as sync status) to device-local logs to aid troubleshooting. They
  are not transmitted to a remote crash-reporting or analytics service.

### 3.3 Information collected automatically

- **Sync metadata** (synced accounts only): record identifiers,
  timestamps, and version counters needed to reconcile offline changes
  with the cloud copy of your data.
- **Connectivity state:** the app checks whether your device is online to
  decide when to sync. This check stays on the device.
- **App version:** displayed in Settings and attached to support requests
  you choose to send.

### 3.4 Information from third-party sign-in

If you choose "Continue with Google," Google shares with us the basic
profile of the Google account you select: your name, email address, and
profile image reference. We use it only to create and identify your ParkiWell
account. We never receive your Google password. Google's handling of your
data is governed by Google's own privacy policy.

### 3.5 Information we do NOT collect

- No precise or approximate location data.
- No contacts, calendars, files, or browsing history.
- No advertising identifiers (IDFA/AAID) and no cross-app tracking.
- No biometric identifiers.
- No data from Apple HealthKit, Google Health Connect, or any wearable.
- No background audio or background recording of any kind.

## 4. How We Use Information

We use the information above only to:

1. Provide app functionality: recording, schedules, reminders shown
   in-app, charts, streaks, and progress views.
2. Sync your records across your devices when you use a synced account,
   including replaying changes you made while offline.
3. Authenticate you, verify your email address, and process password
   resets.
4. Operate the optional community feature and moderate it for safety.
5. Compute on-device insights from your own records.
6. Respond to support and privacy requests you send us.
7. Maintain the security and integrity of the service, and comply with
   legal obligations.

We do **not** use your information for advertising, profiling for
marketing, automated decisions with legal effects, or model training.

## 5. Legal Bases for Processing (EEA/UK users)

Where the GDPR or UK GDPR applies, we rely on:

- **Performance of a contract** (Art. 6(1)(b)): storing and syncing the
  records you create is the core service you request.
- **Consent** (Art. 6(1)(a)) and, for health-related records you choose
  to enter, **explicit consent** (Art. 9(2)(a)): you decide what health
  information to record, and creating a synced account is your explicit
  choice to have it processed in the cloud. You can withdraw consent at
  any time by deleting the relevant records or your account.
- **Legitimate interests** (Art. 6(1)(f)): keeping the service secure,
  preventing abuse of community areas, and defending legal claims.
- **Legal obligation** (Art. 6(1)(c)): where disclosure or retention is
  required by law.

## 6. Where Your Data Is Stored

ParkiWell supports two storage modes:

1. **Local-only mode (default before sign-in).** All records are stored
   in the app's private, sandboxed on-device storage. Nothing is
   transmitted to ParkiWell's servers.
2. **Cloud sync mode (optional).** When you use a synced account, your
   records are also stored in a PostgreSQL database operated on Supabase
   infrastructure. Protections include:
   - encryption in transit (HTTPS/TLS) for every request;
   - encryption at rest on the database infrastructure;
   - row-level security policies so each authenticated account can read
     and write only its own records;
   - authentication tokens scoped to your session.

Changes made offline are queued on your device and replayed to the cloud
with idempotent, versioned writes when connectivity returns, so records
are not duplicated or silently overwritten.

## 7. How Information Is Shared

We do not sell personal data and do not share personal data with data
brokers or advertisers. Information is disclosed only to:

- **Service providers (processors).**
  - *Supabase* — hosts authentication and the synced database described
    above, processing data solely on our instructions.
  - *Google* — only if you choose Google sign-in, to authenticate you.
- **Other users**, only for the optional community feature: posts,
  comments, likes, and your display name and profile image are visible to
  other users where community is enabled. Your symptom logs, medications,
  recovery history, and practice recordings are **never** visible to
  other users.
- **Video platforms.** Recovery videos are embedded from YouTube. When a
  video loads or plays, YouTube (Google) may collect data under its own
  privacy policy, as with any embedded YouTube player. ParkiWell does not
  send your health records to YouTube.
- **Legal requirements.** We may disclose information if required by law,
  subpoena, or court order, or to protect the rights, safety, or property
  of users or the public.
- **Business transfers.** If ParkiWell is involved in a merger, acquisition,
  or asset sale, data may transfer to the successor subject to this
  policy; we will notify you of any material change in ownership or use.

## 8. Community Content

The community feature is optional and requires a synced account. Content
you post (posts, comments, likes) is visible to other users together with
your display name and profile image. Please do not post information you
want to keep private — including health details, addresses, phone
numbers, or anything identifying another person without their permission.
Community content may be moderated, and unsafe or abusive content may be
removed. You can delete your own posts and comments at any time.

## 9. Data Retention

- **Synced records** are kept while your account exists. When you delete
  your account in the app, your account record and associated synced data
  (symptom logs, medication schedules, adherence events, recovery
  sessions, community activity) are deleted from the active database.
  Residual copies in encrypted infrastructure backups expire on the
  backup provider's rotation schedule (typically within 30 days).
- **Local data** stays on your device until you delete your account in
  the app or uninstall the app.
- **Practice recordings** exist only on your device; uninstalling the app
  removes them.
- **Support correspondence** is retained as long as needed to resolve the
  request and to meet legal obligations.

## 10. Your Rights and Controls

### 10.1 Controls inside the app

- Edit your profile (name, image) at any time.
- Add, edit, and delete individual symptom logs, medication schedules,
  posts, and comments.
- Delete your account and associated synced records: Profile → Settings →
  Delete account.
- Use the app entirely offline in local-only mode.
- Deny camera, microphone, or photo permissions — the related optional
  features are disabled, and the rest of the app keeps working.

### 10.2 Rights for EEA/UK users (GDPR)

You have the right to access, rectify, and erase your personal data; to
restrict or object to processing; to data portability; to withdraw
consent at any time without affecting prior processing; and to lodge a
complaint with your supervisory authority. Contact us at
**jcscen@gmail.com** to exercise rights not already available
in-app. We respond within one month.

### 10.3 Rights for California users (CCPA/CPRA)

California residents have the right to know what personal information we
collect, use, and disclose; to delete personal information; to correct
inaccurate information; and to non-discrimination for exercising these
rights. We do not "sell" or "share" personal information as those terms
are defined in the CCPA/CPRA, and we do not use or disclose sensitive
personal information for purposes other than providing the service you
request. Submit requests to **jcscen@gmail.com**; we will verify
your request using your account email.

### 10.4 Other US state privacy laws

Residents of states with comprehensive privacy laws (including Virginia,
Colorado, Connecticut, and Utah) have similar rights of access,
correction, deletion, and portability, and the right to appeal a refusal.
Use the same contact address; appeals are reviewed by a person not
involved in the original decision.

## 11. International Data Transfers

Synced data is hosted in the region of our database provider
(the United States). If you use ParkiWell from another
region, your synced data is transferred to and processed in that hosting
region. Where required, transfers from the EEA/UK rely on adequacy
decisions or standard contractual clauses maintained by our processors.

## 12. Security

We take measures appropriate to the sensitivity of health-related data:

- TLS encryption for all data in transit; encryption at rest for the
  synced database.
- Row-level security so each account can only touch its own records.
- Passwords handled exclusively by the authentication provider as salted
  hashes; ParkiWell never stores plaintext passwords.
- Email verification for new accounts and secure, expiring password-reset
  links.
- The app's local data lives in the OS-sandboxed app container.
- Public repository checks that prevent credentials or signing material
  from being published with the source code.

No method of transmission or storage is 100% secure. If we learn of a
breach affecting your personal data, we will notify you and the relevant
authorities as required by applicable law without undue delay.

## 13. Children's Privacy

ParkiWell is not directed to children and is not intended for anyone under
the age of 13 (or the higher minimum age required in your jurisdiction,
such as 16 in parts of the EEA). We do not knowingly collect personal
data from children. If you believe a child has provided personal data,
contact **jcscen@gmail.com** and we will delete it.

## 14. Health Information Notice

Records you keep in ParkiWell are personal notes you create for yourself.
ParkiWell is **not** a covered entity or business associate under HIPAA, and
the information you store in ParkiWell is not a medical record held by a
healthcare provider. ParkiWell provides organizational and educational
features only; it does not provide medical advice, diagnosis, or
treatment. Always consult your care team about your health, and never
disregard professional advice because of something recorded or displayed
in the app.

## 15. Device Permissions

| Permission | Used for | Required? |
| --- | --- | --- |
| Camera | Recording short practice videos (kept on-device) and taking profile photos | Optional |
| Microphone | Audio in practice videos you record | Optional |
| Photo library | Choosing a profile picture | Optional |
| Network | Optional account sync, community, and embedded videos | Optional (app works offline) |

Denying any permission disables only the related feature.

## 16. Third-Party Links and Content

Recovery videos are embedded from YouTube and remain the property of
their creators; attribution is shown with each video. Opening a video in
the YouTube app or website, or following any external link, takes you to
a service governed by its own terms and privacy policy, which we
encourage you to review.

## 17. Changes to This Policy

We may update this policy as the app evolves. Material changes will be
announced in the app and reflected in the "Last Updated" date above, and
where required by law we will seek renewed consent. Continued use of the
app after an update means the revised policy applies.

## 18. Contact Us

Privacy questions or requests: **<jcscen@gmail.com>**

We aim to acknowledge every privacy request within 7 days and resolve it
within the timelines required by applicable law.
