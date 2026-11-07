import 'package:flutter/material.dart';

// Evita la colisión entre menús nativos de iOS al cambiar de campo.
// Conserva las acciones de selección, copiar y pegar de cada plataforma.
Widget buildTextSelectionToolbar(
  BuildContext context,
  EditableTextState editableTextState,
) => AdaptiveTextSelectionToolbar.editableText(
  editableTextState: editableTextState,
);

void dismissTextInput(PointerDownEvent event) {
  FocusManager.instance.primaryFocus?.unfocus();
}

class KeyboardDismissibleBody extends StatelessWidget {
  const KeyboardDismissibleBody({
    super.key,
    required this.child,
    required this.keyboardVisible,
  });

  final Widget child;
  final bool keyboardVisible;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        if (keyboardVisible)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TextButton.icon(
              key: const Key('btn_hide_keyboard'),
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              icon: const Icon(Icons.keyboard_hide_outlined),
              label: const Text('Ocultar teclado'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
            ),
          ),
      ],
    );
  }
}
