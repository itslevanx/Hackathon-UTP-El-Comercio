import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/features/auth/auth_error_message.dart';
import 'package:hackathon_utp_el_comercio/features/auth/password_recovery_screen.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

Future<AppController> _create(_RecoveryGateway gateway) async {
  final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
  final c = AppController(
    database: db,
    remoteGateway: gateway,
    outboxSyncService: OutboxSyncService(database: db, remoteGateway: gateway),
  );
  await c.initialize(startWithActiveSession: false);
  return c;
}

Future<void> tap(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  testWidgets(
    'Botón de recuperación reutiliza correo, oculta contraseña y confirma sin enumerar cuentas',
    (tester) async {
      final remote = _RecoveryGateway();
      final c = await _create(remote);
      addTearDown(c.dispose);
      c.navigateTo(AppSection.autenticacion);
      await tester.pumpWidget(
        NexoNeighborhoodApp(
          appController: c,
          accessibilityController: AccessibilityController(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('input_auth_email')));
      await tester.enterText(
        find.byKey(const Key('input_auth_email')),
        '  Prueba@example.test  ',
      );
      await tap(tester, 'btn_forgot_password');
      expect(find.byKey(const Key('input_auth_password')), findsNothing);
      await tap(tester, 'btn_submit_auth');
      expect(remote.requestedEmail, 'prueba@example.test');
      expect(find.textContaining('Si existe una cuenta'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('btn_submit_auth')))
            .onPressed,
        isNull,
      );
      expect(c.currentUser, isNull);
      await tap(tester, 'btn_back_from_recovery_request');
      expect(find.byKey(const Key('input_auth_password')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('Correo inválido no envía; fallo de red no crea sesión', () async {
    final remote = _RecoveryGateway();
    final c = await _create(remote);
    addTearDown(c.dispose);
    await expectLater(c.requestPasswordReset('incorrecto'), throwsStateError);
    expect(remote.requests, 0);
    remote.fail = true;
    await expectLater(
      c.requestPasswordReset('prueba@example.test'),
      throwsA(isA<AuthRetryableFetchException>()),
    );
    expect(c.currentUser, isNull);
    expect(
      authErrorMessage(const AuthApiException('secret', code: 'otp_expired')),
      contains('venció'),
    );
  });
  testWidgets(
    'Enlace validado abre nueva contraseña y conserva cola sin guardar contraseñas',
    (tester) async {
      final remote = _RecoveryGateway();
      final c = await _create(remote);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        NexoNeighborhoodApp(
          appController: c,
          accessibilityController: AccessibilityController(),
        ),
      );
      remote.openLink();
      await tester.pumpAndSettle();
      expect(find.byType(PasswordRecoveryScreen), findsOneWidget);
      expect(find.text('Inicio'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('input_recovery_password')),
        'contraseña-prueba',
      );
      await tester.enterText(
        find.byKey(const Key('input_recovery_confirmation')),
        'otra-contraseña',
      );
      await tap(tester, 'btn_save_recovered_password');
      expect(find.textContaining('no coinciden'), findsOneWidget);
      expect(remote.updates, 0);
      await tester.enterText(
        find.byKey(const Key('input_recovery_password')),
        'corta',
      );
      await tester.enterText(
        find.byKey(const Key('input_recovery_confirmation')),
        'corta',
      );
      await tap(tester, 'btn_save_recovered_password');
      expect(find.textContaining('al menos 8'), findsWidgets);
      expect(remote.updates, 0);
      await tester.enterText(
        find.byKey(const Key('input_recovery_password')),
        'contraseña-prueba',
      );
      await tester.enterText(
        find.byKey(const Key('input_recovery_confirmation')),
        'contraseña-prueba',
      );
      await tap(tester, 'btn_save_recovered_password');
      expect(remote.updates, 1);
      expect(c.passwordRecoveryPending, isFalse);
      expect(c.currentUser?.id, 'recovered-user');
      expect(c.statusBannerMessage, 'Contraseña actualizada.');
      expect(await c.database.listOutboxForUser('recovered-user'), isEmpty);
      expect(c.userDrafts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('No cambia contraseña con sesión normal y acepta recuperación emitida antes de inicializar', () async {
    final remote = _RecoveryGateway();
    final c = await _create(remote);
    addTearDown(c.dispose);
    await expectLater(
      c.completePasswordRecovery('contraseña-prueba'),
      throwsStateError,
    );
    expect(remote.updates, 0);
    final cold = _RecoveryGateway()..linkBeforeListen = true;
    final restored = await _create(cold);
    addTearDown(restored.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(restored.passwordRecoveryPending, isTrue);
  });
  testWidgets(
    'Cancelar recuperación y texto ampliado permiten volver al acceso',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final remote = _RecoveryGateway();
      final c = await _create(remote);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        NexoNeighborhoodApp(
          appController: c,
          accessibilityController: AccessibilityController(),
        ),
      );
      remote.openLink();
      await tester.pumpAndSettle();
      await tap(tester, 'btn_cancel_recovery');
      expect(c.passwordRecoveryPending, isFalse);
      expect(c.currentUser, isNull);
      expect(c.currentSection, AppSection.autenticacion);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _RecoveryGateway extends SupabaseRemoteGateway {
  _RecoveryGateway() : super(forceSupabaseAvailable: false);
  final events = StreamController<void>.broadcast();
  bool recovering = false,
      linkBeforeListen = false,
      fail = false,
      completed = false;
  int requests = 0, updates = 0;
  String? requestedEmail;
  @override
  bool get hasPasswordRecoverySession => recovering;
  @override
  Stream<void> get passwordRecoveryChanges async* {
    if (linkBeforeListen) {
      recovering = true;
      yield null;
    }
    yield* events.stream;
  }

  void openLink() {
    recovering = true;
    events.add(null);
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    requests++;
    if (fail) throw AuthRetryableFetchException();
    requestedEmail = email;
  }

  @override
  Future<void> updateRecoveredPassword(String password) async {
    if (!recovering) throw StateError('Sin sesión de recuperación');
    updates++;
    recovering = false;
    completed = true;
  }

  @override
  Future<UserProfile?> getCurrentSessionProfile() async => completed
      ? UserProfile(
          id: 'recovered-user',
          alias: 'Vecino',
          email: 'prueba@example.test',
          neighborhood: 'Pueblo Libre',
          sector: 'Referencia',
          updatedAt: DateTime.utc(2026),
        )
      : null;
  @override
  Future<void> signOutAccount() async {
    recovering = false;
    completed = false;
  }
}
