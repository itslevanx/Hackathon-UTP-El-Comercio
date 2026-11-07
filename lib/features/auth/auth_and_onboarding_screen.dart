import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';

/// Pantalla de registro, inicio de sesión, cambio de cuenta, cierre de sesión
/// y configuración de zona manual / ubicación opcional por GPS.
/// Cumple las reglas del encargo:
/// - Nunca bloquea a quien rechaza el permiso de ubicación GPS (permite elegir
///   barrio o sector manualmente).
/// - Si el usuario llegó aquí por una acción que requería sesión, muestra la
///   intención conservada y la retoma automáticamente al autenticarse.
class AuthAndOnboardingScreen extends StatefulWidget {
  const AuthAndOnboardingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuthAndOnboardingScreen> createState() =>
      _AuthAndOnboardingScreenState();
}

class _AuthAndOnboardingScreenState extends State<AuthAndOnboardingScreen> {
  bool _isRegisterMode = false;

  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _selectedDistrict = AppConfig.defaultNeighborhood;
  String _selectedSector = AppConfig.defaultSector;
  bool _useOptionalGps = false;
  double? _gpsLat;
  double? _gpsLng;
  bool _requestingGps = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDistrict = widget.controller.activeNeighborhood;
    _selectedSector = widget.controller.activeSector;
    _useOptionalGps = widget.controller.currentUser?.useGpsApprox ?? false;
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  NeighborhoodZone get _currentZoneConfig {
    final zones =
        AppConfig.zonesByDistrict[_selectedDistrict] ??
        AppConfig.zonesByDistrict[AppConfig.defaultNeighborhood]!;
    final matched = zones.where((z) => z.sector == _selectedSector).toList();
    return matched.isNotEmpty ? matched.first : zones.first;
  }

