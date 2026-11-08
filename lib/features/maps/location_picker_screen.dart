import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/accessibility/text_input_support.dart';
import '../../core/geography/peru_location_catalog.dart';
import '../../core/maps/address_lookup_service.dart';
import '../../core/maps/carto_basemap.dart';
import '../../core/maps/chosen_map_location.dart';
import '../../core/maps/map_location_service.dart';
import '../shared/peru_location_selector.dart';
import 'neighborhood_map.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.catalog,
    this.initialPoint,
    this.districtUbigeo,
    this.allowExactService = false,
    this.lookup,
    this.locationService,
  });
  final PeruLocationCatalog catalog;
  final LatLng? initialPoint;
  final String? districtUbigeo;
  final bool allowExactService;
  final AddressLookupService? lookup;
  final MapLocationService? locationService;
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _address = TextEditingController();
  final _form = GlobalKey<FormState>();
  late PeruLocationSelection _zone;
  LatLng? _point;
  LatLng? _center;
  List<LatLng> _matches = [];
  bool _chosen = false, _busy = false, _shareExact = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _zone = widget.catalog.selectionForDistrict(widget.districtUbigeo);
    final district = widget.catalog.district(_zone.districtCode);
    _point =
        widget.initialPoint ??
        approximateMapPoint(district?.capitalLat, district?.capitalLng);
    _center = _point;
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _select(LatLng point, {bool recenter = false}) {
    setState(() {
      _point = point;
      if (recenter) _center = point;
      _chosen = true;
      _error = null;
    });
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    if (_address.text.trim().isEmpty) {
      setState(() => _error = 'Escribe una dirección o mueve el pin.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _matches = [];
    });
    try {
      final district = widget.catalog.district(_zone.districtCode)!;
      final area =
          '${district.name}, ${widget.catalog.entry(district.provinceCode)!.name}';
      final matches = await (widget.lookup ?? AddressLookupService()).search(
        _address.text,
        area,
      );
      if (!mounted) return;
      setState(() => _matches = matches);
      if (matches.length == 1) _select(matches.single, recenter: true);
      if (matches.isEmpty) {
        setState(
          () => _error = 'No se encontró la dirección. Puedes tocar el mapa o arrastrar el pin.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo buscar la dirección. Revisa tu conexión o coloca el pin en el mapa.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gps() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final point = await (widget.locationService ?? MapLocationService())
          .locate();
      if (!mounted) return;
      if (point == null) {
        setState(
          () => _error =
              'No se obtuvo ubicación. Puedes tocar el mapa sin usar GPS.',
        );
      } else {
        _select(point, recenter: true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se obtuvo ubicación. Puedes colocar el pin manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (!_chosen || _point == null) {
      setState(
        () => _error = 'Toca el mapa, mueve el pin o busca una dirección para confirmar el punto.',
      );
      return;
    }
    Navigator.pop(
      context,
      ChosenMapLocation(
        point: _point!,
        districtUbigeo: _zone.districtCode!,
        shareExactService: widget.allowExactService && _shareExact,
        address: widget.allowExactService && _shareExact
            ? _address.text.trim()
            : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Elegir ubicación')),
    body: SafeArea(
      child: SingleChildScrollView(
        key: const Key('location_picker_scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Toca el mapa o arrastra el pin. Verifica que corresponda al distrito elegido.',
              ),
              const SizedBox(height: 12),
              PeruLocationSelector(
                catalog: widget.catalog,
                value: _zone,
                enabled: !_busy,
                isRequired: true,
                onChanged: (zone) => setState(() {
                  _zone = zone;
                  _chosen = false;
                  _matches = [];
                  final district = widget.catalog.district(zone.districtCode);
                  _point = approximateMapPoint(
                    district?.capitalLat,
                    district?.capitalLng,
                  );
                  _center = _point;
                }),
              ),
              TextField(
                key: const Key('input_location_address'),
                enabled: !_busy,
                controller: _address,
                maxLength: 300,
                contextMenuBuilder: buildTextSelectionToolbar,
                onTapOutside: dismissTextInput,
                decoration: const InputDecoration(
                  labelText: 'Dirección o lugar de referencia',
                  hintText: 'Calle, número y distrito',
                ),
              ),
              const Text(
                'Al buscar, la dirección se consulta con el proveedor de ubicaciones del teléfono. Verifica el resultado antes de guardarlo.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('btn_search_location_address'),
                    onPressed: _busy ? null : _search,
                    icon: const Icon(Icons.search),
                    label: Text(_busy ? 'Buscando…' : 'Buscar dirección'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _gps,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Usar mi ubicación'),
                  ),
                ],
              ),
              for (var i = 0; i < _matches.length && _matches.length > 1; i++)
                OutlinedButton(
                  onPressed: () => _select(_matches[i], recenter: true),
                  child: Text('Ver resultado ${i + 1} en el mapa'),
                ),
              NeighborhoodMap(
                records: const [],
                center: _center,
                onSelect: (_) {},
                selectionPoint: _point,
                onSelectPoint: _busy ? null : _select,
              ),
              if (widget.allowExactService)
                CheckboxListTile(
                  key: const Key('checkbox_share_exact_service'),
                  contentPadding: EdgeInsets.zero,
                  value: _shareExact,
                  onChanged: (value) =>
                      setState(() => _shareExact = value ?? false),
                  title: const Text(
                    'Compartir el punto y la dirección exactos como lugar de atención de mi servicio',
                  ),
                  subtitle: const Text(
                    'Los vecinos con sesión podrán verlos. Actívalo solo para una dirección que quieras hacer pública.',
                  ),
                )
              else
                const Text(
                  'El perfil y las solicitudes guardan el punto aproximado. La dirección buscada no se publica ni se guarda en el perfil.',
                ),
              if (!_shareExact)
                const Text(
                  'Se guardará una zona aproximada, no la ubicación exacta.',
                ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('btn_confirm_location_point'),
                onPressed: _busy ? null : _save,
                child: const Text('Usar este punto'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
