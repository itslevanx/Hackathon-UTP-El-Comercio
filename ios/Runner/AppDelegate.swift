import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexoMapIdentity")!
    let channel = FlutterMethodChannel(
      name: "pe.vecinos.app/map_identity",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "headers" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let identifier = Bundle.main.bundleIdentifier else {
        result(FlutterError(code: "missing_bundle", message: "Identificador no disponible", details: nil))
        return
      }
      result(["X-Ios-Bundle-Identifier": identifier])
    }
  }
}
