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

## Base de datos

Las migraciones están en `supabase/migrations/` y deben aplicarse en orden sobre un proyecto Supabase. Crean las tablas, los permisos, los procedimientos de búsqueda y el canal de mensajes. PostGIS se instala en el esquema `extensions`, fuera de la API pública.

La migración de aislamiento incluye una protección para despliegues anteriores: si PostGIS está en `public` y las tablas geográficas contienen filas, aborta en lugar de eliminar datos. En ese caso se necesita una migración que conserve las ubicaciones existentes.

Las comprobaciones están en:

- `supabase/tests/rls_and_postgis_verification.sql`: permisos, cercanía, recomendaciones, privacidad del chat y reintentos. Los datos de prueba se revierten al terminar.
- `supabase/tests/deployment_health.sql`: estado de tablas, RLS, PostGIS y Realtime.

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

La revisión actual cuenta con 16 pruebas Flutter aprobadas y análisis sin incidencias. Las pruebas SQL pasaron en Supabase; su asesor de seguridad mostró cero errores y cero advertencias. El aviso informativo de la tabla privada de recibos corresponde a su acceso cerrado a clientes.

La app se compiló y abrió en un simulador iPhone con iOS 27.1, donde se completaron las cinco misiones del simulacro de sismo. Todavía falta comprobar las conversaciones y la sincronización entre sesiones reales, GPS, VoiceOver y TalkBack. No hay APK validado: falta instalar el Android SDK en el entorno de revisión.

## Estructura

```text
lib/core/          Configuración, modelos, SQLite, sincronización y accesibilidad
lib/features/      Pantallas y simulacros
supabase/          Migraciones, datos de ejemplo y pruebas SQL
test/              Pruebas de lógica, persistencia e interfaz
protipo/           Prototipo web y referencias visuales
```

## Equipo

- [itslevanx](https://github.com/itslevanx)
- [zaleo030802](https://github.com/zaleo030802)
- [JhoanAronith](https://github.com/JhoanAronith)
