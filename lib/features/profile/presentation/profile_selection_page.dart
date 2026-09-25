import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/storage/app_database.dart';
import '../../../presentation/mobile/mobile_shell.dart' as mobile;
import '../../../presentation/tv/tv_shell.dart' as tv;
import 'transfer_screen.dart';

const _kAccent = Color(0xFFFF6B35);

final List<String> kPresetAvatars = [
  'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
  'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=150',
  'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=150',
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
  'https://images.unsplash.com/photo-1566492031773-4f4e44671857?w=150',
];

/// Pantalla de selección de perfiles estilo Netflix con soporte Sembast y D-Pad para TV.
class ProfileSelectionPage extends StatefulWidget {
  final VoidCallback? onProfileSelected;
  final Widget Function()? buildHome;
  final bool allowDismiss;

  const ProfileSelectionPage({
    super.key,
    this.onProfileSelected,
    this.buildHome,
    this.allowDismiss = false,
  });

  @override
  State<ProfileSelectionPage> createState() => _ProfileSelectionPageState();
}

class _ProfileSelectionPageState extends State<ProfileSelectionPage> {
  List<LocalProfile> _profiles = [];
  bool _loading = true;
  bool _isEditing = false;
  String? _activeProfileId;

  static const _bgImages = [
    'https://image.tmdb.org/t/p/original/4kTINu9mv2YV1PqFqPGG1FZMnhi.jpg',
    'https://image.tmdb.org/t/p/original/yr1n2RzZHn1UYozrzvPzjcE60cP.jpg',
    'https://image.tmdb.org/t/p/original/cFXxKJzGrvjcmMJAReNekx0RVJb.jpg',
  ];
  int _bgIndex = 0;
  Timer? _bgTimer;

  final List<FocusNode> _profileNodes = [];
  final FocusNode _addNode = FocusNode(debugLabel: 'profile_add');
  final FocusNode _manageNode = FocusNode(debugLabel: 'profile_manage');
  final FocusNode _transferNode = FocusNode(debugLabel: 'profile_transfer');

