import '../../core/accessibility/text_input_support.dart';

import 'package:flutter/material.dart';

import '../../core/database/local_sqlite_database.dart';
import '../../core/models/domain_models.dart';
import '../../core/theme/app_theme.dart';
import '../shared/civic_widgets.dart';

/// Definición de cada escenario local de simulacro (100% disponible en modo avión
/// desde la primera instalación).
class PracticeScenarioConfig {
  const PracticeScenarioConfig({
    required this.id,
    required this.title,
    required this.shortLabel,
    required this.indeciGuidance,
    required this.fictionalNeighborAlias,
    required this.fictionalSector,
    required this.fictionalReportTitle,
    required this.fictionalReportDescription,
    required this.defaultEmergencyDraftTitle,
    required this.defaultEmergencyDraftDescription,
    required this.deterministicChatReply,
  });

  final String id;
  final String title;
  final String shortLabel;
  final String indeciGuidance;
  final String fictionalNeighborAlias;
  final String fictionalSector;
  final String fictionalReportTitle;
  final String fictionalReportDescription;
  final String defaultEmergencyDraftTitle;
  final String defaultEmergencyDraftDescription;
  final String deterministicChatReply;
}

/// Catálogo de los 3 escenarios diferenciados requeridos por el encargo.
const List<PracticeScenarioConfig> kPracticeScenarios = [
  PracticeScenarioConfig(
    id: 'sismo',
    title: 'Sismo fuerte en el barrio',
    shortLabel: 'Sismo en el barrio',
    indeciGuidance: 'Esta práctica comienza después del movimiento, cuando ya estás en una zona segura. Sigue las indicaciones de las autoridades. Practica cómo pedir apoyo vecinal sin exponerte a peligros.',
    fictionalNeighborAlias: 'Doña Rosa (76 años · Datos ficticios)',
    fictionalSector: 'Sector Parque Candamo (Ubicación aproximada)',
    fictionalReportTitle: '[SIMULACRO] Adulta mayor solicita linterna para iluminar su zona segura',
    fictionalReportDescription: 'Reporte ficticio de práctica: Doña Rosa está en la vereda frente al Parque Candamo y necesita una linterna para permanecer en su zona segura.',
    defaultEmergencyDraftTitle:
        'Práctica: Necesito botiquín básico en Sector Sucre',
    defaultEmergencyDraftDescription:
        'Reporte de prueba en simulacro para practicar envío en 2 clics.',
    deterministicChatReply: 'Respuesta automática de práctica de Doña Rosa: "¡Gracias vecino! Te espero frente a la pérgola iluminada del Parque Candamo." (Nota educativa: en una emergencia real la respuesta depende de la conexión y disponibilidad del vecino).',
  ),
  PracticeScenarioConfig(
    id: 'lluvia',
    title: 'Lluvia intensa o aniego en la cuadra',
    shortLabel: 'Lluvia intensa o inundación',
    indeciGuidance: 'Esta práctica comienza desde una zona seca y segura. Evita acercarte al agua acumulada, a cables y a instalaciones eléctricas mojadas. Practica cómo coordinar recursos sin entrar a una zona peligrosa.',
    fictionalNeighborAlias: 'Don Ernesto (70 años · Datos ficticios)',
    fictionalSector: 'Sector Plaza Bolívar (Ubicación aproximada)',
    fictionalReportTitle: '[SIMULACRO] Apoyo con escobillones para retirar agua acumulada en entrada',
    fictionalReportDescription: 'Reporte ficticio de práctica: ingreso de agua de lluvia al pasadizo del primer piso cerca de Plaza Bolívar.',
    defaultEmergencyDraftTitle:
        'Práctica: Solicito plástico protector y baldes en Plaza Bolívar',
    defaultEmergencyDraftDescription:
        'Reporte de prueba en simulacro de lluvia intensa.',
    deterministicChatReply: 'Respuesta automática de práctica de Don Ernesto: "¡Muchas gracias! Estoy en una zona seca y segura. Coordinemos cuando sea seguro." (En un caso real la respuesta depende de la señal y del vecino).',
  ),
  PracticeScenarioConfig(
    id: 'servicios',
    title: 'Corte prolongado de agua o electricidad',
    shortLabel: 'Corte de agua o electricidad',
    indeciGuidance: 'Guía MINSA / Defensa Civil: 1) Prioriza el agua potable hervida o embotellada para adultos mayores y niños. 2) Evita usar velas encendidas sin vigilancia (riesgo de incendio: usa linternas). 3) Usa la app para compartir carga de batería o bidones de agua en tu cuadra.',
    fictionalNeighborAlias: 'Familia Gómez (Datos ficticios)',
    fictionalSector: 'Sector San Martín (Ubicación aproximada)',
    fictionalReportTitle: '[SIMULACRO] Necesitamos 2 litros de agua potable para preparar medicinas',
    fictionalReportDescription: 'Reporte ficticio de práctica: corte de agua en el sector; requieren agua hervida para adulto mayor.',
    defaultEmergencyDraftTitle: 'Práctica: Comparto batería portátil cargada para celulares de emergencia',
    defaultEmergencyDraftDescription:
        'Reporte de prueba en simulacro de corte de servicios básicos.',
    deterministicChatReply: 'Respuesta automática de práctica de Familia Gómez: "¡Gracias por tu solidaridad! Llevamos un envase limpio al punto de encuentro del parque." (En un caso real la respuesta depende de la conexión).',
  ),
];

