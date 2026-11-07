# NEXO — Tu comunidad, más cerca

Prototipo de colaboración vecinal para el reto **Hackathon UTP · El Comercio**. Reúne servicios recomendados por vecinos, una cadena de favores, recursos comunitarios y ejercicios de preparación ante distintas situaciones.

El escenario de demostración es **Pueblo Libre, Lima, Perú**, con personajes y datos de ejemplo.

## Estado del proyecto

El material de referencia está concentrado en **`protipo/`**: un prototipo web navegable de 24 pantallas, 14 capturas y la guía del equipo. La raíz queda reservada para desarrollar la aplicación; actualmente solo contiene este README, `.gitignore` y la carpeta del prototipo.

| Elemento | Estado |
|---|---|
| Interfaces HTML y diseño visual | Disponibles. |
| Navegación entre pantallas | Conectada mediante `prototype.js`. |
| Formularios y confirmaciones | Demostraciones locales; no realizan envíos reales. |
| Aplicación Flutter para iOS y Android | Planificada; todavía no implementada. |
| Base local SQLite y funcionamiento offline completo | Planificados; todavía no implementados. |
| API, autenticación y sincronización entre usuarios | Pendientes de definición e implementación. |

**La presencia de pantallas de “modo sin conexión” no significa que el prototipo ya funcione completamente offline.** Sus estilos, fuentes, iconos e imágenes incluyen dependencias externas.

## Inicio rápido en macOS

### 1. Obtener el repositorio

```sh
git clone https://github.com/itslevanx/Hackathon-UTP-El-Comercio.git
cd Hackathon-UTP-El-Comercio
```

El repositorio requiere acceso autorizado si permanece privado. Usa tu método habitual de autenticación de GitHub; no guardes tokens en los archivos ni en la URL del remoto.

### 2. Abrir el prototipo

No requiere instalar dependencias de Node ni ejecutar una compilación. Desde Finder, abre `protipo/index.html` en tu navegador. También puedes hacerlo desde Terminal:

```sh
open protipo/index.html
```

Para revisar el prototipo servido por HTTP, si tienes Python 3 instalado:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory protipo
```

Abre [http://localhost:8000](http://localhost:8000). Para detener el servidor, pulsa `Control + C` en Terminal. Si el puerto está ocupado, usa otro, por ejemplo `8001`.

Mantén conexión a internet para cargar los recursos externos del diseño actual.

### 3. Recorrer las pantallas

- `protipo/index.html` lleva a la bienvenida.
- La barra inferior conecta Inicio, Explorar, Publicar, Favores y Perfil.
- Los botones principales conectan detalles, formularios y confirmaciones.
- El menú flotante **Pantallas** permite abrir directamente cualquiera de las 24 vistas, incluidos los estados de demostración.
- Los simulacros incluyen accesos para regresar o salir del ejercicio.

## Recorridos de demostración

| Recorrido | Secuencia principal |
|---|---|
| Ingreso | Bienvenida → Registro → Inicio. |
| Servicios | Inicio → Explorar → Detalle de servicio → Recomendar → Inicio. |
| Favores | Inicio o Favores → Solicitud de Carmen → Confirmar oferta → Favores. |
| Publicación | Publicar → Confirmación de demostración → Favores. |
| Recursos | Inicio → Red de apoyo → Mapa de zonas y recursos. |
| Información guardada | Perfil → Mis notas y borradores → Información sin conexión → Editor. |
| Práctica de sismo | Red de apoyo → Selector → Primera decisión → Aprendizajes → Segunda decisión → Solicitudes simuladas → Oferta simulada → Resultado. |
| Otros escenarios | Selector → Lluvias intensas o Corte de agua y luz → Regreso al selector. |

Algunos controles conservan interacciones visuales de ejemplo. No se implementan conversación real, publicación remota, reportes moderados ni validación oficial de servicios.

## Estructura del repositorio

```text
.
├── README.md                       # Presentación, uso y colaboración
├── .gitignore                      # Exclusiones para macOS y desarrollo
└── protipo/                        # Todo el material del prototipo
    ├── index.html                  # Entrada al prototipo
    ├── prototype.js                # Navegación y menú de pantallas
    ├── EQUIPO.md                   # Arquitectura propuesta y plan de ejecución
    ├── calm_civic_humanist/
    │   └── DESIGN.md               # Referencia de diseño visual
    └── <número>._<nombre>/
        ├── code.html               # Interfaz de cada pantalla
        └── screen.png              # Referencia visual, cuando está disponible
