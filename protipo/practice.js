/* Motor local de práctica: sin red, sin personas reales y sin escrituras al backend. */
(() => {
  'use strict';
  const scenarios = {
    sismo: ['Sismo en el barrio', 'El movimiento ya terminó. En este escenario ficticio estás en un lugar seguro y puedes usar el teléfono.', 'Necesito apoyo para llegar a un punto de encuentro'],
    lluvia: ['Lluvias intensas en el barrio', 'En este escenario ficticio estás en una zona segura. Una calle está anegada y necesitas coordinar apoyo sin acercarte al agua.', 'Necesito apoyo por una calle anegada'],
    servicios: ['Corte de agua y luz', 'En este escenario ficticio se interrumpieron el agua y la electricidad. Estás a salvo y quieres pedir un recurso a tu comunidad.', 'Necesito agua para mi hogar']
  };
  const scenario = new URLSearchParams(location.search).get('scenario');
  const [name, context, example] = scenarios[scenario] || scenarios.sismo;
  const screen = document.getElementById('screen');
  const instruction = document.getElementById('instruction');
  const feedback = document.getElementById('feedback');
  const connection = document.getElementById('connection');
  let stage = 'report', sent = false, clicks = 0;
  document.getElementById('title').textContent = name;
  document.getElementById('context').textContent = context;
  function render(html, task) {
    screen.innerHTML = html; instruction.textContent = task; feedback.textContent = '';
    const heading = screen.querySelector('h2');
    if (heading) { heading.tabIndex = -1; heading.focus(); }
  }
  function button(label, fn, kind = '') {
    const b = document.createElement('button'); b.textContent = label; b.type = 'button'; b.className = kind;
    b.addEventListener('click', () => { clicks++; fn(); }); screen.append(b); return b;
  }
  function home() {
    clicks = 0;
    render('<h2>Inicio de la app · práctica</h2><p>Pueblo Libre · zona aproximada</p>', stage === 'report' ? 'Misión 1: reporta una necesidad de apoyo. Usa el acceso de emergencia.' : stage === 'offline' ? 'Misión 3: la conexión simulada se perdió. Crea otra solicitud y observa qué ocurre.' : 'Misión 2: encuentra una solicitud ficticia y ofrece ayuda.');
    button('Reportar emergencia', () => form('emergency'), 'urgent');
    button('Necesito ayuda', () => form('help'));
    button('Ver favores y ayudar', offers, 'secondary');
  }
  function form(kind) {
    render(`<h2>${kind === 'emergency' ? 'Reportar emergencia' : 'Necesito ayuda'}</h2><p>Zona: Pueblo Libre. No publiques tu dirección exacta.</p><form id="report-form"><label for="report-title">¿Qué necesitas?</label><input id="report-title" required maxlength="120" autocomplete="off"><label for="report-detail">Detalles (opcional)</label><textarea id="report-detail"></textarea><button type="submit">Enviar solicitud de práctica</button></form>`, 'Escribe tu necesidad y envíala. El texto no suma clics al recorrido.');
    document.getElementById('report-title').placeholder = example;
    screen.querySelector('form').addEventListener('submit', e => {
      e.preventDefault(); clicks++;
      if (!document.getElementById('report-title').value.trim()) { feedback.textContent = 'Escribe qué necesitas.'; return; }
      if (stage === 'offline') {
        render('<h2>Pendiente de envío · NO comunicada</h2><p>La solicitud permanece solo en este ejercicio. Ningún vecino la ha recibido.</p>', 'Sin conexión, guardar no significa comunicar. En una emergencia real busca ayuda por los canales oficiales disponibles.');
        button('Restablecer conexión simulada', () => {
          connection.textContent = 'Conexión simulada restablecida';
          render('<h2>Solicitud pendiente</h2><p>Ahora puedes intentar enviarla.</p>', 'Confirma el envío en la app de práctica.');
          button('Reintentar envío de práctica', finish);
        });
      } else if (stage === 'report') {
        sent = true;
        render('<h2>Reporte simulado comunicado</h2><p>Estado de práctica: abierto. No hay envío real ni despacho de ayuda.</p>', `Completaste la primera misión en ${clicks} clics desde el inicio simulado.`);
        button('Practicar cómo ofrecer ayuda', () => { stage = 'offer'; home(); });
      } else {
        feedback.textContent = 'En esta misión debes abrir “Ver favores y ayudar”. Vuelve al inicio de práctica.';
        button('Volver al inicio de práctica', home, 'secondary');
      }
    });
    button('Volver al inicio de práctica', home, 'secondary');
  }
  function offers() {
    render('<h2>Solicitudes ficticias</h2><p>Carmen necesita una linterna. Está en una zona segura y pide un préstamo.</p>', 'Abre la solicitud para leer el contexto antes de ofrecer ayuda.');
    button('Ver solicitud de Carmen', () => {
      render('<h2>Una linterna para Carmen</h2><p>Sector San Martín · zona aproximada. Préstamo gratuito. Coordina sin exponerte a un peligro.</p><label for="offer-note">Nota opcional</label><textarea id="offer-note" placeholder="Puedo prestar una linterna"></textarea>', 'Lee la solicitud y confirma tu oferta.');
      button('Enviar oferta de práctica', () => {
        if (stage !== 'offer') {
          feedback.textContent = 'Tu misión actual es publicar una solicitud. Regresa al inicio para intentarlo.';
          button('Volver al inicio de práctica', home, 'secondary'); return;
        }
        render('<h2>Oferta simulada registrada</h2><p>Carmen (personaje ficticio): “Gracias, coordinemos en el punto público acordado”.</p>', `Ofreciste ayuda en ${clicks} clics desde el inicio simulado. En la app real continuarías por el chat privado.`);
        button('Practicar pérdida de conexión', () => { stage = 'offline'; connection.textContent = 'Sin conexión · estado simulado'; home(); });
      });
    });
    button('Volver al inicio de práctica', home, 'secondary');
  }
  function finish() {
    render('<h2>Práctica completada</h2><p>Aprendiste a reportar, ofrecer ayuda y distinguir una solicitud pendiente de una comunicada.</p><p>En una situación real, usa la app desde un lugar seguro. El apoyo comunitario no sustituye a los servicios oficiales.</p>', sent ? 'Todas las acciones fueron ficticias y permanecieron dentro del ejercicio.' : 'Puedes repetir el ejercicio cuando quieras.');
    button('Repetir práctica', () => { stage = 'report'; sent = false; connection.textContent = 'Conexión simulada disponible'; home(); });
    const a = document.createElement('a'); a.href = '3._inicio_hola_rosa/code.html'; a.textContent = 'Salir al inicio'; screen.append(a);
  }
  home();
})();
