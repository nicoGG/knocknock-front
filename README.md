# nocknock

NockNock collaborative post-it reminders and tasks.

## Web

Firebase incluye la aplicación **NockNock Web** en el proyecto
`nocknock-d8fe9`. Para ejecutar en Chrome:

```sh
fvm flutter run -d chrome --web-port 7357
```

Para generar la versión publicable:

```sh
fvm flutter build web
```

El resultado queda en `build/web`. El inicio de sesión usa el popup de
Firebase Auth con Google; `localhost` está autorizado en Firebase Authentication.
Al publicar en otro dominio, agrégalo en **Authentication → Settings → Authorized
domains**. El servidor debe servir la app mediante HTTPS (localhost permite HTTP).

En web se usa Analytics, pero no Crashlytics ni notificaciones locales/push
nativas. La protección biométrica de listas requiere la app móvil. La bandeja
de notificaciones dentro de la app sigue disponible. El almacenamiento offline
usa las preferencias del navegador en lugar de SQLite.

## Firebase Hosting

La web se publica en https://nocknock-d8fe9.web.app.
Cada push a `main` ejecuta `.github/workflows/deploy-firebase-hosting.yml`:
analiza, prueba, compila Flutter web y despliega únicamente Hosting.
También se puede iniciar desde **Actions → Publicar web en Firebase Hosting →
Run workflow**, seleccionando `main`.

GitHub se autentica por Workload Identity Federation con la cuenta
`github-hosting@nocknock-d8fe9.iam.gserviceaccount.com`, sin claves privadas.
El proveedor está limitado al ID de este repositorio, su propietario, la rama
`main` y este workflow. La cuenta tiene permisos de Firebase Hosting y consumo
de APIs del proyecto.

Para publicar manualmente con una cuenta autorizada:

```sh
fvm flutter build web --release
firebase deploy --only hosting --project nocknock-d8fe9
```

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

## Widgets de inicio (Android y iOS)

La galería del sistema incluye **Mis pendientes** y **Captura rápida**. En
**Configuración → Widgets de inicio** se elige “Hoy” o una lista, el destino de
las capturas y si se oculta el contenido. Los ajustes se guardan por cuenta en
este dispositivo y se aplican a todas las instancias del widget.

- “Hoy” muestra notas atrasadas, con recordatorio para hoy y asignadas al usuario
  sin fecha. Una lista elegida muestra sus notas pendientes. Se comparten como
  máximo cinco títulos; el tamaño del widget determina cuántos caben.
- Tocar una nota abre su vista previa. Nueva nota abre el editor compacto y
  permite cambiar la lista de destino antes de guardar.
- Las listas protegidas con biometría se excluyen incluso si están desbloqueadas
  en la app. También se excluyen listas cuya llave de cifrado sigue pendiente.
  No se comparten cuerpos, adjuntos ni credenciales con el widget. Los títulos
  visibles se guardan en almacenamiento privado del dispositivo para que el
  sistema pueda mostrarlos con la app cerrada.
- En Android y iOS 17 o posterior se pueden marcar tareas no recurrentes desde
  el widget. La acción se conserva en una cola nativa con cuenta, revisión e ID
  de mutación; se entrega al repositorio al abrir o reanudar NockNock. Si falla
  la escritura, permanece en cola. El repositorio mantiene sus mecanismos de
  sincronización offline y conflictos. No se confirma la sincronización remota
  desde el widget. Las tareas recurrentes y iOS 15/16 abren la nota en la app.
- El contenido se actualiza al usar la app y recibir cambios del repositorio.
  La fecha de actualización y las acciones por sincronizar se muestran en el
  widget. No se realiza polling de la API desde la extensión del sistema.

Android usa `AppWidgetProvider` y almacenamiento privado. iOS usa WidgetKit y
el App Group existente `group.cl.nocknock.app`, con el target
`NockNockWidgets` embebido en Runner. El target hereda la versión de Flutter
mediante `Widgets.xcconfig`, sin enlazar los plugins de Runner. Para distribuir
se necesita un perfil de firma para `cl.nocknock.app.NockNockWidgets` con ese
App Group habilitado.

