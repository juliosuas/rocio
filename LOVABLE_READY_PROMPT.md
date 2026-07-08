# Rocío — Lovable Ready Prompt

Build a polished mobile-first plant care app named Rocío for Spanish-speaking flower owners.

Core experience:
- Catalog of 15 supported flowers with care cards, real local image assets, watering cadence, light, soil, season, companions, and warnings.
- My Garden: add/remove plants, water tracking, notes, status, urgency, weekly calendar, and local persistence.
- Scanner: camera/file upload flow that clearly says the current local classifier is an honest fallback, not real botanical recognition. Show confidence, uncertainty, top candidates, and a prompt to retake photos with natural light and a centered flower.
- Plant Doctor: symptoms, pests, and remedies must display as PENDING botanical verification. Do not present disease or treatment content as verified medical/agronomic advice.
- App Store readiness: include privacy/support screens based on the local `privacy.html` and `support.html` drafts, Spanish metadata tone, offline-friendly UX, iOS-safe camera/photo/notification permission language, and mobile layouts that feel native rather than like a generic web wrapper.

Hard constraints:
- Do not publish, submit to App Store, or connect production credentials.
- Do not invent botanical claims. Mark unverified disease/treatment guidance as PENDING.
- Plant.id/Supabase integration is BLOCKED until a secure Supabase Edge Function deploy and `PLANT_ID_API_KEY` secret are available.
- Catalog photos have local source/license attribution rows and pass the local App Store photo asset audit; keep attribution visible and do not introduce new unaudited assets.
- Privacy/support drafts are local only until Julio authorizes publication and a public support URL.

Design direction:
- Quiet App Store-grade mobile UI, high contrast, dense but readable cards, 8px-radius controls, obvious scanner fallback state, and no marketing-style landing page before the app experience.