/// Repositorio en memoria 100% aislado para el modo Simulacro.
/// Garantiza CERO escrituras en las tablas reales (`publications_local`,
/// `outbox_operations`, etc.) y CERO tráfico hacia Supabase.
class PracticeIsolatedRepository extends ChangeNotifier {
  PracticeIsolatedRepository({PracticeScenarioConfig? initialScenario})
    : _scenario = initialScenario ?? kPracticeScenarios.first {
    _resetScenarioState();
  }

  PracticeScenarioConfig _scenario;
  PracticeScenarioConfig get scenario => _scenario;

  bool _practiceStarted = false;
  bool get practiceStarted => _practiceStarted;

  bool _simulatedOffline = false;
  bool get simulatedOffline => _simulatedOffline;

  bool _mission1Recognized = false;
  bool get mission1Recognized => _mission1Recognized;

  bool _mission2ReportedInTwoClicks = false;
  bool get mission2ReportedInTwoClicks => _mission2ReportedInTwoClicks;

  bool _mission3OfferedAndChatted = false;
  bool get mission3OfferedAndChatted => _mission3OfferedAndChatted;

  bool _mission4OfflineQueuedAndRetried = false;
  bool get mission4OfflineQueuedAndRetried => _mission4OfflineQueuedAndRetried;

  bool _mission5ResolvedWithFeedback = false;
  bool get mission5ResolvedWithFeedback => _mission5ResolvedWithFeedback;

  late Publication _fictionalNeighborPublication;
  Publication get fictionalNeighborPublication => _fictionalNeighborPublication;

  final List<Publication> _practiceUserPublications = <Publication>[];
  List<Publication> get practiceUserPublications =>
      List.unmodifiable(_practiceUserPublications);

  final List<String> _practiceOutboxIds = <String>[];
  List<String> get practiceOutboxIds => List.unmodifiable(_practiceOutboxIds);

  final List<String> _practiceChatMessages = <String>[];
  List<String> get practiceChatMessages =>
      List.unmodifiable(_practiceChatMessages);

  int get completedMissionsCount {
    var count = 0;
    if (_mission1Recognized) count++;
    if (_mission2ReportedInTwoClicks) count++;
    if (_mission3OfferedAndChatted) count++;
    if (_mission4OfflineQueuedAndRetried) count++;
    if (_mission5ResolvedWithFeedback) count++;
    return count;
  }

