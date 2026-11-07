-- =============================================================================
-- Datos demo identificados (is_demo = true) para el escenario piloto:
-- Pueblo Libre, Lima, Perú (y punto externo en San Miguel para prueba de radio)
-- =============================================================================

insert into public.community_resources (
  id, kind, title, description, neighborhood, sector, approx_lat, approx_lng, contact_info, source_label, is_demo
) values
  (
    '10000000-0000-4000-8000-000000000001',
    'punto_encuentro',
    'Plaza Bolívar · Punto de referencia público',
    'Espacio público abierto e iluminado frente al palacio municipal. Lugar sugerido para entrega solidaria de herramientas o encuentro vecinal (condiciones sin confirmar en terreno).',
    'Pueblo Libre',
    'Sector Plaza Bolívar',
    -12.077,
    -77.063,
    'Espacio público abierto',
    'Referencia comunitaria · Demostración Pueblo Libre',
    true
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'punto_encuentro',
    'Parque Candamo · Punto de referencia público',
    'Explanada central y pérgola de encuentro vecinal. Referencia pública sugerida; disponibilidad y seguridad sujetas a verificación presencial.',
    'Pueblo Libre',
    'Sector Sucre / Candamo',
    -12.074,
    -77.065,
    'Frente a Av. Sucre',
    'Referencia comunitaria · Demostración Pueblo Libre',
    true
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    'recurso_comunitario',
    'Botiquín y punto solidario Sector San Martín',
    'Recurso comunitario demostrativo compartido por junta vecinal voluntaria. No garantiza atención médica ni suministro confirmado.',
    'Pueblo Libre',
    'Sector San Martín',
    -12.076,
    -77.061,
    'Coordinación vecinal previa en la app',
    'Dato ficticio de demostración · No confirmado',
    true
  ),
  (
    '10000000-0000-4000-8000-000000000004',
    'directorio_oficial',
    'Canales oficiales de emergencia (Perú)',
    'En situaciones de peligro vital o estructural, comunícate directamente con los servicios públicos oficiales: Central de Emergencias Policiales 105, Bomberos Voluntarios 116, SAMU Atención Médica Móvil 106. Esta app vecinal no despacha unidades de rescate.',
    'Pueblo Libre',
    'Todo el distrito',
    -12.077,
    -77.063,
    '105 Policía · 116 Bomberos · 106 SAMU',
    'Directorio público oficial · INDECI / MINSA / PNP / CGBVP',
    false
  )
on conflict (id) do nothing;

insert into public.support_groups (
  id, name, description, neighborhood, sector, coordinator_label, channel_note, is_demo
) values
  (
    '20000000-0000-4000-8000-000000000001',
    'Brigada Vecinal Solidaria · Sector San Martín',
    'Grupo de apoyo mutuo entre vecinos para recados de farmacia, acompañamiento a personas mayores y préstamo de linternas o herramientas.',
    'Pueblo Libre',
    'Sector San Martín',
    'Coordinación rotativa entre vecinos registrados (Dato de demostración)',
    'Apoyo voluntario entre vecinos · No reemplaza a Defensa Civil ni servicios de emergencia',
    true
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'Red de Cuidado del Adulto Mayor · Parque Candamo',
    'Vecinos voluntarios para caminatas tranquilas, lectura y aviso preventivo ante cortes de servicios básicos.',
    'Pueblo Libre',
    'Sector Sucre / Candamo',
    'Comité vecinal Parque Candamo (Dato de demostración)',
    'Red comunitaria solidaria y gratuita',
    true
  )
on conflict (id) do nothing;
