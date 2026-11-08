# Conecta2 — Tu comunidad, más cerca

Aplicación vecinal para el Hackathon UTP × El Comercio. Permite encontrar servicios cercanos, recomendar oficios, pedir u ofrecer ayuda y coordinar recursos durante una emergencia.

El escenario de demostración es Pueblo Libre, Lima. Los personajes del prototipo y los simulacros son ficticios.

## Funciones

- Directorio de servicios con recomendaciones de vecinos y búsqueda por cercanía.
- Publicaciones de favores, préstamos, donaciones y necesidades de emergencia.
- Pestaña Chats con conversaciones privadas y grupos de las emergencias que hayas abierto.
- Cada emergencia tiene un grupo para los vecinos registrados del mismo distrito. Los mensajes privados se mantienen separados; al cerrar la emergencia, su grupo queda para lectura.
- Borradores y envíos pendientes en SQLite, con reintentos y control de conflictos.
- Simulacros de sismo, lluvias y corte de servicios: reportar, coordinar ayuda, perder conexión y resolver una actividad sin enviar avisos reales.
- Texto ampliable, contraste alto, botones grandes y recorridos principales de hasta tres clics desde Inicio para usuarios con sesión activa. Escribir en los formularios no cuenta como clic.

Los avisos vecinales no sustituyen a los servicios oficiales de emergencia. Sin conexión, una solicitud queda pendiente y no es visible para otros vecinos hasta que el servidor confirme su recepción.

## Tecnología

| Componente | Uso |
|---|---|
| Flutter y Dart | Aplicación para Android y iPhone |
| Supabase Auth | Registro y acceso por correo |
| PostgreSQL y PostGIS | Datos compartidos y consultas por radio |
| Row Level Security | Permisos de acceso a publicaciones y conversaciones |
| Supabase Realtime | Actualización de mensajes |
| SQLite | Caché, borradores y cola de operaciones por cuenta |
| CARTO Voyager y OpenStreetMap | Mapa con ubicación aproximada y alternativa de lista |

Las ubicaciones de perfiles y solicitudes se redondean a tres decimales. Un servicio puede compartir voluntariamente su punto y dirección exactos como lugar de atención; esta opción viene desactivada. El GPS es opcional. Compartir recursos de emergencia requiere consentimiento explícito.

## Ejecutar la app

Se ha comprobado con Flutter 3.47.9 y Dart 3.13.7. Para Android se necesita el Android SDK; para iOS, macOS y Xcode.

```sh
git clone https://github.com/itslevanx/Hackathon-UTP-El-Comercio.git
cd Hackathon-UTP-El-Comercio
flutter pub get
```

Crea `.env.local.json` en la raíz con la configuración pública de tu proyecto:

```json
{
  "SUPABASE_URL": "https://tu-proyecto.supabase.co",
  "SUPABASE_ANON_KEY": "tu-clave-publishable",
  "CARTO_API_KEY": "tu-clave-basemaps"
}
```

`SUPABASE_ANON_KEY` acepta la clave pública publishable. Este archivo está excluido de Git. No uses claves secretas ni `service_role` en el cliente.

```sh
flutter run --dart-define-from-file=.env.local.json
```

Para ejecutar con el botón Run de Xcode, prepara también la configuración local:

```sh
python3 tools/configure_ios_environment.py
open ios/Runner.xcworkspace
```

Vuelve a ejecutar el script si cambias `.env.local.json`. Genera `.env.ios.xcconfig`, ignorado por Git; no copies sus valores al proyecto ni al esquema de Xcode. Esta configuración se conserva al ejecutar `flutter pub get`. Si compilas desde Flutter con `--dart-define-from-file`, prevalecen los parámetros de ese comando.

Sin configuración remota, los simulacros siguen disponibles. La app no crea sesiones ficticias ni presenta envíos locales como confirmados.

## Notificaciones móviles

`PushNotificationService` centraliza el permiso de notificaciones, el registro
de la instalación en Firebase Cloud Messaging (FCM) y la recepción de avisos con
la app abierta o al tocar un aviso. La app funciona con normalidad si faltan
los valores de Firebase y el registro automático está desactivado.