  Future<void> _toggleGps(bool enabled) async {
    if (!enabled) {
      setState(() {
        _useOptionalGps = false;
        _gpsLat = null;
        _gpsLng = null;
      });
      return;
    }
    setState(() {
      _requestingGps = true;
      _errorMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
          'Activa la ubicación del teléfono o elige tu zona manualmente.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Puedes continuar eligiendo tu barrio manualmente.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _gpsLat = AppConfig.roundPublicCoordinate(position.latitude);
        _gpsLng = AppConfig.roundPublicCoordinate(position.longitude);
        _useOptionalGps = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _useOptionalGps = false;
          _errorMessage = 'No se obtuvo ubicación. Puedes continuar con el barrio elegido manualmente.';
        });
      }
    } finally {
      if (mounted) setState(() => _requestingGps = false);
    }
  }

  Future<void> _handleAuthSubmit() async {
    setState(() => _errorMessage = null);
    try {
      final zone = _currentZoneConfig;
      if (_isRegisterMode) {
        await widget.controller.registerAndSignIn(
          alias: _aliasController.text,
          email: _emailController.text,
          password: _passwordController.text,
          neighborhood: zone.district,
          sector: zone.sector,
          approxLat: _useOptionalGps
              ? (_gpsLat ?? zone.centerLat)
              : zone.centerLat,
          approxLng: _useOptionalGps
              ? (_gpsLng ?? zone.centerLng)
              : zone.centerLng,
          useGpsApprox: _useOptionalGps,
        );
      } else {
        await widget.controller.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  Future<void> _handleSaveLocationOnly() async {
    final zone = _currentZoneConfig;
    await widget.controller.updateLocationPreference(
      neighborhood: zone.district,
      sector: zone.sector,
      approxLat: _useOptionalGps ? (_gpsLat ?? zone.centerLat) : zone.centerLat,
      approxLng: _useOptionalGps ? (_gpsLng ?? zone.centerLng) : zone.centerLng,
      useGpsApprox: _useOptionalGps,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zona actualizada a ${zone.district} · ${zone.sector}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final user = c.currentUser;
    final pendingIntent = c.pendingAuthIntent;
    final districts = AppConfig.zonesByDistrict.keys.toList();
    final sectorsForDistrict =
        AppConfig.zonesByDistrict[_selectedDistrict] ??
        AppConfig.zonesByDistrict[AppConfig.defaultNeighborhood]!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendingIntent != null) ...[
            Container(
              key: const Key('banner_pending_auth_intent'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.amberWarning, width: 1.5),
              ),
              child: Text(
                'Acción en espera: "${pendingIntent.description}". Inicia sesión o regístrate para retomarla inmediatamente.',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.amberWarning,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Si ya hay sesión activa, permite cambiar de cuenta o cerrar sesión
          if (user != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.actionGreen, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sesión activa: ${user.alias}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Correo: ${user.email} · Zona: ${user.neighborhood} (${user.sector})',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('btn_switch_to_maria'),
                        onPressed: () => c.signIn(
                          email: 'maria@pueblolibre.pe',
                          password: 'vecinos-pueblo-libre',
                        ),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Usar cuenta María Castillo'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('btn_switch_to_jorge'),
                        onPressed: () => c.signIn(
                          email: 'jorge@pueblolibre.pe',
                          password: 'vecinos-pueblo-libre',
                        ),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Usar cuenta Don Jorge'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('btn_sign_out'),
                        onPressed: c.signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Selector manual de barrio/sector y ubicación aproximada por GPS opcional
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tu barrio y ubicación aproximada (Privacidad protegida)',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'El permiso de GPS es 100% opcional. Si prefieres no activarlo, elige tu distrito y sector manualmente sin ningún bloqueo. Nunca publicamos tu dirección exacta.',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
                  key: const Key('dropdown_district'),
                  initialValue: _selectedDistrict,
                  decoration: const InputDecoration(
                    labelText: 'Distrito / Barrio',
                  ),
                  items: [
                    for (final d in districts)
                      DropdownMenuItem(value: d, child: Text(d)),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    final firstSector =
                        AppConfig.zonesByDistrict[val]!.first.sector;
                    setState(() {
                      _selectedDistrict = val;
                      _selectedSector = firstSector;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
                  key: const Key('dropdown_sector'),
                  initialValue:
                      sectorsForDistrict.any((z) => z.sector == _selectedSector)
                      ? _selectedSector
                      : sectorsForDistrict.first.sector,
                  decoration: const InputDecoration(
                    labelText: 'Sector / Cuadrante aproximado',
                  ),
                  items: [
                    for (final z in sectorsForDistrict)
                      DropdownMenuItem(
                        value: z.sector,
                        child: Text('${z.sector} (${z.referenceLandmark})'),
                      ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _selectedSector = val);
                  },
                ),
                const SizedBox(height: 10),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('switch_optional_gps'),
                    contentPadding: EdgeInsets.zero,
                    value: _useOptionalGps,
                    onChanged: _requestingGps ? null : _toggleGps,
                    title: const Text(
                      'Usar ubicación aproximada por GPS (opcional)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Solo para calcular distancia a servicios cercanos; redondeada a nivel de sector.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('btn_save_manual_zone'),
                  onPressed: _handleSaveLocationOnly,
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Guardar zona seleccionada'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Formulario de inicio de sesión o registro
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        key: const Key('tab_login_mode'),
                        label: const Text('Iniciar sesión'),
                        selected: !_isRegisterMode,
                        onSelected: (_) =>
                            setState(() => _isRegisterMode = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        key: const Key('tab_register_mode'),
                        label: const Text('Crear cuenta vecinal'),
                        selected: _isRegisterMode,
                        onSelected: (_) =>
                            setState(() => _isRegisterMode = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_isRegisterMode) ...[
                  TextField(
                    key: const Key('input_auth_alias'),
                    controller: _aliasController,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Tu nombre o alias público en el barrio',
                      hintText: 'Ej. Doña Rosa · Sector Candamo',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('input_auth_email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_auth_password'),
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.urgentRed,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 58),
                  child: ElevatedButton.icon(
                    key: const Key('btn_submit_auth'),
                    onPressed: _handleAuthSubmit,
                    icon: const Icon(Icons.login),
                    label: Text(
                      _isRegisterMode
                          ? 'Registrarme y entrar al barrio'
                          : 'Ingresar a mi cuenta',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
