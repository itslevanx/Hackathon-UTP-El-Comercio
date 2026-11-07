# NEXO — Tu comunidad, más cerca

Aplicación vecinal para el Hackathon UTP × El Comercio. Permite encontrar servicios cercanos, recomendar oficios, pedir u ofrecer ayuda y coordinar recursos durante una emergencia. NEXO es un nombre provisional.

El escenario de demostración es Pueblo Libre, Lima. Los personajes del prototipo y los simulacros son ficticios.

## Funciones

- Directorio de servicios con recomendaciones de vecinos y búsqueda por cercanía.
- Publicaciones de favores, préstamos, donaciones y necesidades de emergencia.
- Conversaciones privadas entre los participantes de una solicitud.
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
| OpenStreetMap | Mapa con ubicación aproximada y alternativa de lista |

Las coordenadas públicas se redondean a tres decimales. El GPS es opcional y se puede elegir la zona manualmente. Compartir recursos de emergencia requiere consentimiento explícito.

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
  "APP_PROVISIONAL_NAME": "NEXO"
}
```

`SUPABASE_ANON_KEY` acepta la clave pública publishable. Este archivo está excluido de Git. No uses claves secretas ni `service_role` en el cliente.

```sh
flutter run --dart-define-from-file=.env.local.json
```

Sin configuración remota, los simulacros siguen disponibles. La app no crea sesiones ficticias ni presenta envíos locales como confirmados.

## Confirmación de correo en el teléfono

En Supabase, abre **Authentication → URL Configuration** y configura `pe.vecinos.app://auth-callback` como **Site URL** y como una entrada exacta en **Redirect URLs**. Se necesita una cuenta con permisos para editar esa configuración.

El enlace abre la app instalada en el teléfono; no requiere desplegar una página web. Para recibirlo hay que instalar una compilación que incluya el esquema de retorno. Los correos anteriores pueden seguir apuntando a `localhost`: si el correo ya se confirmó, inicia sesión con la cuenta existente.

## Ubicaciones del Perú sin conexión

El selector **Departamento → Provincia → Distrito** usa el catálogo oficial de [INEI SISCONCODE](https://webapp.inei.gob.pe:8443/sisconcode/main.htm), edición **2026**, identificador `versionCategoriaPK=9-1`. Se descargó el **7 de noviembre de 2026**: 25 departamentos (incluido Callao), 196 provincias y 1.893 distritos. La fecha de descarga no implica que el INEI haya actualizado todos los registros ese día.

El recurso `assets/geography/peru_ubigeo_2026.json` ocupa unos 89 KB y se incluye en la instalación de la app. Conserva los nombres oficiales y los códigos distritales de seis dígitos; la búsqueda acepta texto sin tildes. Su metadata contiene el origen, los parámetros de consulta y la huella SHA-256 de la descarga. `tools/update_ubigeo.py` permite reconstruirlo a partir del HTML exportado por el INEI.

`PeruLocationSelector` admite valores iniciales o controlados, validación, campos opcionales, estado deshabilitado y selección hasta departamento o provincia. Los campos dependientes se limpian cuando cambia el padre. Las opciones se consultan en memoria y solo se muestran las del nivel elegido; no hay llamadas HTTP ni consultas a Supabase para cargar ubicaciones.

Está integrado en el registro y en la edición de la zona del perfil. Las publicaciones, favores y reportes de emergencia heredan el UBIGEO del perfil para conservar sus recorridos rápidos. Las referencias de barrio o sector siguen siendo texto aparte, sin asignarles un código administrativo.

SQLite conserva `district_ubigeo` en perfiles y publicaciones, y también en la cola pendiente. La versión 2 migra los registros anteriores conservando sus textos, coordenadas, borradores y operaciones. Los nombres antiguos o códigos incompletos no se convierten automáticamente: el formulario muestra el valor anterior hasta que el vecino elija una ubicación reconocida.

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

La revisión actual cuenta con 30 pruebas Flutter aprobadas y análisis sin incidencias. Las pruebas SQL pasaron en Supabase; su asesor de seguridad mostró cero errores y una advertencia de autenticación: la protección contra contraseñas filtradas está desactivada en el proyecto. Los avisos informativos de las tablas privadas sin políticas corresponden a su acceso cerrado a clientes.

La app se compiló y abrió en un simulador iPhone con iOS 27.1, donde se completaron las cinco misiones del simulacro de sismo. También se verificó la selección Amazonas → Chachapoyas → Chachapoyas y el guardado local de la zona sin crear una cuenta. Todavía falta comprobar las conversaciones y la sincronización entre sesiones reales, GPS, VoiceOver y TalkBack. No hay APK validado: falta instalar el Android SDK en el entorno de revisión.

## Estructura

```text
lib/core/          Configuración, modelos, SQLite, sincronización y accesibilidad
lib/features/      Pantallas y simulacros
supabase/          Migraciones, datos de ejemplo y pruebas SQL
test/              Pruebas de lógica, persistencia e interfaz
protipo/           Prototipo web y referencias visuales
```
