# Rocío — plan de ataque App Store/TestFlight (2026-05-11)

## Objetivo
Convertir Rocío de web MVP a app iOS funcional, instalable por TestFlight mañana y lista para someter a App Store en 24–48h si la cuenta Apple queda activa.

## Decisión de licencia
- **OWNER ACTION ONLY:** Comprar **Apple Developer Program Individual** si Julio autoriza. La automatización/cron no debe comprar, someter ni publicar.
- Costo esperado: **$99 USD/año**.
- Evitar Organization mañana salvo que ya exista D-U-N-S y verificación lista; puede retrasar.

## Día 1 — Mañana: TestFlight first

### 1. Cuenta Apple / App Store Connect
- [ ] Julio compra Apple Developer Program si decide avanzar.
- [ ] Aceptar agreements pendientes.
- [ ] Crear app en App Store Connect.
- [ ] Bundle ID sugerido: `com.juliosuas.rocio`.
- [ ] Nombre: `Rocío` o `Rocío — Cuida tus Flores`.
- [ ] Categoría: Lifestyle / Utilities / Education (decidir en metadata).

### 2. Wrapper iOS
- [ ] Crear proyecto Capacitor alrededor del HTML existente.
- [ ] Migrar `index.html`, `assets`, `manifest`, `sw.js` a build web estático.
- [ ] Instalar plugins mínimos:
  - Camera / Photos si aplica.
  - Local Notifications.
  - Preferences/storage si queremos migrar de localStorage luego.
- [ ] Generar Xcode workspace.
- [ ] Configurar signing con Apple Developer account.

### 3. Permisos iOS
Agregar textos humanos en `Info.plist`:
- Cámara: identificar flores con foto.
- Fotos: subir una imagen de la flor.
- Notificaciones: recordatorios de riego.

### 4. Privacidad/legal mínimo viable
- [x] Crear borrador local `privacy.html`; PENDING publicar URL y revisión final antes de App Store.
- [x] Crear borrador local `support.html`; PENDING publicar URL/canal autorizado antes de App Store.
- [ ] Declarar datos: fotos enviadas a Supabase/Plant.id para identificación; jardín guardado localmente; sin cuentas en v1.
- [ ] Revisar atribución de imágenes (`PHOTO_ATTRIBUTIONS.md`).

### 5. Assets App Store
- [ ] Icono 1024x1024 PNG.
- [ ] Iconos iOS generados.
- [ ] Splash simple.
- [ ] 5 screenshots iPhone: Home, Catálogo, Jardín, Scanner, Doctor/Calendario.
- [x] Resolver atribuciones PENDING en `PHOTO_ATTRIBUTIONS.md` antes de usar screenshots/metadata con esos assets.

### 6. Build/TestFlight
- [ ] Probar app en simulator/iPhone.
- [ ] Verificar scanner, jardín, calendario, dark mode.
- [ ] Archive en Xcode.
- [ ] Upload a App Store Connect.
- [ ] TestFlight internal testing.

## Día 2 — App Store submission
- [ ] Resolver warnings de App Store Connect.
- [ ] Completar App Privacy Nutrition Labels.
- [ ] Metadata en español + screenshots.
- [ ] Confirmar Plant.id/Supabase production secret.
- [ ] Agregar rate limit básico a Edge Function si da tiempo.
- [ ] Submit review.

## No meter en v1
- Cuentas/login.
- Sync multi-dispositivo.
- Family sharing.
- Web push/backend scheduler.
- Weather API.

## Riesgos
- Apple Developer enrollment puede tardar si hay verificación extra.
- Primera revisión puede tardar 24–48h+.
- App web-wrapper puede ser rechazada si se siente demasiado web; mitigación: permisos nativos, iconos, offline/UX pulida, notificaciones locales y metadata clara.
- Plant.id plan/API debe permitir producción/comercial.
- No vender el scanner como reconocimiento real hasta restaurar Supabase/Plant.id con secreto seguro y QA con fotos reales.
- Enfermedades/tratamientos siguen PENDING hasta auditoría botánica con fuentes confiables.
- Fotos del catálogo pasan el gate local de presencia, atribución, licencia no-PENDING y resolución mínima; revalidar antes de screenshots finales.

## Definición de “funcional v1”
- Instala como app iOS.
- Abre rápido y sin errores JS.
- Permite catálogo + jardín + riego + calendario.
- Scanner funciona o falla con mensaje honesto.
- Notificaciones locales configurables.
- Privacidad/soporte publicados.
