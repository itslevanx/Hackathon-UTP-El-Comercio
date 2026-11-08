import 'package:flutter/material.dart';

import '../../core/accessibility/text_input_support.dart';
import '../../core/state/app_controller.dart';
import 'auth_error_message.dart';

/// Solo se presenta tras una sesión de recuperación validada por Supabase.
/// La contraseña permanece en memoria y nunca entra en SQLite ni en la cola.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_password.text != _confirmation.text) {
      setState(
        () => _error = 'Las contraseñas no coinciden. Vuelve a escribirlas.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.completePasswordRecovery(_password.text);
      _password.clear();
      _confirmation.clear();
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.signOut();
      widget.controller.navigateTo(AppSection.autenticacion);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.all(20),
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Elige una nueva contraseña',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Usa al menos 8 caracteres. No necesitas recordar la contraseña anterior.',
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('input_recovery_password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            contextMenuBuilder: buildTextSelectionToolbar,
            onTapOutside: dismissTextInput,
            decoration: const InputDecoration(labelText: 'Nueva contraseña'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('input_recovery_confirmation'),
            controller: _confirmation,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            contextMenuBuilder: buildTextSelectionToolbar,
            onTapOutside: dismissTextInput,
            decoration: const InputDecoration(
              labelText: 'Repite la nueva contraseña',
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('btn_save_recovered_password'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Guardando…' : 'Guardar nueva contraseña'),
          ),
          TextButton(
            key: const Key('btn_cancel_recovery'),
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancelar y volver al acceso'),
          ),
        ],
      ),
    ),
  );
}
