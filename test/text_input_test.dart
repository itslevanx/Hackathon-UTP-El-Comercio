import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

Future<AppController> pumpAuthForm(WidgetTester tester) async {
  final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false);
  final database = LocalSqliteDatabase(
    engine: InMemoryTransactionalStoreEngine(),
  );
  final controller = AppController(
    database: database,
    remoteGateway: remote,
    outboxSyncService: OutboxSyncService(
      database: database,
      remoteGateway: remote,
    ),
  );
  await controller.initialize(startWithActiveSession: false);
  controller.navigateTo(AppSection.autenticacion);
  await tester.pumpWidget(
    Conecta2App(
      appController: controller,
      accessibilityController: AccessibilityController(),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  return controller;
}

EditableTextState editableState(WidgetTester tester, String key) =>
    tester.state<EditableTextState>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  testWidgets('Copiar y pegar entre campos no abre menús nativos simultáneos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.supportsShowingSystemContextMenu = true;
    addTearDown(
      tester.platformDispatcher.resetSupportsShowingSystemContextMenu,
    );
    var clipboard = '';
    var nativeMenus = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method.startsWith('ContextMenu.')) nativeMenus++;
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': clipboard.isNotEmpty};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpAuthForm(tester);
    final email = find.byKey(const Key('input_auth_email'));
    await tester.ensureVisible(email);
    await tester.enterText(email, 'vecino@example.com');
    final emailState = editableState(tester, 'input_auth_email');
    emailState.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 18,
    );
    emailState.showToolbar();
    await tester.pumpAndSettle();
    expect(find.byType(SystemContextMenu), findsNothing);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, 'vecino@example.com');

    final register = find.byKey(const Key('tab_register_mode'));
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    final alias = find.byKey(const Key('input_auth_alias'));
    await tester.ensureVisible(alias);
    await tester.enterText(alias, 'Vecino');
    final aliasState = editableState(tester, 'input_auth_alias');
    aliasState.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 6,
    );
    aliasState.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(aliasState.widget.controller.text, 'vecino@example.com');
    expect(emailState.widget.controller.text, 'vecino@example.com');
    expect(nativeMenus, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'Ocultar teclado conserva el texto y deslizar también lo cierra',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await pumpAuthForm(tester);
      final email = find.byKey(const Key('input_auth_email'));
      await tester.ensureVisible(email);
      await tester.enterText(email, 'vecino@example.com');
      final state = editableState(tester, 'input_auth_email');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(state.widget.focusNode.hasFocus, isTrue);
      await tester.tap(find.byKey(const Key('btn_hide_keyboard')));
      await tester.pumpAndSettle();
      expect(state.widget.focusNode.hasFocus, isFalse);
      expect(state.widget.controller.text, 'vecino@example.com');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_hide_keyboard')), findsNothing);
      await tester.ensureVisible(email);
      await tester.showKeyboard(email);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(state.widget.focusNode.hasFocus, isFalse);
      expect(state.widget.controller.text, 'vecino@example.com');
      await tester.ensureVisible(email);
      await tester.showKeyboard(email);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conecta2'));
      await tester.pumpAndSettle();
      expect(state.widget.focusNode.hasFocus, isFalse);
      expect(state.widget.controller.text, 'vecino@example.com');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
