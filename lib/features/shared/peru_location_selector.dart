import 'package:flutter/material.dart';

import '../../core/accessibility/text_input_support.dart';
import '../../core/geography/peru_location_catalog.dart';

class PeruLocationSelector extends FormField<PeruLocationSelection> {
  PeruLocationSelector({
    super.key,
    required this.catalog,
    this.value,
    PeruLocationSelection? initialValue,
    this.onChanged,
    this.maxLevel = PeruLocationLevel.district,
    this.isRequired = false,
    super.enabled = true,
    this.fieldKeyPrefix = 'peru_location',
    FormFieldValidator<PeruLocationSelection>? validator,
  }) : super(
         initialValue: catalog.normalize(
           value ?? initialValue ?? const PeruLocationSelection.empty(),
         ),
         autovalidateMode: AutovalidateMode.onUserInteraction,
         validator: (selection) {
           final normalized = catalog.normalize(
             selection ?? const PeruLocationSelection.empty(),
           );
           final chosen = switch (maxLevel) {
             PeruLocationLevel.department => normalized.departmentCode,
             PeruLocationLevel.province => normalized.provinceCode,
             PeruLocationLevel.district => normalized.districtCode,
           };
           final partial = normalized.departmentCode != null && chosen == null;
           if ((isRequired || partial) && chosen == null) {
             return switch (maxLevel) {
               PeruLocationLevel.department => 'Selecciona un departamento.',
               PeruLocationLevel.province =>
                 'Selecciona departamento y provincia.',
               PeruLocationLevel.district =>
                 'Selecciona departamento, provincia y distrito.',
             };
           }
           return validator?.call(normalized);
         },
         builder: (field) => (field as _PeruLocationSelectorState)._build(),
       );

  final PeruLocationCatalog catalog;
  final PeruLocationSelection? value;
  final ValueChanged<PeruLocationSelection>? onChanged;
  final PeruLocationLevel maxLevel;
  final bool isRequired;
  final String fieldKeyPrefix;

  @override
  FormFieldState<PeruLocationSelection> createState() =>
      _PeruLocationSelectorState();
}

class _PeruLocationSelectorState extends FormFieldState<PeruLocationSelection> {
  @override
  PeruLocationSelector get widget => super.widget as PeruLocationSelector;

  @override
  void didUpdateWidget(covariant PeruLocationSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      setValue(widget.catalog.normalize(widget.value!));
    }
  }

  void _change(PeruLocationSelection selection) {
    final next = widget.catalog.normalize(selection);
    didChange(next);
    widget.onChanged?.call(next);
  }

  Future<void> _choose(PeruLocationLevel level) async {
    FocusScope.of(context).unfocus();
    final selected = value ?? const PeruLocationSelection.empty();
    final options = switch (level) {
      PeruLocationLevel.department => widget.catalog.departments,
      PeruLocationLevel.province => widget.catalog.provinces(
        selected.departmentCode,
      ),
      PeruLocationLevel.district => widget.catalog.districts(
        selected.provinceCode,
      ),
    };
    final result = await showModalBottomSheet<PeruLocationEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LocationOptions(level: level, entries: options),
    );
    if (!mounted || result == null || !widget.enabled) return;
    if (level == PeruLocationLevel.department &&
        result.code == selected.departmentCode) {
      return;
    }
    if (level == PeruLocationLevel.province &&
        result.code == selected.provinceCode) {
      return;
    }
    _change(switch (level) {
      PeruLocationLevel.department => PeruLocationSelection(
        departmentCode: result.code,
      ),
      PeruLocationLevel.province => PeruLocationSelection(
        departmentCode: selected.departmentCode,
        provinceCode: result.code,
      ),
      PeruLocationLevel.district => PeruLocationSelection(
        departmentCode: selected.departmentCode,
        provinceCode: selected.provinceCode,
        districtCode: result.code,
      ),
    });
  }

  Widget _build() {
    final selected = value ?? const PeruLocationSelection.empty();
    final catalog = widget.catalog;
    Widget field(
      PeruLocationLevel level,
      String label,
      String? code,
      bool available,
      String hint,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            enabled: widget.enabled && available,
          ),
          child: TextButton(
            key: ValueKey('${widget.fieldKeyPrefix}_${level.name}'),
            onPressed: widget.enabled && available
                ? () => _choose(level)
                : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 56),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    catalog.entry(code)?.name ?? hint,
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(
          PeruLocationLevel.department,
          'Departamento${widget.isRequired ? ' *' : ''}',
          selected.departmentCode,
          true,
          'Elige un departamento',
        ),
        if (widget.maxLevel.index >= PeruLocationLevel.province.index)
          field(
            PeruLocationLevel.province,
            'Provincia',
            selected.provinceCode,
            selected.departmentCode != null,
            'Primero elige un departamento',
          ),
        if (widget.maxLevel == PeruLocationLevel.district)
          field(
            PeruLocationLevel.district,
            'Distrito',
            selected.districtCode,
            selected.provinceCode != null,
            'Primero elige una provincia',
          ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _LocationOptions extends StatefulWidget {
  const _LocationOptions({required this.level, required this.entries});
  final PeruLocationLevel level;
  final List<PeruLocationEntry> entries;
  @override
  State<_LocationOptions> createState() => _LocationOptionsState();
}

class _LocationOptionsState extends State<_LocationOptions> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final options = widget.entries
        .where(
          (entry) =>
              PeruLocationCatalog.searchKey(entry.name)
                  .contains(PeruLocationCatalog.searchKey(_query)),
        )
        .toList();
    final title = switch (widget.level) {
      PeruLocationLevel.department => 'Elegir departamento',
      PeruLocationLevel.province => 'Elegir provincia',
      PeruLocationLevel.district => 'Elegir distrito',
    };
    return FractionallySizedBox(
      heightFactor: .85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Cerrar selector',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('input_location_search'),
              contextMenuBuilder: buildTextSelectionToolbar,
              onTapOutside: dismissTextInput,
              textInputAction: TextInputAction.done,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: 'Buscar por nombre',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () => FocusScope.of(context).unfocus(),
                  tooltip: 'Ocultar teclado',
                  icon: const Icon(Icons.keyboard_hide_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: options.isEmpty
                  ? const Center(child: Text('No se encontraron ubicaciones.'))
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final entry = options[index];
                        return ListTile(
                          key: ValueKey('ubigeo_option_${entry.code}'),
                          minTileHeight: 64,
                          title: Text(entry.name),
                          onTap: () => Navigator.pop(context, entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
