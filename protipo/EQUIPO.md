# NEXO — Guía para continuar el proyecto

Documento de trabajo para el equipo de la hackathon.

## Objetivo

Desarrollar una aplicación para **iPhone y Android** que permita consultar información del barrio, participar en favores vecinales y practicar escenarios de preparación comunitaria. Debe permitir consultar información disponible y guardar acciones **sin conexión a internet**.

## Decisión tecnológica

La base acordada es **Flutter + SQLite con Drift**.

| Componente | Tecnología | Responsabilidad |
|---|---|---|
| Aplicación móvil | Flutter / Dart | Interfaz y navegación para iOS y Android. |
| Datos en el teléfono | SQLite + Drift | Directorio descargado, recursos, borradores y operaciones pendientes. |
| Datos compartidos | API + PostgreSQL | Compartir información entre usuarios cuando haya conexión. |
| Sincronización | Capa por implementar | Enviar pendientes, descargar novedades y resolver duplicados o conflictos. |

La API, su alojamiento y el sistema de autenticación todavía deben definirse. La sincronización no viene resuelta automáticamente por Flutter, SQLite ni Drift.

Para la primera entrega, priorizar la app y el almacenamiento local. Si la sincronización se simula durante la presentación, indicarlo claramente.

## Estado actual del proyecto

- Hay **24 pantallas de referencia en HTML**, con algunos archivos `screen.png`.
- `index.html` abre el prototipo y `prototype.js` conecta sus recorridos.
- El menú **Pantallas** permite acceder directamente a las 24 vistas.
- El prototipo muestra navegación y algunas confirmaciones de demostración.
- **Todavía no es una app Flutter ni implementa funcionamiento offline completo, autenticación o envíos reales.**

Los HTML, las capturas y `calm_civic_humanist/DESIGN.md` sirven como referencia visual. Las pantallas deberán reconstruirse como componentes Flutter.

## Qué significa funcionar offline

La aplicación debe leer y escribir primero en la base local. Internet se utiliza para intercambiar datos con el servidor, sin impedir el uso de las funciones locales.

| Función | Sin conexión | Al recuperar conexión |
|---|---|---|
| Navegar y consultar el perfil local | Disponible. | Actualizar datos si corresponde. |
| Consultar servicios y recursos | Mostrar únicamente contenido descargado o incluido en la instalación. | Descargar novedades. |
| Completar simulacros | Disponible con contenido incluido en la app. | Sincronizar resultados si se decide compartirlos. |
| Crear una solicitud o una oferta | Guardar localmente como pendiente. | Enviar y confirmar recepción. |
| Consultar publicaciones de otros vecinos | Mostrar la última copia descargada y su fecha. | Obtener cambios del servidor. |
| Recibir mensajes o avisos nuevos | No disponible. | Requiere comunicación con el servidor. |

Una solicitud guardada sin conexión **no está enviada ni es visible para otros vecinos**. La interfaz debe distinguir entre **borrador**, **pendiente de enviar**, **enviado** y **error de envío**.

Para una primera apertura sin internet, incluir en la instalación los recursos educativos y datos de demostración necesarios. Los datos reales de la comunidad requieren una descarga previa.

## Alcance recomendado para la hackathon

### Imprescindible

1. Navegación entre inicio, servicios, favores, publicación, perfil y preparación comunitaria.
2. Un directorio de ejemplo almacenado en SQLite.
3. Un recorrido completo: crear una solicitud sin internet, cerrar la app y encontrarla al abrir de nuevo.
4. Un simulacro completo que funcione sin internet.
5. Indicadores visibles de datos guardados y operaciones pendientes.
6. Un botón **Sincronizar** con estados comprensibles. Si usa una simulación, identificarla como tal.

### Después del recorrido principal

- Conectar la API y la base compartida.
- Incorporar autenticación y autorización antes de usar datos privados reales.
- Ampliar el resto de pantallas.
- Incorporar mapas descargables, conversación y notificaciones si el tiempo lo permite.

No bloquear la entrega inicial por chat, mapas completos o notificaciones.

## Organización de la aplicación

Separar cuatro responsabilidades:

- **Pantallas y componentes:** muestran datos y reciben acciones.
- **Lógica de la aplicación:** valida y coordina las operaciones.
- **Repositorios y base local:** consultan y guardan información en SQLite.
- **Cliente de API y sincronización:** intercambian cambios con el servidor.

Las pantallas deben poder funcionar con la base local aunque la API no responda. Una acción del usuario se guarda primero en el dispositivo y, cuando corresponde, se añade a la cola de envío.

## Datos mínimos

