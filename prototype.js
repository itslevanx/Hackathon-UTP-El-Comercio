/* Navegación del prototipo. No realiza envíos ni llamadas a servicios. */
(() => {
  'use strict';
  const routes = {"1": "1._bienvenida_nexo/code.html", "2": "2._registro_por_barrio/code.html", "3": "3._inicio_hola_rosa/code.html", "4": "4._explorar_servicios/code.html", "5": "5._detalle_de_servicio_luis_alberto/code.html", "6": "6._recomendar_servicio_confirmaci_n/code.html", "7": "7._cadena_de_favores_pueblo_libre/code.html", "8": "8._publicaci_n_r_pida_en_el_barrio/code.html", "9": "9._detalle_de_solicitud_do_a_carmen/code.html", "10": "10._confirmar_oferta_pueblo_libre/code.html", "11": "11._red_de_apoyo_vecinal/code.html", "12": "12._mapa_de_zonas_y_recursos/code.html", "13": "13._perfil_vecinal_do_a_rosa/code.html", "14": "14._modo_sin_conexi_n_informaci_n_guardada/code.html", "15": "15._tablero_de_estados_ui/code.html", "16": "16._selector_de_simulacro_prep_rate_con_tu_comunidad/code.html", "17": "17._sismo_decisi_n_1_durante_el_movimiento/code.html", "18": "18._sismo_retroalimentaci_n_educativa_1/code.html", "19": "19._sismo_decisi_n_2_apoyo_vecinal_seguro/code.html", "20": "20._red_de_apoyo_simulada_solicitudes_ficticias/code.html", "21": "21._detalle_simulado_oferta_registrada_ficticia/code.html", "22": "22._resultado_pr_ctica_completada/code.html", "23": "23._inundaci_n_lluvias_intensas_y_zonas_seguras/code.html", "24": "24._corte_de_servicios_pr_ctica_sin_conexi_n/code.html"};
  const labels = ["Bienvenida", "Registro por barrio", "Inicio", "Explorar servicios", "Detalle de servicio", "Recomendar servicio", "Cadena de favores", "Publicar en el barrio", "Solicitud de Carmen", "Confirmar oferta", "Red de apoyo vecinal", "Mapa de zonas y recursos", "Perfil de Rosa", "Información sin conexión", "Estados del prototipo", "Elegir simulacro", "Sismo: primera decisión", "Sismo: aprendizajes", "Sismo: apoyo vecinal", "Solicitudes simuladas", "Oferta simulada", "Resultado de la práctica", "Lluvias intensas", "Corte de agua y luz"];
  const base = new URL('.', document.currentScript.src);
  const url = id => new URL(routes[id], base).href;
  const current = Number(decodeURIComponent(location.pathname).split('/').findLast(part => /^\d+\._/.test(part))?.split('.')[0]);
  const go = id => location.assign(url(id));
  // Capture only connected controls so their former placeholder actions do not run.
  const targets = new WeakMap();
  function connect(element, target) {
    if (!element) return;
    if (typeof target === 'number') {
      element.dataset.screen = target;
      if (element.tagName === 'A') element.href = url(target);
    }
    const bound = targets.has(element);
    targets.set(element, target);
    if (bound) return;
    element.addEventListener('click', event => {
      const target = targets.get(element);
      if (element.disabled) return;
      if (element.tagName === 'A' && (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      typeof target === 'function' ? target() : go(target);
    }, true);
  }
  const byId = (id, target) => connect(document.getElementById(id), target);
  const text = (phrase, target) => document.querySelectorAll('button, a').forEach(el => {
    if (el.textContent.replace(/\s+/g, ' ').trim().includes(phrase)) connect(el, target);
  });
  const back = {2:1,5:4,6:5,7:3,8:3,9:7,10:9,11:3,13:3,15:13,16:11,17:16,18:17,19:18,20:19,21:20,22:21,23:16,24:16};
  document.querySelectorAll('button[aria-label="Perfil de Rosa"]').forEach(el => connect(el, 13));
  document.querySelectorAll('[data-path]').forEach(el => {
    const section = [4,5,6].includes(current) ? 'explorar' : [7,9,10].includes(current) ? 'favores' : current === 8 ? 'publicar' : current === 13 ? 'perfil' : 'inicio';
    el.removeAttribute('aria-current');
    el.classList.remove('text-secondary','bg-surface-container-low','font-label-md');
    if (el.dataset.path === section) {
      el.setAttribute('aria-current','page');
      el.classList.add('text-secondary','bg-surface-container-low','font-label-md');
    }
  });
  document.querySelectorAll('button,a').forEach(el => {
    if (/Volver|Cancelar y volver|Deshacer \/ Volver/.test(el.textContent) && back[current]) connect(el, back[current]);
    if (el.getAttribute('aria-label') === 'Salir de la práctica') connect(el, 11);
  });
  switch (current) {
    case 1: byId('btn-comenzar',2); byId('btn-login',3); break;
    case 2: byId('continue-button',3); break;
    case 3:
      text('Pueblo Libre (Sector',2); text('Buscar',4); text('Explorar oficios',4);
      text('Participar en la cadena',7); text('Ver red comunitaria',11);
      text('Ver servicio / Contactar',5); text('Ver perfil',5);
      text('Responder a Carmen',9); text('Publicar pedido',8); break;
    case 4: text('Ver perfil y opiniones',5); break;
    case 5: byId('btn-recomendar',6); break;
    case 6: text('Entendido, volver al inicio',3); break;
    case 7: text('Pedir o brindar un favor',8); text('Responder',9); text('Ver detalle del favor',9); break;
    case 8: text('Cambiar',2); text('Ver mi publicación en Favores',7); break;
    case 9: byId('btn-ofrecer',10); break;
    case 10:
      // La pantalla de conversación no forma parte de este prototipo.
      document.querySelectorAll('button').forEach(el => {
        if (el.textContent.includes('Ver conversación con Carmen')) {
          el.innerHTML = '<span class="material-symbols-outlined">volunteer_activism</span> Volver a Favores';
          connect(el,7);
        }
      }); break;
    case 11:
      text('Necesito ayuda barrial',8); text('Puedo ofrecer ayuda hoy',8);
      text('Ver recursos y directorios',12); text('Iniciar ejercicio guiado',16);
      text('Ver detalles',9); text('Ofrecer mano',10); break;
    case 12: text('Ver solicitudes en este sector',7); text('Ver detalles y voluntariados',11); break;
    case 13:
      text('Cambiar barrio',2); text('Favor en curso',9); text('recomendación hecha',5);
      text('Mis notas y borradores',14); text('Cerrar sesión',1); break;
    case 14: byId('edit-draft-btn',8); break;
    case 15:
      text('Ver todos los oficios',4); text('Publicar el primer pedido',8);
      text('Reintentar conexión ahora',3); text('Usar información guardada',14);
      text('Volver a la pantalla de Inicio',3); text('Continuar al directorio',4); break;
    case 16:
      byId('btn-iniciar', () => {
        const selected = document.querySelector('.scenario-card[aria-checked="true"]');
        go(selected?.id === 'card-lluvia' ? 23 : selected?.id === 'card-servicios' ? 24 : 17);
      }); break;
    case 17: byId('submit-btn',18); break;
    case 18: text('Continuar a la siguiente',19); text('Repetir esta pregunta',17); break;
    case 19: byId('btn-confirm',20); break;
    case 20: text('Seleccionar para ayudar',21); break;
    case 21: text('Ver resultado y aprendizajes',22); text('Volver a la lista',20); break;
    case 22:
      text('Volver a practicar este escenario',17); text('Explorar otra situación',16);
      text('Volver a la pantalla principal',3); break;
    case 23:
      // Se conserva la confirmación existente y se ofrece una salida al selector.
      addLink(document.getElementById('solidarity-confirmation'), 'Elegir otro escenario',16); break;
    case 24: text('Finalizar ejercicio y volver al selector',16); break;
  }
  function addLink(parent, label, target) {
    if (!parent) return;
    const link = document.createElement('a');
    link.href = url(target); link.textContent = label;
    link.style.cssText = 'display:block;padding:12px;font-weight:600;text-decoration:underline;color:inherit';
    parent.append(link);
  }
  // Acceso directo a las 24 pantallas, también a los estados de demostración.
  const style = document.createElement('style');
  style.textContent = `#prototype-menu{position:fixed;z-index:80;right:12px;bottom:calc(92px + env(safe-area-inset-bottom,0px));font:14px/1.4 Inter,system-ui,sans-serif;color:#183d32}#prototype-menu summary{cursor:pointer;list-style:none;background:#fff;border:1px solid #c1c8c4;border-radius:24px;padding:10px 16px;box-shadow:0 2px 8px #183d321a}#prototype-menu summary:focus-visible,#prototype-menu a:focus-visible{outline:3px solid #106c4c}#prototype-menu nav{position:absolute;bottom:48px;right:0;width:min(310px,calc(100vw - 24px));max-height:60vh;overflow:auto;background:white;border:1px solid #c1c8c4;border-radius:12px;padding:8px;box-shadow:0 6px 24px #183d3226}#prototype-menu a{display:block;padding:10px;border-radius:8px;text-decoration:none;color:inherit}#prototype-menu a:hover,#prototype-menu a[aria-current]{background:#e7f8ee}`;
  document.head.append(style);
  const menu = document.createElement('details'); menu.id = 'prototype-menu';
  const summary = document.createElement('summary'); summary.textContent = 'Pantallas'; menu.append(summary);
  const nav = document.createElement('nav'); nav.setAttribute('aria-label','Pantallas del prototipo');
  labels.forEach((label,index) => {
    const link = document.createElement('a'); link.href = url(index+1); link.textContent = `${index+1}. ${label}`;
    if (current === index+1) link.setAttribute('aria-current','page');
    nav.append(link);
  });
  menu.append(nav); document.body.append(menu);
  document.addEventListener('click',event => { if (!menu.contains(event.target)) menu.open = false; });
  document.addEventListener('keydown',event => { if (event.key === 'Escape') { menu.open = false; summary.focus(); } });
})();
