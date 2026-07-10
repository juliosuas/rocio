# Rocio Lovable Production Contract

Build the public marketing site for Rocio, a global flower care app with bilingual English and Spanish support. English is the default landing locale and a persistent EN/ES control switches all marketing copy. The native iOS app follows the user's device language.

## Product Promise

- A secure account with a locally cached flower garden synchronized through Supabase.
- Practical flower care guides, watering reminders, and a weekly calendar.
- An experimental scanner that sends consented images through an authenticated Supabase Edge Function to Plant.id, shows multiple candidates, and falls back to an on-device visual match.
- Required authentication, optional first-party product analytics with opt-out, no advertising or cross-app tracking, and no payment in the initial release.

## Canonical Proof And Links

- Native app demo video: `https://juliosuas.github.io/rocio/assets/video/rocio-demo.mp4`
- Interactive fallback demo: `https://juliosuas.github.io/rocio/index.html?demo=1`
- Privacy policy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`

The hero must use the native app video as its primary proof. Do not use a dominant editorial flower photo, a duplicate second video, or claims that the current video does not demonstrate.

## Waitlist

Create a real Lovable Cloud waitlist backed by `waitlist_subscribers(id, email unique, locale, consent_version, consent_at, created_at)`. Normalize email, store the active locale and consent version, include a hidden honeypot, handle duplicates idempotently, and show accessible loading, success, duplicate, validation, and server-error states. The form must link to the privacy policy before submission.

## Privacy Boundary

State clearly that the iOS app links an email, user ID, synchronized garden, limited optional product analytics, and consented scanner requests to the user's account. Scanner images are processed by Plant.id through Rocio Cloud and are not stored in Rocio's database. Separately disclose that the public website collects an email address, locale, consent version, and timestamps only when a visitor joins the waitlist.

## Design And Release Requirements

- Warm ecological editorial design: leaf green, flower pink, warm white, and restrained teal accents.
- Responsive at 1440x900, 430x932, and 390x844 with no overflow or clipped text.
- Accessible keyboard navigation, visible focus, semantic headings, reduced-motion support, and labeled controls.
- Public production quality only: no MVP, placeholder, BLOCKED, PENDING, internal checklist, personal email, or owner-only language.
- Canonical production slug: `rocio-flower-care`, falling back to `rocio-flower-care-app` only if unavailable.
