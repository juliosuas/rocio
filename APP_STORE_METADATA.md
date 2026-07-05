# Rocio App Store Metadata Draft

Date: 2026-07-05

## Product Page

Name: Rocio

Subtitle:
Cuida tus flores en español

Promotional text:
Rocio te ayuda a cuidar tu jardín de flores con onboarding simple, recordatorios locales, fichas claras y un scanner experimental honesto.

Description:
Rocio es una app de cuidado de flores pensada en español desde el inicio. Guarda tus flores en Mi Jardín, revisa cuándo toca regar, consulta fichas de cuidado y usa un scanner experimental que compara fotos localmente con el catálogo.

La v1 está diseñada para ser simple y privada:

- Onboarding nativo para empezar sin fricción.
- Jardín guardado localmente en tu iPhone.
- Recordatorios de riego activados por ti.
- Catálogo filtrable de flores comunes con cuidados prácticos.
- Scanner local con candidatos e incertidumbre visible.
- Exportación y borrado de datos locales.
- Atajos de Siri para abrir el jardín, registrar riego y abrir el scanner.

Rocio no promete identificación perfecta ni diagnóstico profesional. El scanner es una ayuda experimental; verifica siempre la ficha de cuidado y usa tu criterio antes de actuar.

## Keywords

flores, plantas, jardin, riego, cuidado de plantas, identificar flores, macetas, jardineria, recordatorios

## Category

Primary: Lifestyle
Secondary: Education

## Review Notes

Rocio is a Spanish-first flower-care app. The native iOS app stores the user's garden locally on the device, schedules local watering reminders after user opt-in, and offers an experimental local flower identification helper using camera or photo input.

No Plant.id or Supabase provider calls are enabled in the current native iOS release. Camera and selected photo input are analyzed locally on the device and are not uploaded or saved by the app.

Notification permission is requested only from Settings when the user taps the watering reminder action. The app has no account system, analytics, tracking, or backend dependency in this release.

## Screenshots To Capture

1. Catalogo: flower catalog with real images.
2. Mi Jardin: saved plants, garden summary, and watering status.
3. Calendario: weekly watering schedule.
4. Scanner: experimental local candidates, confidence band, and uncertainty copy.
5. Ajustes: reminders, privacy, export/delete local data.

## URLs

Production URLs:

- Landing: `https://juliosuas.github.io/rocio/launch.html`
- Privacy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`

Local demo:

- Landing: `http://localhost:3002/launch.html`
- Privacy: `http://localhost:3002/privacy.html`
- Support: `http://localhost:3002/support.html`

## Monetization Position

v1 is free for App Review. Recommended v1.1 pricing after acceptance is Rocio Pro one-time unlock at US$14.99, or US$19.99/year only if recurring seasonal/weather/catalog value is added through StoreKit.

## Internal Benchmark

Primary internal benchmark is Planta for care habit, reminders, onboarding, and subscription framing. PictureThis and Plantum are secondary references for scanner/ASO/pricing. Do not mention competitor names in App Store metadata.
