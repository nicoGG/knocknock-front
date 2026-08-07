# nocknock

NockNock collaborative post-it reminders and tasks.

## Notificaciones push

La app usa Firebase Cloud Messaging y registra una instalación independiente
por dispositivo contra `POST /api/notifications/devices`. El token se vuelve a
enviar al iniciar sesión, al volver al primer plano y cada vez que Firebase lo
rota. Al cerrar sesión se desvincula la instalación antes de eliminar el token.

Android declara el permiso de notificaciones y el canal
`nocknock_notifications`. iOS incluye las capacidades Push Notifications y
Remote notifications. Para distribuir en iPhone, la credencial APNs del bundle
`cl.nocknock.app` también debe estar cargada en Firebase Console.

La campana del tablero abre la bandeja persistente, permite marcar avisos como
leídos y navega a la lista o nota indicada por el backend.

## Analytics y Crashlytics

Firebase Analytics registra navegación, inicio/cierre de sesión, apertura de
notificaciones y eventos automáticos. Crashlytics captura errores fatales y las
fallas inesperadas del API. Ambos se habilitan en builds release; para probarlos
en debug usa `--dart-define=ENABLE_FIREBASE_TELEMETRY=true` y reinstala la app
completamente después de agregar o actualizar plugins nativos.

El proyecto `nocknock-d8fe9` debe tener Google Analytics habilitado en
**Firebase Console → Configuración del proyecto → Integraciones**. Después de
habilitarlo, vuelve a ejecutar `flutterfire configure` para descargar los
archivos Android/iOS actualizados antes de generar el release.

Cada request lleva un `X-Request-Id`, Firebase App Instance ID, sesión y versión
de la app. El backend devuelve el mismo request ID y puede asociar sus eventos
confirmados con la sesión móvil. La telemetría sanitiza las rutas y nunca envía
títulos, contenido de notas, nombres de listas, correos ni tokens.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firma de releases Android

Los APK y AAB de release se firman con un keystore de subida propio. La
configuracion sensible queda fuera de Git.

1. Genera la clave de subida (solo una vez):

   ```sh
   keytool -genkeypair -v \
     -keystore android/app/nocknock-upload.jks \
     -alias nocknock-upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Copia `android/key.properties.example` como `android/key.properties` y
   reemplaza las contrasenas. `storeFile` debe seguir apuntando a
   `app/nocknock-upload.jks`.

3. Genera el artefacto:

   ```sh
   flutter build appbundle --release
   # o, para APK:
   flutter build apk --release
   ```

Antes de publicar, guarda una copia segura de `nocknock-upload.jks`, su alias y
sus contrasenas. Si se pierde la clave de subida, no se podran firmar nuevas
versiones con ella sin iniciar el proceso de reemplazo de clave en Google Play.

## Publicacion automatica en Google Play

Cada push a la rama `release` (incluido un merge) ejecuta
`.github/workflows/release-google-play.yml`. El workflow analiza y prueba la
app, genera un AAB firmado y lo publica como version completada en **Pruebas
internas** de Google Play. Tambien se puede ejecutar manualmente desde GitHub
Actions.

El `versionName` se toma de `pubspec.yaml`. El `versionCode` se calcula con el
numero y el intento de la ejecucion de GitHub Actions, por lo que cada entrega
puede subirse a Play sin reutilizar el codigo de una version anterior.

Configura estos secretos en el repositorio de GitHub antes del primer merge a
`release`:

- `ANDROID_KEYSTORE_BASE64`: contenido del keystore de subida codificado en
  base64.
- `ANDROID_KEYSTORE_PASSWORD`: contrasena del keystore.
- `ANDROID_KEY_ALIAS`: alias de la clave; por defecto,
  `nocknock-upload`.
- `ANDROID_KEY_PASSWORD`: contrasena de la clave.
- `PLAY_SERVICE_ACCOUNT_JSON`: JSON completo de una cuenta de servicio con
  permiso para publicar NockNock en Play Console.
