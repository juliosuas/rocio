# Rocio App Store Metadata

Date: 2026-07-09

## English (Primary)

Name: Rocio

Subtitle: Flower care, made gentle

Promotional text:
Build a private flower garden with clear care guides, local watering reminders, and an honest experimental scanner.

Description:
Rocio helps you care for flowers without turning gardening into another complicated task. Save flowers to My Garden, see when watering is due, explore practical care guides, and use an experimental on-device scanner that shows possible matches with visible uncertainty.

The free v1 is designed to be useful and private:

- Native onboarding and a focused 15-flower catalog.
- A private garden stored locally on your iPhone.
- Watering reminders enabled only when you choose.
- A weekly care calendar and simple watering status.
- An experimental scanner with candidates and confidence guidance.
- Local data export and deletion.
- Siri and Shortcuts actions for your garden, watering, and scanner.

Rocio does not promise perfect identification or professional diagnosis. Always verify the care guide before acting.

Keywords: flowers,plants,garden,watering,flower care,plant care,identify flowers,reminders

## Espanol

Nombre: Rocio

Subtitulo: Cuidado simple de flores

Texto promocional:
Crea un jardin privado con fichas claras, recordatorios locales y un scanner experimental honesto.

Descripcion:
Rocio te ayuda a cuidar flores sin convertir la jardineria en otra tarea complicada. Guarda flores en Mi Jardin, revisa cuando toca regar, consulta fichas practicas y usa un scanner experimental que muestra posibles coincidencias con incertidumbre visible.

La v1 gratuita esta pensada para ser util y privada:

- Onboarding nativo y un catalogo enfocado en 15 flores.
- Jardin privado guardado localmente en tu iPhone.
- Recordatorios de riego activados solo cuando tu decides.
- Calendario semanal y estado de riego simple.
- Scanner experimental con candidatos y guia de confianza.
- Exportacion y borrado de datos locales.
- Acciones de Siri y Atajos para jardin, riego y scanner.

Rocio no promete identificacion perfecta ni diagnostico profesional. Verifica siempre la ficha antes de actuar.

Palabras clave: flores,plantas,jardin,riego,cuidado de flores,macetas,identificar,recordatorios

## Category

Primary: Lifestyle

Secondary: Education

## Review Notes

Rocio is a bilingual English/Spanish native flower-care app and follows the user's iOS language. The app stores the user's garden locally, schedules local watering reminders after explicit opt-in, and offers an experimental on-device flower matching helper using camera or selected photo input.

No Plant.id or Supabase calls are enabled. Camera and selected photos are analyzed locally and are not uploaded or saved by the app. The app has no account, analytics, tracking, advertising, payment, or backend dependency in this release.

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

v1 is free and contains no StoreKit products. Any future digital unlock must use StoreKit and requires updated metadata, privacy review, and tests before release.
