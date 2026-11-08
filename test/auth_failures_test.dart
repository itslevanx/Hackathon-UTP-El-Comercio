import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/features/auth/auth_error_message.dart';
import 'package:hackathon_utp_el_comercio/features/auth/auth_and_onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  test(
    'Errores de red, credenciales y límites se traducen sin filtrar detalles',
    () {
      final network = authErrorMessage(
        AuthRetryableFetchException(
          message: 'SocketException: private-host auth/v1/token',
        ),
      );
      expect(network, contains('conexión'));
      expect(network, isNot(contains('SocketException')));
      expect(network, isNot(contains('private-host')));
      expect(
        authErrorMessage(
          const AuthApiException(
            'Invalid login credentials',
            code: 'invalid_credentials',
            statusCode: '400',
          ),
        ),
        contains('no coinciden'),
      );
      expect(
        authErrorMessage(
          const AuthApiException('private detail', code: 'email_not_confirmed'),
        ),
        contains('Confirma tu correo'),
      );
      expect(
        authErrorMessage(
          const AuthApiException('private detail', statusCode: '429'),
        ),
        contains('Espera unos minutos'),
      );
      expect(
        authErrorMessage(
          StateError(
            'Cuenta creada. Confirma tu correo y luego inicia sesión.',
          ),
        ),
        startsWith('Cuenta creada'),
      );
      expect(
        authErrorMessage(StateError('Private SQL detail')),
        isNot(contains('SQL')),
      );
    },
  );

  testWidgets(
    'Fallo de acceso conserva campos y permite reintentar sin envíos duplicados',
    (tester) async {
      final remote = _FailingAuth();
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      final c = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await c.initialize(startWithActiveSession: false);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AuthAndOnboardingScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('input_auth_email')));
      await tester.enterText(
        find.byKey(const Key('input_auth_email')),
        'prueba@example.test',
      );
      await tester.ensureVisible(find.byKey(const Key('input_auth_password')));
      await tester.enterText(
        find.byKey(const Key('input_auth_password')),
        'password-prueba',
      );
      final submit = find.byKey(const Key('btn_submit_auth'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);
      expect(remote.calls, 1);
      remote.pending.completeError(
        AuthRetryableFetchException(
          message: 'Failed host lookup: private-host',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos conectar'), findsOneWidget);
      expect(find.textContaining('AuthRetryable'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('input_auth_email')))
            .controller!
            .text,
        'prueba@example.test',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('input_auth_password')))
            .controller!
            .text,
        'password-prueba',
      );
      remote.pending = Completer<UserProfile>();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      remote.pending.completeError(
        const AuthApiException(
          'Invalid login credentials',
          code: 'invalid_credentials',
          statusCode: '400',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no coinciden'), findsOneWidget);
      expect(c.currentUser, isNull);
      expect(remote.calls, 2);
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Botones de acceso completos con texto al 200% y pantalla estrecha',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final remote = _FailingAuth();
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      final c = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await c.initialize(startWithActiveSession: false);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AuthAndOnboardingScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      final register = find.byKey(const Key('tab_register_mode'));
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('input_auth_alias')), findsOneWidget);
      expect(find.text('Crear cuenta vecinal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _FailingAuth extends SupabaseRemoteGateway {
  _FailingAuth() : super(forceSupabaseAvailable: false);
  int calls = 0;
  Completer<UserProfile> pending = Completer<UserProfile>();
  @override
  Future<UserProfile> signInAccount({
    required String email,
    required String password,
  }) {
    calls++;
    return pending.future;
  }
}