```

Mantener dentro de `protipo/` los HTML, las capturas, los recursos y la documentación de referencia del prototipo. El nuevo proyecto móvil se desarrollará en la raíz cuando el equipo lo inicialice.

Los nombres de las carpetas provienen de la exportación original. No todas las pantallas incluyen captura.

## Catálogo de pantallas

| N.º | Pantalla | Captura local |
|---|---|---|
| 1 | [Bienvenida](protipo/1._bienvenida_nexo/code.html) | No |
| 2 | [Registro por barrio](protipo/2._registro_por_barrio/code.html) | No |
| 3 | [Inicio](protipo/3._inicio_hola_rosa/code.html) | Sí |
| 4 | [Explorar servicios](protipo/4._explorar_servicios/code.html) | No |
| 5 | [Detalle de servicio](protipo/5._detalle_de_servicio_luis_alberto/code.html) | No |
| 6 | [Recomendar servicio](protipo/6._recomendar_servicio_confirmaci_n/code.html) | No |
| 7 | [Cadena de favores](protipo/7._cadena_de_favores_pueblo_libre/code.html) | Sí |
| 8 | [Publicar en el barrio](protipo/8._publicaci_n_r_pida_en_el_barrio/code.html) | No |
| 9 | [Solicitud de Carmen](protipo/9._detalle_de_solicitud_do_a_carmen/code.html) | No |
| 10 | [Confirmar oferta](protipo/10._confirmar_oferta_pueblo_libre/code.html) | No |
| 11 | [Red de apoyo vecinal](protipo/11._red_de_apoyo_vecinal/code.html) | Sí |
| 12 | [Mapa de zonas y recursos](protipo/12._mapa_de_zonas_y_recursos/code.html) | Sí |
| 13 | [Perfil de Rosa](protipo/13._perfil_vecinal_do_a_rosa/code.html) | No |
| 14 | [Información sin conexión](protipo/14._modo_sin_conexi_n_informaci_n_guardada/code.html) | Sí |
| 15 | [Estados del prototipo](protipo/15._tablero_de_estados_ui/code.html) | Sí |
| 16 | [Elegir simulacro](protipo/16._selector_de_simulacro_prep_rate_con_tu_comunidad/code.html) | Sí |
| 17 | [Sismo: primera decisión](protipo/17._sismo_decisi_n_1_durante_el_movimiento/code.html) | Sí |
| 18 | [Sismo: aprendizajes](protipo/18._sismo_retroalimentaci_n_educativa_1/code.html) | Sí |
| 19 | [Sismo: apoyo vecinal](protipo/19._sismo_decisi_n_2_apoyo_vecinal_seguro/code.html) | Sí |
| 20 | [Solicitudes simuladas](protipo/20._red_de_apoyo_simulada_solicitudes_ficticias/code.html) | Sí |
| 21 | [Oferta simulada](protipo/21._detalle_simulado_oferta_registrada_ficticia/code.html) | No |
| 22 | [Resultado de la práctica](protipo/22._resultado_pr_ctica_completada/code.html) | Sí |
| 23 | [Lluvias intensas](protipo/23._inundaci_n_lluvias_intensas_y_zonas_seguras/code.html) | Sí |
| 24 | [Corte de agua y luz](protipo/24._corte_de_servicios_pr_ctica_sin_conexi_n/code.html) | Sí |

## Tecnologías del prototipo actual

- **HTML y JavaScript:** estructura de las pantallas, navegación y acciones de demostración.
- **Tailwind CSS mediante CDN:** estilos de las interfaces exportadas.
- **Google Fonts y Material Symbols:** tipografía e iconos.
- **Imágenes remotas y capturas PNG locales:** recursos visuales y referencias.

Las páginas HTML no utilizan un proyecto React o Flutter. No hay `package.json`, `pubspec.yaml`, base de datos ni servidor de aplicación en esta entrega.

## Dirección técnica para iPhone y Android

La base acordada para la aplicación móvil es **Flutter + SQLite con Drift**:

| Capa | Elección | Propósito |
|---|---|---|
| Aplicación | Flutter / Dart | Compartir gran parte de la interfaz y lógica entre iOS y Android. |
| Almacenamiento local | SQLite + Drift | Consultar datos descargados y guardar acciones sin conexión. |
| Datos compartidos | API + PostgreSQL, por implementar | Intercambiar información entre vecinos cuando haya conexión. |
| Sincronización | Cola local de operaciones, por implementar | Confirmar envíos, reintentar sin duplicar y tratar conflictos. |

La aplicación debe leer y escribir primero en el dispositivo. Una solicitud creada sin internet se guarda como **Pendiente de enviar** y solo pasa a **Enviado** después de la confirmación del servidor. No será visible para otro vecino antes de sincronizarse.

SQLite no sincroniza automáticamente con PostgreSQL. El equipo deberá implementar ese intercambio o elegir una solución especializada.

Para compilar y probar iOS se necesita una Mac con Xcode. La carpeta actual todavía no contiene un proyecto móvil que pueda abrirse o compilarse con Flutter.

Consulta [EQUIPO.md](protipo/EQUIPO.md) para el alcance recomendado, las entidades mínimas, las reglas de sincronización, el reparto de trabajo y los criterios de aceptación.

## Prioridades de la hackathon

1. Crear el proyecto Flutter y comprobar que arranca en iOS y Android.
2. Construir el recorrido principal y guardar información con Drift.
3. Incluir recursos y datos de ejemplo para usar la app sin internet.
4. Demostrar una solicitud que persista después de cerrar y abrir la app.
5. Completar un simulacro en modo avión.
6. Incorporar sincronización real o identificar claramente su simulación.
7. Ampliar las pantallas y funcionalidades después de validar el recorrido completo.

## Cómo modificar la navegación web

1. Edita la interfaz correspondiente en `protipo/<carpeta-de-pantalla>/code.html`.
2. Revisa el objeto `routes` y el bloque `switch` en `protipo/prototype.js` para cambiar destinos o conectar controles.
3. Mantén la carga de `../prototype.js` en cada pantalla.
4. Si renombras una carpeta, actualiza también los enlaces de la barra inferior, `protipo/index.html` y este catálogo.
5. Comprueba el recorrido de ida, los botones de regreso y las salidas del simulacro.

Los controles se conectan por identificador o texto. Cambiar el texto de un botón puede requerir actualizar su conexión en `protipo/prototype.js`.

## Verificación antes de compartir cambios

- Abrir la bienvenida y probar la barra inferior.
- Recorrer servicios, recomendaciones, favores y publicación.
- Elegir cada uno de los tres escenarios de práctica y comprobar las salidas.
- Revisar el menú **Pantallas** y sus 24 destinos.
- Comprobar las confirmaciones de demostración.
- Revisar el diseño con ancho de teléfono y texto ampliado.
- Si tienes Node.js, comprobar la sintaxis con `node --check protipo/prototype.js`.
- Revisar `git diff --check` y `git status` antes de crear el commit.

El repositorio todavía no incluye una suite automatizada de pruebas. Las pruebas offline de la futura app deben incluir cierre y reapertura, reintentos y recuperación de conexión.

## Trabajo en equipo y commits

Crear una rama por cambio y utilizar mensajes en español que describan una sola intención:

```sh
git switch -c mejora/nombre-del-cambio
# Realizar y revisar el cambio antes de seleccionar los archivos.
git add ruta/al/archivo
git commit -m "feat: conectar el regreso al listado de favores"
git push -u origin mejora/nombre-del-cambio
```

Abrir una solicitud de cambios hacia `main` para facilitar la revisión. Separar cambios de interfaz, correcciones y documentación cuando sean independientes. No incluir credenciales, datos personales reales ni archivos generados.

### Archivos ignorados en macOS

El `.gitignore` excluye `.DS_Store` en cualquier carpeta, archivos AppleDouble (`._*`), metadatos de Finder, configuración personal de editores, credenciales, dependencias y resultados de compilación. También contempla archivos generados de Flutter, Android y Xcode para la futura aplicación.

Se conservan los archivos fuente, las capturas de referencia y los archivos de bloqueo de dependencias de la aplicación cuando se incorporen. Ignorar un archivo no lo elimina del disco.

## Limitaciones y consideraciones

- Los datos y las confirmaciones del prototipo son de demostración.
- La consulta de contenido remoto nuevo y la comunicación entre usuarios requieren conexión.
- Las acciones pendientes deben distinguirse de las confirmadas por el servidor.
- El apoyo comunitario y los ejercicios educativos no sustituyen los canales oficiales de emergencia.
- Este repositorio no establece una licencia de distribución; antes de reutilizar o publicar recursos visuales, revisar sus permisos y procedencia.

## Referencias

- [Guía del equipo](protipo/EQUIPO.md)
- [Sistema de diseño](protipo/calm_civic_humanist/DESIGN.md)
- [Flutter: arquitectura offline](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Drift: documentación](https://drift.simonbinder.eu/)