  List<String> get completedMissionIds {
    return [
      if (_mission1Recognized) 'mision_1_reconocer',
      if (_mission2ReportedInTwoClicks) 'mision_2_reportar_2_clics',
      if (_mission3OfferedAndChatted) 'mision_3_ofrecer_y_chat',
      if (_mission4OfflineQueuedAndRetried) 'mision_4_offline_sin_duplicados',
      if (_mission5ResolvedWithFeedback) 'mision_5_resolver_actividad',
    ];
  }

  void selectScenario(PracticeScenarioConfig newScenario) {
    _scenario = newScenario;
    _resetScenarioState();
    notifyListeners();
  }

  void startPractice() {
    _practiceStarted = true;
    notifyListeners();
  }

  void _resetScenarioState() {
    final now = DateTime.now().toUtc();
    _fictionalNeighborPublication = Publication(
      id: 'prac-pub-${_scenario.id}-vecino',
      clientMutationId: 'prac-mut-${_scenario.id}-vecino',
      ownerUserId: 'practice_sandbox',
      authorId: 'practice-neighbor',
      authorAlias: _scenario.fictionalNeighborAlias,
      kind: PublicationKind.emergenciaSolicitud,
      category: 'emergencia_practica',
      title: _scenario.fictionalReportTitle,
      description: _scenario.fictionalReportDescription,
      neighborhood: 'Pueblo Libre (Simulacro)',
      sector: _scenario.fictionalSector,
      availabilityText: 'Simulacro educativo sin alerta real',
      priority: PublicationPriority.emergencia,
      status: PublicationStatus.abierta,
      approxLat: -12.075,
      approxLng: -77.064,
      syncStatus: SyncStatus.confirmado,
      isDemo: true,
      createdAt: now,
      updatedAt: now,
    );
    _practiceUserPublications.clear();
    _practiceOutboxIds.clear();
    _practiceChatMessages.clear();
    _simulatedOffline = false;
    _mission1Recognized = false;
    _mission2ReportedInTwoClicks = false;
    _mission3OfferedAndChatted = false;
    _mission4OfflineQueuedAndRetried = false;
    _mission5ResolvedWithFeedback = false;
  }

  /// Misión 1: Reconocer reporte ficticio y su ubicación aproximada por sector.
  void completeMission1RecognizeReport() {
    _mission1Recognized = true;
    notifyListeners();
  }

  /// Misión 2 y Misión 4: Crear reporte de emergencia ficticio dentro de la caja
  /// de arena aislada. Si [_simulatedOffline] es true, queda como
  /// `SyncStatus.pendiente` ("Pendiente de envío / NO comunicada") con llave
  /// idempotente.
  Publication submitPracticeReport({
    required String title,
    required String description,
    String? idempotencyKey,
  }) {
    final now = DateTime.now().toUtc();
    final mutId =
        idempotencyKey ??
        'prac-mut-${_scenario.id}-${_simulatedOffline ? "offline" : "online"}';

    // Idempotencia: si ya existe con el mismo clientMutationId, no duplicar
    final existingIdx = _practiceUserPublications.indexWhere(
      (p) => p.clientMutationId == mutId,
    );

    final status = _simulatedOffline
        ? SyncStatus.pendiente
        : SyncStatus.confirmado;

    final pub = Publication(
      id: existingIdx >= 0
          ? _practiceUserPublications[existingIdx].id
          : 'prac-user-pub-${_practiceUserPublications.length + 1}',
      clientMutationId: mutId,
      ownerUserId: 'practice_sandbox',
      authorId: 'practice-user',
      authorAlias: 'Tú (En modo práctica)',
      kind: PublicationKind.emergenciaSolicitud,
      category: 'emergencia_practica',
      title: title.trim().isEmpty
          ? _scenario.defaultEmergencyDraftTitle
          : title.trim(),
      description: description.trim().isEmpty
          ? _scenario.defaultEmergencyDraftDescription
          : description.trim(),
      neighborhood: 'Pueblo Libre (Simulacro)',
      sector: _scenario.fictionalSector,
      priority: PublicationPriority.emergencia,
      status: PublicationStatus.abierta,
      approxLat: -12.075,
      approxLng: -77.064,
      syncStatus: status,
      isDemo: true,
      createdAt: now,
      updatedAt: now,
    );

    if (existingIdx >= 0) {
      _practiceUserPublications[existingIdx] = pub;
    } else {
      _practiceUserPublications.add(pub);
    }

    if (_simulatedOffline) {
      if (!_practiceOutboxIds.contains(mutId)) {
        _practiceOutboxIds.add(mutId);
      }
    } else {
      _mission2ReportedInTwoClicks = true;
    }

    notifyListeners();
    return pub;
  }