## Listas financieras

Al crear una lista puedes elegir **Normal**, **Gastos**, **Cotizaciones**,
**Cuentas por cobrar** o **Financiera personalizada**. Esta última permite dar
nombre al tipo y reutilizar los nombres personalizados de tus listas accesibles.
Las listas existentes conservan el tipo Normal y su interfaz habitual.

Las listas financieras muestran un formulario de concepto, monto, moneda,
persona/proveedor, fecha y estado, con boletas, capturas y PDF usando los adjuntos
existentes (hasta dos archivos). CLP usa pesos enteros; USD y EUR, dos decimales.
Los montos se guardan como unidades enteras, independientemente del título.
Los estados distinguen por pagar/pagado, por cobrar/cobrado o cotización
pendiente/aceptada/descartada. Se incluyen iconos por tipo y moneda, las
superficies de vidrio del resto de la app, búsqueda y filtros por estado.

Los resúmenes usan todos los registros de la lista, separan las monedas y no
incluyen notas sin datos financieros ni registros eliminados. El listado muestra
hasta cuarenta registros inicialmente y permite ver más, sin limitar el total.
Se conservan invitaciones, edición colaborativa, comprobantes, historial,
papelera y sincronización offline. El nombre del tipo personalizado y los datos
financieros se cifran antes de enviarse o guardarse en la caché de la cuenta.

Requiere publicar primero la actualización correspondiente del backend.

### Finanzas: abonos, presupuestos y rendiciones

- Los registros financieros admiten hasta 50 abonos con fecha, referencia y
  comprobante asociado. El saldo usa unidades enteras (pesos CLP o centavos
  USD/EUR); no permite abonos superiores al monto. Al completar el pago se
  cancela la alerta de ese registro.
- Vencimiento y recordatorio se configuran por separado. El tablero permite
  filtrar vencidos y meses; los totales siempre usan todos los registros del
  período y mantienen cada moneda separada.
- Los presupuestos se configuran por moneda para toda la lista o para un mes.
  Suman montos registrados, sin descartados ni transferencias. Se guardan como
  registros de control cifrados en la misma lista: reutilizan permisos,
  sincronización, historial, recuperación y protección existentes.
- Gastos compartidos: participantes por nombre (incluye sugerencias de miembros),
  quién pagó y reparto igualitario exacto. Los saldos consideran importes pagados
  y transferencias registradas entre personas; nunca convierten monedas. Usa
  nombres consistentes para la misma persona. Registrar una transferencia es
  anotar un pago realizado, no ejecutar una operación bancaria.
- Cotizaciones: precio, proveedor, plazo en días, validez, adjuntos y estado.
  El comparador ordena por moneda y precio y destaca propuestas elegidas.
- Exportación local del período: PDF, Excel `.xlsx` con hojas de registros,
  abonos y reparto, o ZIP con ambos informes y comprobantes originales. Requiere
  conexión si los adjuntos aún no están descargados. Los archivos exportados
  contienen la información legible solicitada por el usuario.
- Plantillas al crear listas: hogar, viaje compartido, remodelación, cobros y
  comparación de proveedores. Configuran nombre y tipo sin agregar gastos
  ficticios; la moneda se puede elegir antes de crear.
- El JSON financiero versión 2 agrega campos opcionales sobre el transporte
  cifrado existente; el lector mantiene compatibilidad con registros versión 1.

### Medio de pago y cuotas

Gastos y abonos admiten crédito, débito, transferencia y efectivo. Crédito permite
indicar entre 1 y 120 cuotas; es información del pago y no crea abonos ni cambia
el total. Los registros anteriores conservan el medio sin especificar. Los campos
opcionales `paymentMethod` e `installments` viajan en el JSON financiero v2 cifrado,
se mantienen en historial y aparecen en las exportaciones.
