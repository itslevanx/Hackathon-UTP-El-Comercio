import Flutter
import VoiceBridge
public class Conecta2VoicePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Retain the bridge's translation unit for Dart FFI symbol lookup.
        _ = conecta_voice_version()
    }
}