  /// Misión 3: Ofrecer ayuda al vecino ficticio y coordinar en el chat local
  /// determinista sin red.
  void offerHelpAndSendPracticeChat(String userMessage) {
    final clean = userMessage.trim().isEmpty
        ? 'Hola vecino, tengo linterna y botiquín para apoyarte en el punto de encuentro.'
        : userMessage.trim();
    _fictionalNeighborPublication = _fictionalNeighborPublication.copyWith(
      status: PublicationStatus.enCoordinacion,
      updatedAt: DateTime.now().toUtc(),
    );
    _practiceChatMessages.add('Tú (Práctica): $clean');
    _practiceChatMessages.add(_scenario.deterministicChatReply);
    _mission3OfferedAndChatted = true;
    notifyListeners();
  }

  /// Misión 4: Alternar pérdida de conexión simulada y reintentar cola aislada
  /// sin duplicar registros.
  void setSimulatedOffline(bool offline) {
    _simulatedOffline = offline;
    notifyListeners();
  }

  void retryPracticeOfflineQueueIdempotent() {
    _simulatedOffline = false;
    for (var i = 0; i < _practiceUserPublications.length; i++) {
      final item = _practiceUserPublications[i];
      if (item.syncStatus == SyncStatus.pendiente) {
        _practiceUserPublications[i] = item.copyWith(
          syncStatus: SyncStatus.confirmado,
          updatedAt: DateTime.now().toUtc(),
        );
      }
    }
    _practiceOutboxIds.clear();
    _mission4OfflineQueuedAndRetried = true;
    notifyListeners();
  }

