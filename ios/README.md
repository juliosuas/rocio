# Rocío iOS 1.0

Cliente nativo SwiftUI de Rocío. No es un WebView ni una envoltura del demo web.

## Estado de esta versión

- `MARKETING_VERSION = 1.0`
- `CURRENT_PROJECT_VERSION = 1`
- Deployment target iOS 17.0 y Swift 5.
- 115/115 pruebas pasan en iPhone 17 con iOS 26.3.1.
- Debug y Release unsigned compilan con Xcode 26.3.
- Una build de desarrollo Personal Team abre en iPhone físico.
- TestFlight sigue bloqueado por la membresía pagada, `DEVELOPMENT_TEAM` y los smokes externos pendientes.

## Superficie nativa

- Catalog, Garden, Calendar, Scanner y Settings en SwiftUI.
- Catálogo bilingüe de 15 flores con fotografía local atribuida.
- Cuenta Supabase, sesión en Keychain y jardín sincronizado por usuario con caché local.
- Primer flujo completo: agregar planta, volver al jardín, activar recordatorio y confirmar riego.
- Notificaciones locales solicitadas únicamente después del toque de la persona.
- Scanner experimental con reducción de imagen fuera del hilo principal, consentimiento por foto, opción local y fallback honesto.
- Recuperación de contraseña PKCE con verifier en Keychain, URLs sin bearer tokens y manejo de carreras entre escenas.
- App Intents para abrir el jardín, abrir scanner y registrar riego.
- Exportación, limpieza local, borrado cloud, opt-out de analítica, sign out y eliminación permanente de cuenta.
- Modo demo aislado bajo `#if DEBUG`; no existe en Release.

## Requisitos

- Xcode 26.3 completo.
- Un runtime de iOS Simulator compatible.
- macOS compatible con Xcode 26.3.
- Para nube: URL pública y publishable key del proyecto Supabase.

Selecciona Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## Configuración pública de Supabase por Mac

```sh
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
```

Agrega a `Local.xcconfig` únicamente la `sb_publishable_...` de Supabase. El archivo está ignorado por Git y alimenta Debug y Release.

Nunca agregues al cliente:

- `sb_secret_...`
- JWT con rol `service_role`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PLANT_ID_API_KEY`

Un Debug sin key muestra **Explorar demo local**. Una build Release firmada falla temprano si falta la configuración pública, para impedir subir un binario cloud incompleto.

## Build

Desde la raíz del repositorio:

```sh
xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Release unsigned:

```sh
xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Pruebas

```sh
xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

La suite cubre autenticación, PKCE, rotación de refresh tokens, aislamiento de cuentas, sync/epoch/tombstones, primer cuidado, notificaciones, scanner, reducción de imágenes, rutas y persistencia.

Los gates adicionales se ejecutan desde la raíz:

```sh
node qa/release-gate.mjs
node qa/cloud-ai-security-audit.mjs
node qa/ios-app-store-readiness-audit.mjs
```

## Comportamiento offline y de errores

- Una sesión válida y el jardín local aparecen sin esperar el handshake cloud.
- Cambios pendientes se conservan y reintentan; la UI no afirma sincronización hasta confirmación remota.
- Un logout, cambio de cuenta o recuperación invalida tareas anteriores antes de que puedan publicar estado viejo.
- Plantas eliminadas se representan con tombstones para no reaparecer desde otro dispositivo.
- Si Plant.id o Supabase fallan, el scanner vuelve al matcher local y mantiene visible la incertidumbre.

## Demo Debug sin Supabase

Pulsa **Explorar demo local**. El modo demo:

- crea tres plantas efímeras;
- permite recorrer Garden, Calendar y Scanner;
- nunca sube fotos ni ejecuta analítica cloud;
- no escribe sobre el jardín de una cuenta;
- restaura los datos previos al salir desde Settings.

## Antes de TestFlight

1. Activar Apple Developer Program y configurar `DEVELOPMENT_TEAM`.
2. Confirmar bundle id `com.juliosuas.rocio` en Apple Developer y App Store Connect.
3. Verificar que la build Release firmada contiene la publishable key correcta.
4. Integrar el cliente antes de desplegar la migración de tombstones.
5. Allowlistar `com.juliosuas.rocio://auth/recovery`, configurar Site URL HTTPS y SMTP.
6. Probar recuperación real por correo y sincronización con dos sesiones.
7. Ejecutar cámara, selector de fotos y notificaciones en iPhone físico.
8. Archivar desde Xcode Organizer, subir a TestFlight y capturar screenshots finales.

Consulta [`../APP_STORE_RELEASE_CHECKLIST.md`](../APP_STORE_RELEASE_CHECKLIST.md) para el gate completo y [`../DESIGN.md`](../DESIGN.md) para las reglas visuales.
