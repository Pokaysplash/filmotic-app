import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_config_shared.dart';
import 'updates/tv_updates_tab.dart';
import 'appearance/tv_appearance_tab.dart';
import '../../profile/presentation/profile_selection_page.dart';

enum _ConfigTab {
  perfiles,
  apariencia,
  actualizaciones,
}

/// Página de configuración TV (shell de tabs).
/// Simplificada al igual que en móvil: Perfiles, Apariencia, Actualizaciones.
class ConfigPage extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const ConfigPage({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<ConfigPage> createState() => ConfigPageState();
}

class ConfigPageState extends State<ConfigPage>
    with AutomaticKeepAliveClientMixin {
  _ConfigTab _tab = _ConfigTab.perfiles;
  bool _movingFocusToContent = false;
  String _menuPosition = 'top';

  late final List<FocusNode> _tabNodes;
  final ScrollController _scroll = ScrollController();

  final GlobalKey<ActualizacionesTabState> _actualizacionesKey = GlobalKey();
  final GlobalKey<AparienciaTabState> _aparienciaKey = GlobalKey();
  final FocusNode _perfilesActionNode = FocusNode(debugLabel: 'cfg_perfiles_btn');

  static const _tabLabels = [
    'Perfiles',
    'Apariencia',
    'Actualizaciones',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabNodes = List.generate(
      _tabLabels.length,
      (i) => FocusNode(debugLabel: 'cfg_tab_$i'),
    );
    MenuPositionPref.get().then((v) {
      if (mounted) setState(() => _menuPosition = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMainFocusNodeCreated?.call(_tabNodes[0]);
    });
  }

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    _perfilesActionNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void refresh() {
    _actualizacionesKey.currentState?.refresh();
  }

  void _focusCurrentTab() {
    final i = _tab.index;
    if (i >= 0 && i < _tabNodes.length) {
      _tabNodes[i].requestFocus();
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _selectTab(int index) {
    if (index == _tab.index) return;
    setState(() => _tab = _ConfigTab.values[index]);
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  void _moveFocusToContent() {
    if (_movingFocusToContent) return;
    _movingFocusToContent = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _movingFocusToContent = false;
      if (!mounted) return;
      final target = _contentFirstFocusNode();
      target?.requestFocus();
    });
  }

  FocusNode? _contentFirstFocusNode() {
    switch (_tab) {
      case _ConfigTab.perfiles:
        return _perfilesActionNode;
      case _ConfigTab.apariencia:
        return _aparienciaKey.currentState?.firstFocusNode;
      case _ConfigTab.actualizaciones:
        return _actualizacionesKey.currentState?.firstFocusNode;
    }
  }

  Widget _buildBody() {
    switch (_tab) {
      case _ConfigTab.perfiles:
        return _buildPerfilesTab();
      case _ConfigTab.apariencia:
        return AparienciaTab(
          key: _aparienciaKey,
          onRequestTabFocus: _focusCurrentTab,
          onMenuPositionChanged: (v) {
            if (mounted) setState(() => _menuPosition = v);
          },
        );
      case _ConfigTab.actualizaciones:
        return ActualizacionesTab(
          key: _actualizacionesKey,
          onRequestTabFocus: _focusCurrentTab,
        );
    }
  }

  Widget _buildPerfilesTab() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: kConfigCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kConfigAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_circle_rounded, color: kConfigAccent, size: 30),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Perfiles de Usuario',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gestiona los perfiles locales, personaliza avatares y configura tu PIN de seguridad.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Focus(
            focusNode: _perfilesActionNode,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _focusCurrentTab();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                _openProfiles();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final hasFocus = Focus.of(ctx).hasFocus;
                return InkWell(
                  onTap: _openProfiles,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: hasFocus ? kConfigAccent : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasFocus ? Colors.white : Colors.white.withValues(alpha: 0.15),
                        width: hasFocus ? 2.5 : 1.0,
                      ),
                      boxShadow: hasFocus
                          ? [
                              BoxShadow(
                                color: kConfigAccent.withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.switch_account_rounded,
                          color: hasFocus ? Colors.white : kConfigAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Cambiar o Administrar Perfil',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: hasFocus ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openProfiles() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileSelectionPage(allowDismiss: true),
      ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
      color: const Color(0xFF121214),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: List.generate(_tabLabels.length, (i) {
          final selected = _tab.index == i;
          return Expanded(
            child: Focus(
              focusNode: _tabNodes[i],
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (i < _tabNodes.length - 1) {
                    _selectTab(i + 1);
                    _tabNodes[i + 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (i > 0) {
                    _selectTab(i - 1);
                    _tabNodes[i - 1].requestFocus();
                  } else {
                    widget.onRequestMenuFocus?.call();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _moveFocusToContent();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  _selectTab(i);
                  _moveFocusToContent();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (ctx) {
                  final hasFocus = Focus.of(ctx).hasFocus;
                  return InkWell(
                    onTap: () {
                      _selectTab(i);
                      _tabNodes[i].requestFocus();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: hasFocus
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: selected || hasFocus
                                ? kConfigAccent
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        _tabLabels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected || hasFocus
                              ? Colors.white
                              : Colors.white60,
                          fontSize: 15,
                          fontWeight: selected || hasFocus
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPad = _menuPosition == 'top' ? 56.0 : 8.0;
    return Scaffold(
      backgroundColor: kConfigBg,
      body: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Column(
          children: [
            _buildTopTabs(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
