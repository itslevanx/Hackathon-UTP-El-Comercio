import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Solo se presentan textos propios. Las excepciones pueden contener URLs,
/// detalles de red u otros datos que no deben llegar al formulario.
String authErrorMessage(Object error) {
  if (error is AuthRetryableFetchException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return 'No pudimos conectar con el barrio. Revisa tu conexión o prueba otra red y vuelve a intentarlo. Tus datos siguen en el formulario.';
  }
  if (error is AuthException) {
    if (error.statusCode == '429' ||
        error.code == 'over_request_rate_limit' ||
        error.code == 'over_email_send_rate_limit') {
      return 'Hubo demasiados intentos. Espera unos minutos y vuelve a intentarlo.';
    }
    return switch (error.code) {
      'invalid_credentials' => 'El correo o la contraseña no coinciden. Revísalos y vuelve a intentarlo.',
      'email_not_confirmed' => 'Confirma tu correo antes de iniciar sesión.',
      'user_already_exists' || 'email_exists' =>
        'Ya existe una cuenta con ese correo. Intenta iniciar sesión.',
      'otp_expired' || 'flow_state_expired' || 'flow_state_not_found' =>
        'El enlace venció o ya se usó. Solicita otro correo de recuperación.',
      'same_password' => 'Elige una contraseña diferente de la anterior.',
      'session_expired' || 'session_not_found' || 'bad_jwt' => 'Tu sesión venció. Vuelve a iniciar sesión o solicita otro enlace de recuperación.',
      'weak_password' =>
        'Elige una contraseña más segura y vuelve a intentarlo.',
      'signup_disabled' || 'email_provider_disabled' =>
        'El registro no está disponible en este momento. Inténtalo más tarde.',
      _ =>
        'No pudimos completar el acceso. Vuelve a intentarlo en unos momentos.',
    };
  }
  if (error is StateError && _localMessages.contains(error.message)) {
    return error.message.toString();
  }
  return 'No pudimos completar la operación. Tus datos siguen en el formulario; vuelve a intentarlo.';
}

const _localMessages = {
  'Ingresa un correo electrónico válido.',
  'Ingresa tu contraseña.',
  'La nueva contraseña debe tener al menos 8 caracteres.',
  'Abre un enlace de recuperación válido para cambiar tu contraseña.',
  'Ingresa tu nombre o alias vecinal (mínimo 2 letras).',
  'La contraseña debe tener al menos 6 caracteres.',
  'Cuenta creada. Confirma tu correo y luego inicia sesión.',
  'Selecciona un distrito reconocido en el catálogo INEI.',
  'Sin conexión. Inicia sesión cuando recuperes internet.',
};
