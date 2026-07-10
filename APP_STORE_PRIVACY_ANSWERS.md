# Rocio App Store Privacy Answers Draft

Date: 2026-07-09

This draft describes the cloud-enabled native iOS build. Reconfirm it against the deployed Supabase project and Plant.id agreement before submission.

## Data Flow

- Account: email address and Supabase user ID are stored for authentication and account management.
- Garden: plants, nicknames, care status, notes, and watering dates are cached on-device and synced to the user's Supabase account.
- Scanner: after a one-time explicit disclosure and consent, Rocio sends a compressed selected photo through an authenticated Supabase Edge Function to Plant.id/Kindwise. Rocio does not persist the raw image in its database. Plant.id processes the image under the applicable provider agreement.
- Scan records: Rocio stores provider name, top scientific name, confidence, candidate count, quota use, and timestamp. It does not store the raw scanner image.
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
- User Content > Photos or Videos: flower photo sent for identification after consent; app functionality.
- Usage Data > Product Interaction: first-party product improvement analytics when enabled.

### Data Not Linked To The User

None currently declared. The backend rows above use the authenticated user ID and should be treated as linked.

### Tracking

`NSPrivacyTracking` remains `false`. No tracking domains are declared.

## Permission Explanations

Camera and selected photos are used only after a scanner action. Before the first cloud scan, the app states that a compressed photo is sent to Plant.id through Rocio Cloud and requires consent. If cloud identification fails, the app can show a lower-quality on-device fallback.

Notification permission is requested only from Settings. Reminders are generated locally from the user's garden.

## Review Notes Draft

Rocio is a bilingual flower-care app with a required account because the account provides cross-device garden sync, scan history/quota enforcement, and account deletion. Provide App Review with a working demo account.

The scanner is assistive and experimental. After explicit disclosure, selected photos are sent through an authenticated Supabase Edge Function to Plant.id. The Plant.id API key is server-side, requests require a valid Rocio JWT, and raw photos are not stored in the Rocio database. A basic on-device visual matcher is used when the provider is unavailable. Rocio does not claim professional botanical, agricultural, medical, or veterinary accuracy.

Settings provides analytics opt-out, data export, local/cloud garden deletion, sign out, and permanent account deletion.

## Production URLs

- Privacy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`

## Blocking Verification

- Deploy the migration and Edge Function to the production Supabase project.
- Set `PLANT_ID_API_KEY`; never put it in the app, browser, CI logs, or repository.
- Add the production Supabase anonymous key through release configuration.
- Confirm Plant.id image retention/deletion terms and update the public policy with the final contractual behavior.
- Create an App Review demo account and test in-app account deletion.
- Reconfirm App Privacy labels after StoreKit or crash reporting is added.