| Entidad | Contenido principal |
|---|---|
| Perfil local | Identificador, nombre y barrio. |
| Servicio | Identificador, categoría, descripción y datos públicos de contacto. |
| Publicación | Identificador, autor, tipo, título, descripción, barrio y estado. |
| Oferta de ayuda | Identificador, publicación asociada, autor y mensaje. |
| Recurso comunitario | Identificador, categoría, contenido y fecha de actualización. |
| Resultado de práctica | Identificador, escenario, decisiones y fecha. |
| Operación pendiente | Identificador único de operación, entidad, acción, datos, intentos y estado. |

Usar identificadores que se puedan generar sin conexión. Registrar la versión o revisión del servidor para detectar conflictos; no depender únicamente de la hora del teléfono.

## Reglas de sincronización

1. Guardar el cambio y su operación pendiente en una misma transacción local.
2. Intentar sincronizar al abrir o reanudar la app, al recuperar conexión y mediante el botón manual. La disponibilidad de red no garantiza que la API responda.
3. Conservar los pendientes hasta recibir confirmación del servidor.
4. Reutilizar el mismo identificador de operación en los reintentos para evitar publicaciones duplicadas. La API debe reconocerlo.
5. Mostrar errores y permitir reintentar sin perder el contenido.
6. Detectar cambios concurrentes: para el MVP, conservar la edición local y pedir revisión si el servidor rechaza una versión desactualizada.
7. Separar los datos y pendientes por usuario. No enviar operaciones de una cuenta utilizando la sesión de otra.

No prometer sincronización inmediata con la aplicación cerrada: la ejecución en segundo plano depende de iOS y Android. El recorrido principal debe funcionar con la app abierta.

## Interfaz y accesibilidad

- Mantener letra legible, contraste suficiente y botones amplios.
- Respetar el tamaño de texto configurado en el sistema.
- Explicar los estados con texto, además del color.
- Incluir fuentes, iconos e imágenes esenciales dentro de la aplicación.
- Mostrar cuándo se actualizó la información descargada.
- Presentar los simulacros como contenido educativo y las publicaciones como apoyo vecinal.

## Reparto sugerido del trabajo

| Frente | Entrega |
|---|---|
| Interfaz | Componentes comunes y pantallas del recorrido principal. |
| Datos locales | Esquema Drift, repositorios, datos de ejemplo y persistencia. |
| Integración | Contrato de API, operaciones pendientes y sincronización. |
| Validación y presentación | Pruebas en ambos sistemas y preparación de la demostración. |

Si hay pocas personas, combinar datos locales e integración y reducir el número de pantallas iniciales.

## Criterios de aceptación

- [ ] La aplicación se puede ejecutar en iPhone y Android.
- [ ] El recorrido principal funciona en modo avión.
- [ ] Una solicitud nueva persiste después de cerrar y volver a abrir la app.
- [ ] Las operaciones offline aparecen como pendientes, nunca como enviadas.
- [ ] Un fallo de red no borra los datos ni bloquea la navegación.
- [ ] Un reintento no crea duplicados en el servidor, si hay integración real.
- [ ] Los recursos esenciales no necesitan descargarse durante la demostración.
- [ ] La sincronización real o simulada se identifica correctamente.
- [ ] Los botones de regreso y las salidas de los simulacros funcionan.
- [ ] Se comprueba el diseño con texto ampliado.

Para compilar y probar la versión iOS, preparar una Mac con Xcode. Acordar temprano cómo se instalará la aplicación en los dispositivos de demostración.

## Guion de demostración

1. Abrir la app y mostrar el directorio local.
2. Activar modo avión.
3. Consultar un recurso y completar un simulacro.
4. Crear una solicitud: debe indicar **Pendiente de enviar**.
5. Cerrar y abrir la app para comprobar que sigue guardada.
6. Recuperar internet y pulsar **Sincronizar**.
7. Mostrar la confirmación real del servidor o explicar que es una simulación.

## Primeros pasos del equipo

1. Crear el proyecto Flutter y comprobar que arranca en ambos sistemas.
2. Configurar Drift y guardar una publicación de ejemplo.
3. Construir el recorrido principal con los diseños existentes.
4. Validar persistencia y modo avión antes de ampliar funcionalidades.
5. Definir el contrato de API y decidir si la demo incluirá sincronización real.

## Documentación de referencia

- [Flutter: arquitectura offline](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Flutter: recomendaciones de arquitectura](https://docs.flutter.dev/app-architecture/recommendations)
- [Drift: documentación](https://drift.simonbinder.eu/)
- [Drift: plataformas compatibles](https://drift.simonbinder.eu/platforms/)