  /// Misión 5: Marcar la actividad de práctica como `resuelta` y recibir
  /// retroalimentación final.
  void markPracticeActivityResolved() {
    _fictionalNeighborPublication = _fictionalNeighborPublication.copyWith(
      status: PublicationStatus.resuelta,
      updatedAt: DateTime.now().toUtc(),
    );
    for (var i = 0; i < _practiceUserPublications.length; i++) {
      _practiceUserPublications[i] = _practiceUserPublications[i].copyWith(
        status: PublicationStatus.resuelta,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    _mission5ResolvedWithFeedback = true;
    notifyListeners();
  }
}

/// Pantalla completa de Simulacros Interactivos Offline.
/// Respeta:
/// - Presupuesto de clics desde Inicio: `Practicar una emergencia` (1) ->
///   elegir escenario si se cambia (2) -> `Iniciar práctica` (máximo 3).
/// - Banda permanente `PRÁCTICA — DATOS FICTICIOS` y botón `Salir de la práctica`.
/// - Las 5 misiones interactivas completas sin tocar tablas reales ni Supabase.
class PracticeSimulatorScreen extends StatefulWidget {
  const PracticeSimulatorScreen({
    super.key,
    required this.database,
    required this.onExitPractice,
  });

  final LocalSqliteDatabase database;
  final VoidCallback onExitPractice;

  @override
  State<PracticeSimulatorScreen> createState() =>
      _PracticeSimulatorScreenState();
}

class _PracticeSimulatorScreenState extends State<PracticeSimulatorScreen> {
  late final PracticeIsolatedRepository _repo;
  bool _openingTwoClickReportForm = false;

  final TextEditingController _reportTitleCtrl = TextEditingController();
  final TextEditingController _reportDescCtrl = TextEditingController();
  final TextEditingController _chatCtrl = TextEditingController(
    text: 'Puedo compartir una linterna desde mi zona segura.',
  );

  @override
  void initState() {
    super.initState();
    _repo = PracticeIsolatedRepository();
    _syncDefaultDraftTexts();
  }

  void _syncDefaultDraftTexts() {
    _reportTitleCtrl.text = _repo.scenario.defaultEmergencyDraftTitle;
    _reportDescCtrl.text = _repo.scenario.defaultEmergencyDraftDescription;
  }

  @override
  void dispose() {
    _reportTitleCtrl.dispose();
    _reportDescCtrl.dispose();
    _chatCtrl.dispose();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _persistIsolatedPracticeProgress() async {
    await widget.database.savePracticeProgress(
      _repo.scenario.id,
      _repo.completedMissionIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banda inequívoca SIEMPRE visible durante el simulacro
            Container(
              key: const Key('banner_practica_datos_ficticios'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: AppTheme.practiceBlue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'PRÁCTICA',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Datos ficticios · No se envían avisos',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  TextButton.icon(
                    key: const Key('btn_salir_de_la_practica'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: widget.onExitPractice,
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Salir'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                child: !_repo.practiceStarted
                    ? _buildScenarioSelectorLanding()
                    : _buildInteractiveMissionsWorkspace(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Pantalla inicial del simulacro: permite elegir escenario (Clic 2 opcional)
  /// y tocar `Iniciar práctica` (Clic 2 o Clic 3 máximo desde Inicio).
  Widget _buildScenarioSelectorLanding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.practiceBlue, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Entrenamiento Vecinal: Practica cómo usar la app en una emergencia',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige un escenario local y toca "Iniciar práctica". Todo lo que publiques o respondas aquí ocurre con datos ficticios y nunca sale de tu teléfono.',
                style: TextStyle(
                  fontSize: 17,
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              for (final sc in kPracticeScenarios) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    key: Key('card_scenario_${sc.id}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      _repo.selectScenario(sc);
                      _syncDefaultDraftTexts();
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _repo.scenario.id == sc.id
                            ? AppTheme.practiceSurface
                            : AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _repo.scenario.id == sc.id
                              ? AppTheme.practiceBlue
                              : AppTheme.borderSoft,
                          width: _repo.scenario.id == sc.id ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _repo.scenario.id == sc.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: AppTheme.practiceBlue,
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sc.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sc.fictionalReportTitle,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: ElevatedButton.icon(
                  key: const Key('btn_iniciar_practica'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.practiceBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _repo.startPractice(),
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text(
                    'Iniciar práctica',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const OfficialEmergencyChannelsCard(),
      ],
    );
  }

  /// Espacio interactivo con las 5 misiones obligatorias sobre componentes reales.
  Widget _buildInteractiveMissionsWorkspace() {
    final sc = _repo.scenario;
    final neighborPub = _repo.fictionalNeighborPublication;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selector rápido para cambiar de escenario en cualquier momento
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.practiceSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.practiceBlue, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Escenario activo: ${sc.title}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.practiceBlue,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Misiones: ${_repo.completedMissionsCount} / 5',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.practiceBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                sc.indeciGuidance,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textPrimary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in kPracticeScenarios)
                    ChoiceChip(
                      key: Key('chip_active_scenario_${option.id}'),
                      label: Text(option.shortLabel),
                      selected: sc.id == option.id,
                      onSelected: (_) {
                        _repo.selectScenario(option);
                        _repo.startPractice();
                        _syncDefaultDraftTexts();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // MISIÓN 1: Reconocer reporte ficticio en su zona y ubicación aproximada
        _buildMissionContainer(
          missionNumber: 1,
          title: 'Misión 1: Reconocer un reporte ficticio en tu zona y su ubicación aproximada',
          completed: _repo.mission1Recognized,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        PublicationStatusBadge(status: neighborPub.status),
                        SyncStatusBadge(
                          status: neighborPub.syncStatus,
                          isEmergency: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      neighborPub.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vecino: ${neighborPub.authorAlias} · ${neighborPub.sector}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.practiceBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      neighborPub.description,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: ElevatedButton.icon(
                  key: const Key('btn_mission1_recognize'),
                  onPressed: () {
                    _repo.completeMission1RecognizeReport();
                    _persistIsolatedPracticeProgress();
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text(
                    'Reconozco el reporte ficticio y su ubicación aproximada',
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // MISIÓN 2: Reportar necesidad de emergencia en 2 clics desde el inicio de la práctica
        _buildMissionContainer(
          missionNumber: 2,
          title: 'Misión 2: Reportar una necesidad de emergencia en 2 clics (estado ficticio comunicado)',
          completed: _repo.mission2ReportedInTwoClicks,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_openingTwoClickReportForm)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: ElevatedButton.icon(
                    key: const Key('btn_practice_reportar_emergencia_step1'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.urgentRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        setState(() => _openingTwoClickReportForm = true),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Clic 1: Reportar emergencia (Práctica)'),
                  ),
                )
              else ...[
                TextField(
                  contextMenuBuilder: buildTextSelectionToolbar,
                  onTapOutside: dismissTextInput,
                  key: const Key('input_practice_report_title'),
                  controller: _reportTitleCtrl,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: '¿Qué necesitas reportar en esta práctica?',
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: ElevatedButton.icon(
                    key: const Key('btn_practice_enviar_reporte_step2'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.urgentRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      _repo.setSimulatedOffline(false);
                      _repo.submitPracticeReport(
                        title: _reportTitleCtrl.text,
                        description: _reportDescCtrl.text,
                        idempotencyKey: 'prac-mission2-${sc.id}',
                      );
                      _persistIsolatedPracticeProgress();
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Clic 2: Enviar reporte (Práctica)'),
                  ),
                ),
              ],
              if (_repo.mission2ReportedInTwoClicks) ...[
                const SizedBox(height: 10),
                const SyncStatusBadge(
                  status: SyncStatus.confirmado,
                  isEmergency: true,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // MISIÓN 3: Abrir solicitud ficticia, ofrecer recurso y coordinar por chat de práctica
        _buildMissionContainer(
          missionNumber: 3,
          title: 'Misión 3: Ofrecer ayuda o recurso al vecino ficticio y coordinar por chat local',
          completed: _repo.mission3OfferedAndChatted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                contextMenuBuilder: buildTextSelectionToolbar,
                onTapOutside: dismissTextInput,
                key: const Key('input_practice_chat_message'),
                controller: _chatCtrl,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText:
                      'Mensaje de coordinación para ${sc.fictionalNeighborAlias}',
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: ElevatedButton.icon(
                  key: const Key('btn_mission3_offer_and_chat'),
                  onPressed: () {
                    _repo.offerHelpAndSendPracticeChat(_chatCtrl.text);
                    _persistIsolatedPracticeProgress();
                  },
                  icon: const Icon(Icons.volunteer_activism),
                  label: const Text(
                    'Ofrecer ayuda y enviar mensaje en chat de práctica',
                  ),
                ),
              ),
              if (_repo.practiceChatMessages.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final msg in _repo.practiceChatMessages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.practiceSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        msg,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // MISIÓN 4: Simular pérdida de conexión, observar "Pendiente de envío / NO comunicada", restaurar y reintentar sin duplicados
        _buildMissionContainer(
          missionNumber: 4,
          title: 'Misión 4: Simular pérdida de conexión, ver "Pendiente de envío / NO comunicada" y reintentar sin duplicados',
          completed: _repo.mission4OfflineQueuedAndRetried,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    key: const Key('btn_mission4_simulate_offline_request'),
                    onPressed: () {
                      _repo.setSimulatedOffline(true);
                      _repo.submitPracticeReport(
                        title: 'Solicitud en simulacro sin señal',
                        description:
                            'Prueba de guardado local cuando se cae internet.',
                        idempotencyKey: 'prac-mission4-offline-${sc.id}',
                      );
                    },
                    icon: const Icon(Icons.cloud_off),
                    label: const Text(
                      '1. Cortar señal simulada y crear solicitud',
                    ),
                  ),
                  ElevatedButton.icon(
                    key: const Key('btn_mission4_restore_and_retry'),
                    onPressed: () {
                      // Reintentamos también el envío con la misma llave para demostrar 0 duplicados
                      _repo.submitPracticeReport(
                        title: 'Solicitud en simulacro sin señal',
                        description:
                            'Prueba de guardado local cuando se cae internet.',
                        idempotencyKey: 'prac-mission4-offline-${sc.id}',
                      );
                      _repo.retryPracticeOfflineIdempotentAndComplete();
                      _persistIsolatedPracticeProgress();
                    },
                    icon: const Icon(Icons.wifi),
                    label: const Text(
                      '2. Restaurar conexión y reintentar (sin duplicar)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_repo.simulatedOffline || _repo.practiceOutboxIds.isNotEmpty)
                Container(
                  key: const Key('badge_mission4_pending_not_communicated'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.amberWarning),
                  ),
                  child: const Text(
                    'Estado actual: Pendiente de envío / NO comunicada (Guardada en cola local de práctica, 0 alertas enviadas).',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.amberWarning,
                    ),
                  ),
                ),
              if (_repo.mission4OfflineQueuedAndRetried)
                Container(
                  key: const Key('badge_mission4_retried_no_duplicates'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF7E8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.actionGreen),
                  ),
                  child: Text(
                    'Conexión simulada restaurada: solicitud sincronizada sin duplicados (Total publicaciones únicas en práctica: ${_repo.practiceUserPublications.length}).',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.actionGreen,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // MISIÓN 5: Actualizar estado a resuelta y recibir retroalimentación final
        _buildMissionContainer(
          missionNumber: 5,
          title: 'Misión 5: Actualizar el estado de la actividad a "Resuelta" y ver retroalimentación final',
          completed: _repo.mission5ResolvedWithFeedback,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: ElevatedButton.icon(
                  key: const Key('btn_mission5_mark_resolved'),
                  onPressed: () {
                    _repo.markPracticeActivityResolved();
                    _persistIsolatedPracticeProgress();
                  },
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Marcar actividad como Resuelta'),
                ),
              ),
              if (_repo.mission5ResolvedWithFeedback) ...[
                const SizedBox(height: 12),
                Container(
                  key: const Key('card_mission5_final_feedback'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF7E8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.actionGreen, width: 2),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¡Simulacro completado con éxito!',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.actionGreen,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '• Aprendiste a reconocer la ubicación por sector aproximado.\n'
                        '• Reportaste una necesidad en 2 clics desde el inicio.\n'
                        '• Coordinaste ayuda solidaria y verificaste qué ocurre cuando se corta internet ("Pendiente de envío / NO comunicada").\n'
                        '• Recuerda siempre: ante urgencia médica o rescate llama al 105 (Policía), 116 (Bomberos), 106 (SAMU) o 115 (INDECI).',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMissionContainer({
    required int missionNumber,
    required String title,
    required bool completed,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completed ? AppTheme.actionGreen : AppTheme.borderSoft,
          width: completed ? 2 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                completed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: completed ? AppTheme.actionGreen : AppTheme.practiceBlue,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

extension _PracticeRetryExt on PracticeIsolatedRepository {
  void retryPracticeOfflineIdempotentAndComplete() {
    retryPracticeOfflineQueueIdempotent();
  }
}
