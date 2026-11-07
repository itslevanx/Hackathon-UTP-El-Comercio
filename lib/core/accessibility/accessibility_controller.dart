import 'package:flutter/material.dart';

/// Controlador de accesibilidad para personas mayores:
/// - Soporta el conmutador rápido `A / A+` (escala adicional 1.22x) sin
///   desactivar ni recortar la escala de texto configurada en el sistema
///   operativo (compatible con 200% o más de ampliación).
/// - Respeta la preferencia de reducir movimiento del sistema o manual.
class AccessibilityController extends ChangeNotifier {
  bool _largeTextEnabled = false;
  bool _reduceMotionOverride = false;
  bool _dismissedBriefTutorial = false;

  bool get isLargeTextEnabled => _largeTextEnabled;
  double get userTextScaleMultiplier => userScaleMultiplier;
  bool effectiveReduceMotion(bool system) => system || _reduceMotionOverride;

  bool get largeTextEnabled => _largeTextEnabled;
  bool get reduceMotionOverride => _reduceMotionOverride;
  bool get dismissedBriefTutorial => _dismissedBriefTutorial;

  double get userScaleMultiplier => _largeTextEnabled ? 1.22 : 1.0;

  void toggleLargeText() {
    _largeTextEnabled = !_largeTextEnabled;
    notifyListeners();
  }

  void setLargeText(bool enabled) {
    if (_largeTextEnabled == enabled) return;
    _largeTextEnabled = enabled;
    notifyListeners();
  }

  void setReduceMotionOverride(bool enabled) {
    if (_reduceMotionOverride == enabled) return;
    _reduceMotionOverride = enabled;
    notifyListeners();
  }

  void dismissBriefTutorial() {
    if (_dismissedBriefTutorial) return;
    _dismissedBriefTutorial = true;
    notifyListeners();
  }

  void reopenBriefTutorial() {
    _dismissedBriefTutorial = false;
    notifyListeners();
  }

  /// Combina la escala del sistema operativo con el ajuste A/A+ sin bloquear
  /// escalas de 200% o superiores.
  TextScaler effectiveTextScaler(BuildContext context) {
    final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
    final combined = systemScale * userScaleMultiplier;
    return TextScaler.linear(combined);
  }

  bool isReducedMotionActive(BuildContext context) {
    final platformReduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return platformReduced || _reduceMotionOverride;
  }
}