Para conectar un proyecto Firebase, registra las apps con los identificadores
actuales de Android e iOS y completa la configuración nativa de
[Firebase para Flutter](https://firebase.google.com/docs/flutter/setup).
Para iOS también se requieren la capacidad Push Notifications en Xcode y la
[configuración de APNs](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).
Agrega los valores públicos a `.env.local.json`:

| Campo | Uso |
|---|---|
| `FIREBASE_PROJECT_ID` | Proyecto Firebase |
| `FIREBASE_MESSAGING_SENDER_ID` | Número de proyecto para FCM |
| `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_API_KEY` | Configuración de la app Android |
| `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY` | Configuración de la app iOS |

### Mensajes privados

Con Firebase configurado, la opción **Activar avisos de mensajes** aparece en
**Chats** para usuarios con sesión. El aviso es genérico y abre la conversación
solo para la cuenta destinataria. Si ya está abierto ese chat, Realtime muestra
el mensaje directamente.

Para habilitar el envío en Supabase, aplica la migración
`20261108170000_private_message_push.sql`. La cola se llena al guardar un
mensaje privado y las instalaciones quedan vinculadas a la sesión de Supabase.
Al eliminar la sesión o desactivar los avisos, se elimina su registro y su cola.

Despliega la función con `supabase functions deploy private-message-push --no-verify-jwt`.
Configura los secretos de la función `FCM_SERVICE_ACCOUNT_JSON` con la cuenta
de servicio autorizada para enviar mediante FCM y `PRIVATE_PUSH_WORKER_SECRET`
con un valor aleatorio de alta entropía. Guarda ese mismo valor en Vault con el
nombre `private_push_worker_secret` y la URL del proyecto como `project_url`.
Las credenciales privadas quedan en el servidor y en las consolas correspondientes.

Con `pg_cron` y `pg_net` habilitados, programa el procesamiento de la cola:

```sql
select cron.schedule(
  'private-message-push',
  '15 seconds',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'project_url') || '/functions/v1/private-message-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-worker-secret',
      (select decrypted_secret from vault.decrypted_secrets
       where name = 'private_push_worker_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);
```

Comprueba el flujo con dos cuentas, activando el aviso en el teléfono del
destinatario y dejando Conecta2 en segundo plano antes de enviar el mensaje.

## Mapas CARTO

Desde Inicio, **Explorar mapa** permite consultar servicios, favores, recursos y avisos, filtrar por tipo, categoría y UBIGEO, seleccionar marcadores y abrir sus registros. El mapa del directorio y el de emergencias reutilizan el mismo componente. Las agrupaciones reúnen puntos cercanos en pantalla; la lista permite abrir un registro directamente.

La clave `CARTO_API_KEY` se lee de `.env.local.json` mediante `--dart-define-from-file`. No se incluyen claves reales en el repositorio. La app instalada puede revelar una clave embebida: restringirla reduce abusos, pero los encabezados móviles no equivalen a una prueba criptográfica de identidad.

El cliente solicita [CARTO Voyager](https://carto.com/basemaps/apikey/) con el parámetro `key`. Obtiene de la instalación `X-Ios-Bundle-Identifier` o `X-Android-Package` y `X-Android-Cert`; no deduce estos valores del deep link. Si faltan clave o identidad móvil, conserva la lista y explica el problema.

| Plataforma | Identificador actual | Certificado |
|---|---|---|
| iOS Runner, Debug y Release | `com.example.hackathonUtpElComercio` | No aplica SHA-1 |
| Android Debug | `com.example.hackathon_utp_el_comercio` | SHA-1 pendiente de obtener con Android SDK y Java |
| Android Release | `com.example.hackathon_utp_el_comercio` | Actualmente Gradle usa la firma de depuración; no hay certificado de distribución verificado |

Los identificadores están definidos en `ios/Runner.xcodeproj/project.pbxproj` y `android/app/build.gradle.kts`; el namespace Android coincide con su Application ID. Para Android, ejecutar `./gradlew :app:signingReport` desde `android/` cuando estén disponibles SDK y Java. Registrar en CARTO el SHA-1 de la firma efectiva, incluido el certificado de app signing de Play si se distribuye por esa vía. No registrar `pe.vecinos.app` como Bundle ID: es el esquema de retorno de autenticación.

Las consultas reutilizan `search_publications_by_location` y `search_resources_within_radius`, con la sesión y RLS existentes. El mapa solicita hasta 201 resultados por consulta y presenta hasta 200; los filtros permiten acotar la vista. Desplazar o ampliar el mapa no lanza consultas de registros. El distrito explícito se consulta por su código completo; departamento y provincia filtran la copia local hasta elegir un distrito. Los recursos históricos carecen de UBIGEO y se muestran por cercanía, sin asignarles un distrito por su nombre.

El GPS se solicita solo al tocar **Mi ubicación**. Se usa una lectura puntual redondeada para centrar la vista; muestra un pin azul privado durante la visita al mapa; no modifica el perfil ni publica la ubicación. Las publicaciones propias sin coordenadas o UBIGEO también aparecen en la lista general, con una acción para ubicarlas. Un filtro administrativo explícito sigue exigiendo un código compatible; no se asigna automáticamente el distrito del perfil a publicaciones antiguas. No hay seguimiento continuo ni marcadores de perfiles privados.

Los [términos CARTO del 29/09/2026](https://carto.com/legal/basemap-terms/) permiten caché temporal de cliente hasta 30 días y prohíben la descarga masiva y la caché o proxy en servidores. Los tiles consultados se conservan en una base SQLite separada, hasta 100 MB y durante el plazo indicado por el servidor, con un máximo de 30 días. Se eliminan los vencidos y se liberan los más antiguos cuando falta espacio. No se hacen descargas masivas ni anticipadas de regiones. Para preparar una zona, ábrela y recórrela con conexión en los niveles de zoom que necesites. Sin conexión pueden verse esas calles guardadas; las áreas no guardadas pueden quedar vacías. El catálogo INEI, los filtros y la lista de avisos siguen disponibles. El uso queda sujeto a las cuotas del proveedor; no se contrató ningún plan de pago.

## Elegir un punto para una publicación

**Elegir ubicación en el mapa** abre un editor opcional al publicar y al configurar la zona del perfil. Permite elegir departamento, provincia y distrito del catálogo INEI, tocar el mapa, arrastrar el pin o buscar una dirección. La referencia inicial de capital distrital no confirma una dirección: es necesario seleccionar o mover el punto antes de guardarlo. Se conserva el recorrido rápido de publicación sin abrir el editor.

La búsqueda usa [geocoding](https://pub.dev/packages/geocoding), que consulta el proveedor nativo de iOS o Android bajo sus límites. La dirección solo se envía al buscar; no hay autocompletado, seguimiento ni consultas al servicio público Nominatim. Puede requerir conexión y devolver varias coincidencias o ninguna. Siempre hay que comprobar el distrito y el punto; no se garantiza la precisión del proveedor.

En un servicio, **Compartir el punto y la dirección exactos como lugar de atención de mi servicio** permite publicar esa referencia para vecinos con sesión. Sin ese consentimiento se guarda únicamente el punto aproximado; la dirección escrita se descarta. El perfil, los favores y las emergencias mantienen su ubicación aproximada. Buscar direcciones y cargar calles nuevas requiere red. Las calles guardadas, el catálogo, los borradores y los envíos pendientes funcionan con SQLite.

Para ubicar una publicación antigua: **Inicio → Explorar mapa → Ubicar esta publicación en el mapa** en la lista propia. Seleccionar el punto y guardar. No se inventan coordenadas ni se migran automáticamente las ubicaciones antiguas. Si hay un filtro de distrito que excluya una publicación sin UBIGEO, quitarlo primero.

SQLite **versión 3** añade los campos opcionales del servicio y `location_json` al borrador. La ubicación queda en una transacción con su operación pendiente. Cambiar la ubicación de una publicación existente usa `publication_location`, conserva la versión local mientras haya envíos pendientes y permite reintentos idempotentes. La migración de Supabase `20261107235826_public_service_locations.sql` incorpora esos campos y `update_publication_location`; verifica autoría, UBIGEO, coordenadas, consentimiento y versión. Los recibos de operaciones están en un esquema privado sin acceso directo desde clientes. Los registros históricos se conservan.

## Avisos, edición y uso sin conexión

Debajo de las acciones de Inicio aparece **Avisos del barrio**, con tarjetas del más reciente al más antiguo. Incluye anuncios, servicios, favores, préstamos, donaciones, intercambios y reportes de emergencia. Las tarjetas se crean conforme se recorren, para mantener fluidez. El historial del distrito se descarga por páginas mientras la app está abierta y hay conexión; no hace falta recorrerlo entero para conservarlo. La primera descarga puede tardar y se retoma si se interrumpe. Si todavía no se ha elegido distrito, el feed consulta solo las publicaciones propias.

El autor dispone de **Editar** y **Eliminar** en su tarjeta y en el detalle. Puede corregir título, descripción y disponibilidad del servicio. El punto se cambia desde Explorar mapa. Eliminar pide confirmación, quita el aviso del feed y del mapa y conserva las conversaciones asociadas. Los avisos eliminados no permiten nuevas ofertas o recomendaciones.

Crear, editar y eliminar se guarda primero en SQLite junto con una operación pendiente. Al detectar conexión, o al volver a abrir la app, se intenta enviar la cola. El sistema operativo puede suspender una app cerrada; no se garantiza envío mientras permanezca cerrada. Si una creación nunca se ha intentado enviar y se elimina sin conexión, se cancela localmente y no se publica después. Si el envío ya pudo llegar al servidor, se conserva la eliminación pendiente. Un fallo anterior bloquea los cambios posteriores del mismo aviso, y los conflictos requieren revisión. Los reintentos no duplican la publicación ni la modificación.

Sin internet se consulta el contenido que alcanzó a descargarse antes del corte, incluso después de cerrar y volver a abrir. Al recuperar conexión se actualizan los avisos guardados que hayan cambiado y se retiran los eliminados por sus autores. No se pueden conocer avisos nuevos del servidor mientras no haya conexión, iniciar una cuenta nueva, buscar direcciones en línea ni descargar calles que no estén guardadas. Los mensajes conservan su comportamiento de borrador cuando no pueden enviarse.

SQLite versión **4** añade `deleted_at` sin eliminar registros ni operaciones anteriores. La migración `20261108033825_publication_crud_and_feed.sql` añade edición y eliminación idempotentes con control de autor y versión, el feed paginado y los identificadores de publicaciones retiradas. Estos identificadores permiten limpiar las copias de otros teléfonos sin exponer el contenido eliminado. Las conversaciones no se borran en cascada.

## Confirmación de correo en el teléfono

En Supabase, abre **Authentication → URL Configuration** y configura `pe.vecinos.app://auth-callback` como **Site URL** y como una entrada exacta en **Redirect URLs**. Se necesita una cuenta con permisos para editar esa configuración.

El enlace abre la app instalada en el teléfono; no requiere desplegar una página web. Para recibirlo hay que instalar una compilación que incluya el esquema de retorno. Los correos anteriores pueden seguir apuntando a `localhost`: si el correo ya se confirmó, inicia sesión con la cuenta existente.

## Recuperar una contraseña

En el formulario de acceso, **Olvidé mi contraseña** permite enviar un enlace al correo de la cuenta. La respuesta es genérica para no revelar si un correo está registrado. Abre el correo en el mismo teléfono y pulsa el enlace: el retorno `pe.vecinos.app://auth-callback`, ya registrado en Supabase e iOS/Android, lleva a una pantalla para escribir y repetir una nueva contraseña de al menos ocho caracteres.

La pantalla se habilita únicamente tras el evento de recuperación validado por Supabase. La contraseña se actualiza con `auth.updateUser`, sin guardarse en SQLite, borradores ni cola offline. Se requiere conexión; los errores permiten reintentar y los enlaces vencidos requieren solicitar otro correo. No hace falta desplegar una página web. El envío y la recepción reales dependen de la configuración y los límites de correo de Supabase.

## Ubicaciones del Perú sin conexión

El selector **Departamento → Provincia → Distrito** usa el catálogo oficial de [INEI SISCONCODE](https://webapp.inei.gob.pe:8443/sisconcode/main.htm), edición **2026**, identificador `versionCategoriaPK=9-1`. Se descargó el **7 de noviembre de 2026**: 25 departamentos (incluido Callao), 196 provincias y 1.893 distritos. La fecha de descarga no implica que el INEI haya actualizado todos los registros ese día.

El recurso `assets/geography/peru_ubigeo_2026.json` ocupa unos 89 KB y se incluye en la instalación de la app. Conserva los nombres oficiales y los códigos distritales de seis dígitos; la búsqueda acepta texto sin tildes. Su metadata contiene el origen, los parámetros de consulta y la huella SHA-256 de la descarga. `tools/update_ubigeo.py` permite reconstruirlo a partir del HTML exportado por el INEI.

`PeruLocationSelector` admite valores iniciales o controlados, validación, campos opcionales, estado deshabilitado y selección hasta departamento o provincia. Los campos dependientes se limpian cuando cambia el padre. Las opciones se consultan en memoria y solo se muestran las del nivel elegido; no hay llamadas HTTP ni consultas a Supabase para cargar ubicaciones.

Está integrado en el registro, la edición de la zona del perfil y el editor opcional de ubicación de publicaciones. Las publicaciones, favores y reportes de emergencia heredan el UBIGEO del perfil para conservar sus recorridos rápidos, salvo que se elija expresamente otra ubicación. Las referencias de barrio o sector siguen siendo texto aparte, sin asignarles un código administrativo.

SQLite conserva `district_ubigeo` en perfiles y publicaciones, y también en la cola pendiente. La migración desde la versión 1 conserva los textos, coordenadas, borradores y operaciones existentes. Los nombres antiguos o códigos incompletos no se convierten automáticamente: el formulario muestra el valor anterior hasta que el vecino elija una ubicación reconocida.

La migración `20261107165219_peru_ubigeo_locations.sql` añade las columnas opcionales, sus índices y referencias al catálogo privado del servidor. Mantiene la búsqueda espacial anterior y añade una consulta por distrito para los registros sin coordenadas. El catálogo privado valida las escrituras; la app usa su copia local.

Cuando no se usa GPS, una zona nueva puede tomar las coordenadas de capital publicadas por el INEI. Hay 35 distritos sin una coordenada de capital utilizable en esta fuente: su selección sigue funcionando, pero se muestran por distrito, sin inventar una distancia ni un marcador. Una ubicación guardada no se reemplaza por la capital al editar su referencia.

| Archivos | Responsabilidad |
|---|---|
| `assets/geography/peru_ubigeo_2026.json`, `tools/update_ubigeo.py` | Catálogo, procedencia y reconstrucción |
| `lib/core/geography/peru_location_catalog.dart` | Índices, jerarquías y búsqueda local |
| `lib/features/shared/peru_location_selector.dart` | Componente reutilizable y selector con búsqueda |
| `lib/features/auth/auth_and_onboarding_screen.dart` | Registro y edición de zona |
| `lib/core/models/domain_models.dart`, `lib/core/state/app_controller.dart` | UBIGEO, restauración y publicaciones heredadas |
| `lib/core/database/local_sqlite_database.dart`, `lib/core/sync/supabase_remote_gateway.dart` | Migración SQLite y sincronización |
| `lib/features/shared/civic_widgets.dart`, pantallas de servicios, actividades, favores y publicación | Nombres completos y manejo de resultados sin coordenadas |
| `supabase/migrations/20261107165219_peru_ubigeo_locations.sql` | Compatibilidad y validación en PostgreSQL |
| `test/peru_locations_test.dart`, `test/fixtures/sqlite_v1.sql`, `supabase/tests/ubigeo_verification.sql` | Pruebas del selector, persistencia, migración y permisos |

El selector y las preferencias funcionan sin internet; crear una cuenta real de Supabase o confirmar un envío a otros vecinos sigue requiriendo conexión. El prototipo HTML permanece como material de referencia, separado de los formularios móviles.

## Base de datos

Las migraciones están en `supabase/migrations/` y deben aplicarse en orden sobre un proyecto Supabase. Crean las tablas, los permisos, los procedimientos de búsqueda y el canal de mensajes. PostGIS se instala en el esquema `extensions`, fuera de la API pública.

La migración de aislamiento incluye una protección para despliegues anteriores: si PostGIS está en `public` y las tablas geográficas contienen filas, aborta en lugar de eliminar datos. En ese caso se necesita una migración que conserve las ubicaciones existentes.

Las comprobaciones están en:

- `supabase/tests/rls_and_postgis_verification.sql`: permisos, cercanía, recomendaciones, privacidad del chat y reintentos. Los datos de prueba se revierten al terminar.
- `supabase/tests/deployment_health.sql`: estado de tablas, RLS, PostGIS y Realtime.
- `supabase/tests/ubigeo_verification.sql`: catálogo, códigos válidos, perfiles y publicaciones sin GPS, compatibilidad y permisos. Revierte sus datos de prueba.
- `supabase/tests/publication_location_verification.sql`: ubicación de publicaciones, consentimiento, autoría, versiones y reintentos. Revierte los datos de prueba.
- `supabase/tests/publication_crud_verification.sql`: edición, eliminación, feed, propagación de retiradas y permisos. Revierte los datos de prueba.

`supabase/seed.sql` contiene datos de demostración opcionales; no debe cargarse como contenido real del barrio.

## Prototipo web

Las pantallas de referencia están en `protipo/`. Se puede abrir `protipo/index.html` o servir la carpeta:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory protipo
```

Abre [localhost:8000](http://localhost:8000). El prototipo incluye recursos externos y sus formularios no publican datos en Supabase.

## Pruebas y estado

```sh
flutter analyze
flutter test
node --check protipo/prototype.js
node --check protipo/practice.js
```

La revisión anterior de las funciones existentes se comprobó también con SQL en Supabase. La validación de los módulos comunitarios nuevos se describe al final de este documento y se ejecuta sobre una base aislada.

La app se compiló y abrió en un simulador iPhone con iOS 27.1, donde se completaron las cinco misiones del simulacro de sismo. También se probaron la selección Amazonas → Chachapoyas → Chachapoyas, el guardado local de la zona, la búsqueda nativa de una referencia pública y el arrastre del pin, sin crear una cuenta. Todavía falta comprobar las conversaciones y la sincronización entre sesiones reales, GPS, VoiceOver y TalkBack. No hay APK validado: falta instalar el Android SDK en el entorno de revisión.

## Estructura

```text
lib/core/          Configuración, modelos, SQLite, sincronización y accesibilidad
lib/features/      Pantallas y simulacros
supabase/          Migraciones, datos de ejemplo y pruebas SQL
test/              Pruebas de lógica, persistencia e interfaz
protipo/           Prototipo web y referencias visuales
```

## Identidad e iconos

El nombre visible es Conecta2. El icono maestro está en `assets/branding/conecta2-icon.svg`; `tools/generate_app_icons.py` genera los tamaños de iOS, Android, macOS, Windows y web con Pillow y resvg-py. Los identificadores de aplicación y nombres de las bases locales se conservan para mantener las instalaciones y sus datos.

## Grupos de emergencia

Desde el detalle de una emergencia puedes entrar a su chat grupal. El acceso se valida mediante RLS: autor y vecinos autenticados del mismo distrito UBIGEO. No se publican automáticamente conversaciones privadas ni coordenadas de los participantes.

Los mensajes se guardan primero en SQLite y se sincronizan con una clave de idempotencia. Sin conexión, el historial consultado permanece disponible y los mensajes nuevos muestran su estado pendiente hasta recibir confirmación. Los grupos abiertos aparecen en Chats. La caché está separada por cuenta; SQLite se migra de la versión 4 a la 5 sin reemplazar las tablas anteriores.

La migración `20261108071749_emergency_group_chat.sql` añade mensajes de grupo, políticas RLS, RPC de envío e historial y actualizaciones Realtime. La verificación transaccional está en `supabase/tests/emergency_group_chat_verification.sql` y revierte todos sus datos de prueba.

En Chats puedes fijar conversaciones privadas o grupos para tenerlos al principio y quitarlos de tu lista con «Eliminar de mi lista». Estas preferencias se guardan en SQLite por cuenta y teléfono, incluso sin conexión. No borran mensajes ni afectan las listas de otros vecinos. Puedes deshacer la acción o abrir de nuevo el chat desde su publicación. Los grupos y privados comparten burbujas: tus mensajes aparecen a la derecha y los de los demás a la izquierda.

Desde «Mis publicaciones y reportes» también puedes editar o eliminar tus avisos con las mismas reglas de permisos y sincronización del resto de la app.

Los chats privados se agrupan por vecino, aunque lo contactes desde distintos servicios. El mensaje de contacto conserva el nombre del aviso como contexto. Los historiales anteriores se reúnen sin borrar sus mensajes y los borradores pendientes se conservan. La lista se ordena por el último mensaje, con los chats fijados primero; recibe cambios en tiempo real y consulta de nuevo al recuperar conexión.

La migración `20261108163300_neighbor_chats_and_activity.sql` añade consultas y envíos entre vecinos con RLS, reutilización de la conversación existente e historial paginado. No elimina hilos ni mensajes históricos. Sus verificaciones están en `supabase/tests/neighbor_chat_verification.sql`.

## Riesgos comunitarios y ayudas recomendadas

**Explorar mapa** distingue las agrupaciones visuales de marcadores de las concentraciones de reportes. La RPC `community_risk_snapshot` ejecuta DBSCAN en PostGIS por distrito y categoría, sobre reportes de emergencia abiertos o en coordinación. Usa las ubicaciones públicas aproximadas y una proyección UTM del hemisferio sur elegida según la longitud media del distrito consultado. El radio se mide en metros proyectados; no representa un límite exacto sobre el terreno.

Se conserva el reporte más reciente de cada cuenta y categoría dentro de la ventana temporal. Se excluyen eliminados, demostraciones, reportes futuros, ubicaciones ausentes y reportes de invitados sin identidad de cuenta. Las cuentas distintas no equivalen a identidades humanas verificadas. El límite es de 1.000 reportes independientes por consulta: si se supera, no se generan concentraciones parciales. Los reportes individuales siguen disponibles en la lista habitual.

La configuración se concentra en `lib/core/intelligence/community_intelligence.dart`, clase `IntelligenceConfig`:

| Parámetro | Valor inicial | Rango admitido por el servidor |
|---|---:|---:|
| Radio DBSCAN | 300 m | 50–1.000 m |
| Ventana temporal | 15 minutos | 1–60 minutos |
| Mínimo de cuentas distintas | 3 | 3–20 |
| Compatibilidad del recurso | 40 % | Pesos no negativos que sumen 100 % |
| Distancia | 25 % | Igual |
| Disponibilidad | 20 % | Igual |
| Urgencia de la solicitud | 15 % | Igual |

Una concentración requiere atención cuando alcanza el doble del mínimo de cuentas y contiene un reporte del último tercio de la ventana. **Nunca se marca como emergencia confirmada**: el modelo actual no contiene una fuente autorizada de verificación ni evidencias estructuradas. Los círculos ilustran la zona aproximada del marcador, no el alcance de un desastre. El detalle muestra fechas, motivo y acceso a los reportes permitidos por RLS. Se puede filtrar por categoría y nivel de atención.

### Coincidencias entre solicitudes y ofertas

Desde el detalle de una solicitud propia abierta, **Consultar ayudas recomendadas** busca ofertas autorizadas del mismo distrito. El servidor filtra por titular, estado, consentimiento y familia de recurso; Dart puntúa los candidatos. Se incluyen ofertas de favores, préstamos, donaciones, habilidades, servicios y recursos de emergencia con consentimiento. Se excluyen ofertas resueltas, canceladas, en coordinación, eliminadas, de demostración y del propio solicitante.

La compatibilidad usa identificadores de categoría, nunca el título ni palabras sueltas de la descripción. Hay equivalencias explícitas para `agua_potable`/`agua`, `movilidad`/`transporte` y `albergue`/`refugio`. Las demás categorías deben coincidir exactamente. Las categorías genéricas `general`, `donaciones` y `habilidades` no generan recomendaciones: se puede elegir una categoría concreta al publicar o editar, conservando el resto del aviso. Para ampliar las equivalencias hay que mantener alineados `CommunityCategories.family` y `community_resource_family`.

El puntaje suma compatibilidad, cercanía normalizada hasta 20 km, disponibilidad y urgencia. Sin coordenadas comparables, la cercanía recibe cero puntos y se indica distancia desconocida. No se interpreta un horario escrito como prueba de disponibilidad: una oferta abierta recibe la mitad del peso de disponibilidad y exige confirmación con el vecino. **Marcar recurso agotado** pasa la oferta a resuelta mediante la cola de estados existente. El puntaje es orientativo, no una probabilidad de éxito ni una acreditación profesional. Los empates se ordenan por identificador para mantener resultados estables.

Las ofertas llegan en páginas de 200, con cursor por identificador y **Cargar más ofertas**. La clasificación compara las páginas cargadas, no todas las ofertas aún sin consultar. Cada actualización comienza otra vez por la primera página. El detalle y el contacto vuelven a comprobar la publicación en el servidor; el mensaje solo se envía después de que el usuario lo escriba y pulse Enviar. Se reutiliza el chat privado por vecino.

### Actualización, caché y permisos

`IntelligenceController` reutiliza los avisos del controlador de la app y el ciclo de consulta de 30 segundos. Agrupa cambios durante 800 ms y no consulta al desplazar o ampliar el mapa. Las ediciones, eliminaciones, cambios de zona, sesión y conectividad invalidan la vigencia de la vista. La consulta periódica actualiza también las ventanas temporales aunque no lleguen nuevos reportes.

SQLite **versión 6** añade únicamente `intelligence_cache`. Sus claves incluyen cuenta, UBIGEO, solicitud y configuración del algoritmo. Los resultados llevan fecha de consulta y vencimiento. La migración local conserva las publicaciones, borradores y operaciones pendientes; al salir se elimina la caché de inteligencia de esa cuenta.

Sin conexión se muestran exclusivamente consultas guardadas, con su fecha y advertencia de caducidad. No se ejecuta DBSCAN local ni se buscan ofertas nuevas en el feed incompleto del teléfono. Los detalles guardados de recomendaciones siguen accesibles; el contacto y la confirmación de disponibilidad requieren volver a verificar con conexión. Un fallo de red conserva la copia, mientras que un rechazo de autorización la descarta. Cargar páginas posteriores no renueva la antigüedad de las páginas previas. El mapa base conserva sus propias reglas de caché de CARTO, sin nuevas descargas masivas.

La migración incremental `supabase/migrations/20261108210000_community_intelligence.sql` añade dos índices y tres funciones: `community_resource_family`, `community_risk_snapshot` y `community_help_candidates`. Las RPC son `SECURITY INVOKER`, tienen `search_path` vacío y solo permiten ejecución autenticada. No amplían RLS, no publican perfiles privados y no requieren claves de servicio. Las coordenadas de concentraciones se redondean a tres decimales. No se añade una tabla de verificación ni un sistema de bloqueo: cualquier futura política restrictiva sobre publicaciones se aplica también a estas consultas.

La migración comunitaria se activó en el proyecto actual el 8 de noviembre de 2026. Se comprobó la solicitud real de agua con una donación temporal bajo el rol autenticado; la cuenta y la oferta de prueba se revirtieron. En otros entornos hay que revisar y aplicar la migración antes de consultar las RPC. No hay configuración adicional de CARTO ni nuevas dependencias.

### Verificación de estos módulos

```sh
flutter analyze
flutter test
# Base local o de pruebas con las migraciones del repositorio aplicadas:
psql "$LOCAL_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/community_intelligence_verification.sql
```

Las pruebas nuevas cubren radio, ventana temporal, categorías incompatibles, cuentas repetidas, coordenadas modificadas o ausentes, eliminaciones, atención sin verificación, RLS, límite de 1.000 reportes, paginación, puntuación, empates, agotados, consentimiento, caché aislada, reconexión, respuestas tardías, migración SQLite y selección del marcador de concentración. Las fixtures SQL se revierten al finalizar.

Para validar en Android e iOS, usar un entorno de pruebas con tres cuentas distintas, el mismo UBIGEO y reportes de la misma categoría a menos de 300 metros publicados dentro de 15 minutos. Abrir Explorar mapa, revisar la concentración, cambiar los filtros y editar o resolver uno de los reportes; la concentración debe actualizarse en el siguiente ciclo. Crear también una solicitud de agua y una oferta ajena de agua, comprobar su recomendación y el chat existente; una oferta de transporte no debe aparecer. Marcar la oferta como agotada y actualizar. Tras consultar ambas vistas, desconectar internet, reabrirlas y comprobar las fechas de datos guardados y que no se confirme disponibilidad. Reconectar y actualizar.

Capacidad del proyecto remoto comprobada en lectura: PostgreSQL 17.11, PostGIS 3.3.7 y `ST_ClusterDBSCAN` disponible en `extensions`. Las verificaciones SQL se ejecutaron en una base local aislada con PostgreSQL 17.5 y PostGIS 3.5.2; no equivalen a una prueba de despliegue en producción. La implementación usa una función [disponible desde PostGIS 2.3](https://postgis.net/docs/ST_ClusterDBSCAN.html), con orden explícito para asignaciones de borde reproducibles.

Validación de esta entrega: 111 pruebas Flutter aprobadas, `flutter analyze` sin incidencias, nueve scripts SQL aprobados en la base local e iOS Simulator compilado sin firma. Android no se compiló porque este entorno no tiene Android SDK ni Java Runtime. No se instalaron estos cambios en dispositivos físicos.

El panel de riesgos del mapa es desplegable para dar prioridad al mapa y a los avisos. Los mensajes de conexión se mantienen breves; el detalle conserva el contexto de cada concentración.