  @override
  void initState() {
    super.initState();
    _load();
    _bgTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() => _bgIndex = (_bgIndex + 1) % _bgImages.length);
    });
  }

  @override
  void dispose() {
    _bgTimer?.cancel();
    for (final n in _profileNodes) {
      n.dispose();
    }
    _addNode.dispose();
    _manageNode.dispose();
    _transferNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await AppDatabase.instance.init();
    final list = await AppDatabase.instance.getProfiles();
    final current = AppDatabase.instance.activeProfile?.id;

    if (!mounted) return;

    while (_profileNodes.length < list.length) {
      _profileNodes.add(FocusNode(debugLabel: 'profile_${_profileNodes.length}'));
    }
    while (_profileNodes.length > list.length) {
      _profileNodes.removeLast().dispose();
    }

    setState(() {
      _profiles = list;
      _activeProfileId = current;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_profileNodes.isNotEmpty) {
        _profileNodes.first.requestFocus();
      } else {
        _addNode.requestFocus();
      }
    });
  }

  Future<Widget> _resolveHome() async {
    if (widget.buildHome != null) return widget.buildHome!();
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('app_mode') ?? 'mobile';
    return mode == 'tv' ? const tv.MainHome() : const mobile.MainHome();
  }

  Future<void> _enterApp() async {
    if (!mounted) return;
    if (widget.allowDismiss && widget.buildHome == null) {
      widget.onProfileSelected?.call();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final home = await _resolveHome();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (route) => false,
    );
  }

  Future<void> _onProfileTap(LocalProfile profile) async {
    if (_isEditing) {
      _openEditDialog(profile);
      return;
    }

    // Si tiene PIN, solicitar verificación
    if (profile.pin != null && profile.pin!.isNotEmpty) {
      final pinOk = await _showPinDialog(profile);
      if (pinOk != true) return;
    }

    await AppDatabase.instance.setActiveProfile(profile);
    widget.onProfileSelected?.call();
    await _enterApp();
  }

  Future<bool?> _showPinDialog(LocalProfile profile) async {
    final pinController = TextEditingController();
    String error = '';

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white24),
              ),
              title: Row(
                children: [
                  const Icon(Icons.lock, color: _kAccent),
                  const SizedBox(width: 8),
                  Text('PIN de ${profile.nombre}',
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ingresa el PIN de 4 dígitos para acceder a este perfil.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      letterSpacing: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) {
                      if (AppDatabase.instance.verifyPin(profile, val.trim())) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDialogState(() => error = 'PIN incorrecto');
                      }
                    },
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(error,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                  onPressed: () {
                    if (AppDatabase.instance.verifyPin(profile, pinController.text.trim())) {
                      Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() => error = 'PIN incorrecto');
                    }
                  },
                  child: const Text('Entrar', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openCreateDialog() {
    if (_profiles.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Límite de 5 perfiles alcanzado.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String selectedAvatar = kPresetAvatars.first;
    bool isKids = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white24),
              ),
              title: const Text('Nuevo Perfil',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nombre del perfil:',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ej. Juan, Mamá, Niños',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Selecciona un Avatar:',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kPresetAvatars.map((av) {
                        final isSel = selectedAvatar == av;
                        return InkWell(
                          onTap: () => setDialogState(() => selectedAvatar = av),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel ? _kAccent : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundImage: NetworkImage(av),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('¿Es perfil infantil?',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Filtro para contenido apto para toda la familia',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                      value: isKids,
                      activeColor: _kAccent,
                      onChanged: (v) => setDialogState(() => isKids = v),
                    ),
                    const SizedBox(height: 10),
                    const Text('PIN de 4 dígitos (opcional):',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, letterSpacing: 4),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Dejar vacío para sin PIN',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);
                    await AppDatabase.instance.createProfile(
                      nombre: name,
                      avatar: selectedAvatar,
                      esInfantil: isKids,
                      pin: pinCtrl.text.trim().isNotEmpty ? pinCtrl.text.trim() : null,
                    );
                    await _load();
                  },
                  child: const Text('Crear', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openEditDialog(LocalProfile profile) {
    final nameCtrl = TextEditingController(text: profile.nombre);
    final pinCtrl = TextEditingController(text: profile.pin ?? '');
    String selectedAvatar = profile.avatar;
    bool isKids = profile.esInfantil;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white24),
              ),
              title: Text('Editar: ${profile.nombre}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nombre:',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Avatar:',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kPresetAvatars.map((av) {
                        final isSel = selectedAvatar == av;
                        return InkWell(
                          onTap: () => setDialogState(() => selectedAvatar = av),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel ? _kAccent : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(av),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('¿Es perfil infantil?',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: isKids,
                      activeColor: _kAccent,
                      onChanged: (v) => setDialogState(() => isKids = v),
                    ),
                    const SizedBox(height: 10),
                    const Text('PIN de 4 dígitos:',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, letterSpacing: 4),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Vacío para quitar PIN',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 28),
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar este perfil'),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              backgroundColor: const Color(0xFF1c1c1e),
                              title: const Text('¿Eliminar perfil?',
                                  style: TextStyle(color: Colors.white)),
                              content: Text(
                                  'Se eliminará "${profile.nombre}", sus favoritos y su historial.',
                                  style: const TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Eliminar',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            Navigator.pop(ctx);
                            await AppDatabase.instance.deleteProfile(profile.id);
                            await _load();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);
                    final updated = profile.copyWith(
                      nombre: name,
                      avatar: selectedAvatar,
                      esInfantil: isKids,
                      pin: pinCtrl.text.trim().isNotEmpty ? pinCtrl.text.trim() : null,
                    );
                    await AppDatabase.instance.updateProfile(updated);
                    await _load();
                  },
                  child: const Text('Guardar', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height * 1.15;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo animado
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1200),
            child: Image.network(
              _bgImages[_bgIndex],
              key: ValueKey(_bgIndex),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(color: Colors.black),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.65),
                  Colors.black.withOpacity(0.85),
                  Colors.black.withOpacity(0.95),
                ],
              ),
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kAccent),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          const Text(
                            '¿Quién está viendo ahora?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isEditing
                                ? 'Selecciona un perfil para editarlo'
                                : 'Perfiles locales con historial y favoritos independientes',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 36),

                          // Grid / Row de perfiles
                          Wrap(
                            spacing: isLandscape ? 32 : 20,
                            runSpacing: 28,
                            alignment: WrapAlignment.center,
                            children: [
                              ...List.generate(_profiles.length, (index) {
                                final p = _profiles[index];
                                final isSelected = p.id == _activeProfileId;
                                final focusNode = _profileNodes.length > index
                                    ? _profileNodes[index]
                                    : null;

                                return _ProfileCard(
                                  profile: p,
                                  isEditing: _isEditing,
                                  isActive: isSelected,
                                  focusNode: focusNode,
                                  onTap: () => _onProfileTap(p),
                                );
                              }),

                              // Botón de Añadir Perfil (si hay menos de 5)
                              if (_profiles.length < 5)
                                _AddProfileButton(
                                  focusNode: _addNode,
                                  onTap: _openCreateDialog,
                                ),
                            ],
                          ),

                          const SizedBox(height: 48),

                          // Barra de Acciones
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              // Botón Administrar perfiles
                              OutlinedButton.icon(
                                focusNode: _manageNode,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: _isEditing ? _kAccent : Colors.white30,
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                                icon: Icon(_isEditing ? Icons.check : Icons.edit,
                                    color: _isEditing ? _kAccent : Colors.white),
                                label: Text(
                                  _isEditing ? 'Listo' : 'Administrar perfiles',
                                  style: TextStyle(
                                    color: _isEditing ? _kAccent : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() => _isEditing = !_isEditing);
                                },
                              ),

                              // Botón Transferir Cuentas (QR + TCP)
                              ElevatedButton.icon(
                                focusNode: _transferNode,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22222A),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                                icon: const Icon(Icons.qr_code_scanner, color: Colors.amberAccent),
                                label: const Text('Transferir Cuenta (QR/P2P)'),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const TransferScreen(),
                                    ),
                                  ).then((_) => _load());
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  final LocalProfile profile;
  final bool isEditing;
  final bool isActive;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.isEditing,
    required this.isActive,
    this.focusNode,
    required this.onTap,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final borderCol = widget.isEditing
        ? Colors.amberAccent
        : (_isFocused ? _kAccent : (widget.isActive ? _kAccent : Colors.transparent));

    return InkWell(
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _isFocused = v),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedScale(
        scale: _isFocused ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: 105,
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol, width: 3),
                      boxShadow: _isFocused
                          ? [
                              BoxShadow(
                                color: _kAccent.withOpacity(0.5),
                                blurRadius: 16,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.network(
                      widget.profile.avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF2A2A38),
                        child: const Icon(Icons.person, color: Colors.white54, size: 44),
                      ),
                    ),
                  ),

                  // Overlay en modo edición
                  if (widget.isEditing)
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.edit, color: Colors.amberAccent, size: 32),
                    ),

                  // Candado si tiene PIN
                  if (widget.profile.pin != null && widget.profile.pin!.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock, size: 14, color: Colors.white),
                      ),
                    ),

                  // Badge Infantil
                  if (widget.profile.esInfantil)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber[700],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'KIDS',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.profile.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isFocused || widget.isActive ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProfileButton extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback onTap;

  const _AddProfileButton({this.focusNode, required this.onTap});

  @override
  State<_AddProfileButton> createState() => _AddProfileButtonState();
}

class _AddProfileButtonState extends State<_AddProfileButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _isFocused = v),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedScale(
        scale: _isFocused ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: 105,
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isFocused ? _kAccent : Colors.white24,
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.add, color: Colors.white70, size: 40),
              ),
              const SizedBox(height: 10),
              const Text(
                'Añadir perfil',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}