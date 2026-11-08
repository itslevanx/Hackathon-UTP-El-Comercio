import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/notifications/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Sin configuración de Firebase el servicio no solicita permisos',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final service = PushNotificationService.instance;
      await service.initialize();

      expect(await service.requestPermission(), isNull);
      expect(await service.registerInstallation(), isNull);
      expect(await service.takeInitialMessage(), isNull);
    },
  );
}
