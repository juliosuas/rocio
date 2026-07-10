# Rocio App Store Metadata

Date: 2026-07-09

## English (Primary)

Name: Rocio

Subtitle: Flower care, made gentle

Promotional text:
Build a synced flower garden with clear care guides, simple watering reminders, and an honest AI-assisted scanner.

Description:
Rocio helps you care for flowers without turning gardening into another complicated task. Save flowers to My Garden, sync care across devices, see when watering is due, explore practical guides, and use an experimental AI-assisted scanner that shows possible matches with visible uncertainty.

The free v1 is designed to be useful and private:

- Native onboarding and a focused 15-flower catalog.
- A secure account that syncs your garden across devices.
- Watering reminders enabled only when you choose.
- A weekly care calendar and simple watering status.
- Five cloud AI scans per month with candidates, confidence guidance, and an on-device fallback.
- Data export, cloud deletion, and permanent in-app account deletion.
- Siri and Shortcuts actions for your garden, watering, and scanner.

Rocio does not promise perfect identification or professional diagnosis. Always verify the care guide before acting.

Keywords: flowers,plants,garden,watering,flower care,plant care,identify flowers,reminders

## Español

Nombre: Rocio

Subtítulo: Cuidado simple de flores

Texto promocional:
Crea un jardín sincronizado con fichas claras, recordatorios simples y un scanner experimental con IA.

Descripción:
Rocio te ayuda a cuidar flores sin convertir la jardinería en otra tarea complicada. Guarda flores en Mi Jardín, sincroniza el cuidado entre dispositivos, revisa cuándo toca regar y usa un scanner experimental con IA que muestra posibles coincidencias con incertidumbre visible.

La v1 gratuita está pensada para ser útil y privada:

- Onboarding nativo y un catálogo enfocado en 15 flores.
- Cuenta segura y jardín sincronizado entre dispositivos.
- Recordatorios de riego activados solo cuando tú decides.
- Calendario semanal y estado de riego simple.
- Cinco escaneos con IA al mes, candidatos, guía de confianza y fallback local.
- Exportación, borrado en la nube y eliminación permanente de cuenta.
- Acciones de Siri y Atajos para jardín, riego y scanner.

Rocio no promete identificación perfecta ni diagnóstico profesional. Verifica siempre la ficha antes de actuar.

Palabras clave: flores,plantas,jardín,riego,cuidado de flores,macetas,identificar,recordatorios

## Category

Primary: Lifestyle

Secondary: Education

## Review Notes

Rocio is a bilingual English/Spanish native flower-care app and follows the user's iOS language. A required email account provides cross-device garden sync, scan quota/history, and in-app account deletion. App Review credentials will be supplied in the review information.

After explicit disclosure and consent, scanner photos are sent through an authenticated Supabase Edge Function to Plant.id. Raw photos are not stored in the Rocio database. The scanner is experimental and falls back to a basic on-device visual match if the provider is unavailable. Limited first-party product analytics can be disabled in Settings. Rocio has no advertising or cross-app tracking.

Notification permission is requested only in Settings after the user taps Enable Watering Reminders. Settings also provides data export and a destructive delete action that clears the garden and cancels pending reminders.

## Screenshots To Capture

1. Catalog: real flower photos and practical filters.
2. My Garden: saved plants, summary, and watering status.
3. Calendar: weekly watering schedule.
4. Scanner: experimental candidates, confidence band, and disclaimer.
5. Settings: reminders, privacy, export, delete, privacy policy, and support.

Capture the primary English set first. Capture a Spanish localized set only after the English screenshots pass the visual release checklist.

## URLs

- Landing: `https://rocio-flower-care.lovable.app`
- Interactive demo: `https://juliosuas.github.io/rocio/index.html?demo=1`
- Privacy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`

## Monetization

The initial release remains free and includes five AI scans per month. The backend recognizes a future Pro entitlement, but no paid unlock may ship until StoreKit products, receipt/transaction verification, restore purchases, metadata, and tests are complete.
