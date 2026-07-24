# Rocio App Store Privacy Answers Draft

Date: 2026-07-23

This draft describes the cloud-enabled native iOS build. Reconfirm it against the deployed Supabase project and Plant.id agreement before submission.

## Data Flow

- Account: email address and Supabase user ID are stored for authentication and account management.
- Locale: the app language is sent during account creation and persisted in the account profile so Rocio can provide localized app functionality.
- Garden: each saved plant's source identity, common and scientific names when available, nickname, notes, optional care preferences, care status, and watering dates are cached on-device and synced to the user's Supabase account.
- Scanner: for every selected photo, Rocio asks whether to analyze only on the iPhone or send a compressed copy through an authenticated Supabase Edge Function to Plant.id/Kindwise. Cloud transfer occurs only after consent for that photo. Rocio does not persist the raw image in its database. To resume an interrupted paid scan without sending it twice, the device temporarily stores an account-scoped mapping containing a SHA-256 fingerprint of the compressed image, a random request UUID, and an expiry; it stores no photo bytes. The mapping can be reused for up to five minutes. It is removed immediately after a terminal result, sign-out, or account deletion, while stale entries are removed on the next app launch or scan. Plant.id processes the submitted copy under the applicable provider agreement.
- Scan records: Rocio stores provider name, top scientific name, confidence, candidate count, quota use, and timestamp. To make network retries safe, Rocio also keeps a bounded normalized identification response (maximum 128 KiB) with a seven-day replay window. Expired replay rows are removed on that account's next cloud scan or when the account is deleted; if neither happens, the expired bounded row can remain stored but is no longer replayed. The replay record contains no raw photo and no Plant.id access token.
- Analytics: when enabled, Rocio stores limited product interaction events linked to the account. No advertising ID, precise location, contacts, photo content, or cross-app tracking is used.
- Notifications: watering reminders are local and opt-in.
- Deletion: Settings includes permanent in-app account deletion. Database rows cascade when the Supabase auth user is deleted.

## App Privacy Labels

### Data Used To Track The User

No. Rocio does not combine data with third-party data for advertising, share data with data brokers, or track users across other companies' apps and websites.

### Data Linked To The User

- Contact Info > Email Address: app functionality and account management.
- Identifiers > User ID: app functionality and analytics.
- User Content > Other User Content: synced garden, notes, care status, and watering history; app functionality.
- User Content > Photos or Videos: plant photo sent for identification after consent; app functionality.
- Usage Data > Product Interaction: authenticated scan usage enforces the account quota; first-party product improvement analytics are stored when enabled. App functionality and analytics.
- Other Data > Other Data Types: app locale sent during account creation and persisted in the account profile; app functionality.

### Data Not Linked To The User

None currently declared. The backend rows above use the authenticated user ID and should be treated as linked.

### Tracking

`NSPrivacyTracking` remains `false`. No tracking domains are declared.

## Permission Explanations

Camera and selected photos are used only after a scanner action. For each photo, the app offers an on-device analysis or states that a compressed copy will be sent to Plant.id through Rocio Cloud and requires consent for that transfer. If cloud identification fails, the app can show a lower-quality on-device fallback.

Notification permission is requested only after an explicit tap in the first-care Garden card or in Settings. Reminders are generated locally from the user's garden.

When the user deletes local data in Settings, Rocio also cancels pending local watering reminders.

## Review Notes Draft

Rocio is a bilingual plant-care app with a required account because the account provides cross-device garden sync, scan history/quota enforcement, and account deletion. Provide App Review with a working demo account.

The scanner is assistive and experimental. After per-photo disclosure and consent, a selected photo can be sent through an authenticated Supabase Edge Function to Plant.id; the user can instead keep each analysis on-device. The Plant.id API key is server-side, requests require a valid Rocio JWT, and raw photos are not stored in the Rocio database. A bounded normalized result has a seven-day replay window solely to make network retries safe; it excludes the raw photo and provider access token. An expired row is removed on the account's next cloud scan or account deletion and can otherwise remain stored but unavailable for replay. A basic on-device visual matcher is used when selected or when the provider is unavailable. Rocio does not claim professional botanical, agricultural, medical, or veterinary accuracy.

Settings provides analytics opt-out, data export, local/cloud garden deletion, sign out, and permanent account deletion.

## Production URLs

- Privacy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`

## Blocking Verification

- After backup and linked dry-run review, apply `20260721000100_preserve_garden_deletions.sql`, `20260722000100_support_arbitrary_plants.sql`, and `20260723000100_idempotent_scan_requests.sql` in that order, then deploy and verify the matching authenticated Edge Function.
- Set `PLANT_ID_API_KEY`; never put it in the app, browser, CI logs, or repository.
- Add the production Supabase anonymous key through release configuration.
- Confirm Plant.id image retention/deletion terms and update the public policy with the final contractual behavior.
- Create an App Review demo account and test in-app account deletion.
- Reconfirm App Privacy labels after StoreKit or crash reporting is added.
