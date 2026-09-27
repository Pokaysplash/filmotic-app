import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_config_shared.dart';
import 'updates/tv_updates_tab.dart';
import 'appearance/tv_appearance_tab.dart';
import '../../profile/presentation/profile_selection_page.dart';

enum _ConfigTab {
  perfil,
  apariencia,
  actualizaciones,
}

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
  _ConfigTab _tab = _ConfigTab.perfil;
  bool _movingFocusToContent = false;
  String _menuPosition = 'top';

  late final List<FocusNode> _tabNodes;
  final ScrollController _scroll = ScrollController();

  final FocusNode _perfilCardFocus = FocusNode(debugLabel: 'cfg_perfil_btn');
  final GlobalKey<ActualizacionesTabState> _actualizacionesKey = GlobalKey();
  final GlobalKey<AparienciaTabState> _aparienciaKey = GlobalKey();

  static const _tabLabels = [
    'Perfil',
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
    _perfilCardFocus.dispose();
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

  void _selectTab(int index, {bool focusContent = false}) {
    final tab =
        _ConfigTab.values[index.clamp(0, _ConfigTab.values.length - 1)];
    final changed = _tab != tab;
    if (changed) {
      setState(() => _tab = tab);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    if (focusContent) {
      _enterTabContent(tab, afterRebuild: changed);
    }
  }

  void _enterTabContent(_ConfigTab tab, {bool afterRebuild = false}) {
    Future<void> focusWhenReady() async {
      final waits = afterRebuild ? 3 : 1;
      for (var i = 0; i < waits; i++) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      if (!mounted || _tab != tab) return;

      if (tab == _ConfigTab.perfil) {
        _perfilCardFocus.requestFocus();
        _movingFocusToContent = false;
        return;
      }

      final state = _stateFor(tab);
      if (state != null) {
        state.requestFirstFocus();
        _movingFocusToContent = false;
      }
    }

    if (_tab != tab) {
      setState(() => _tab = tab);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    focusWhenReady();
  }

  dynamic _stateFor(_ConfigTab tab) {
    switch (tab) {
      case _ConfigTab.perfil:
        return null;
      case _ConfigTab.actualizaciones:
        return _actualizacionesKey.currentState;
      case _ConfigTab.apariencia:
        return _aparienciaKey.currentState;
    }
  }

  Widget _buildBody() {
    switch (_tab) {
      case _ConfigTab.perfil:
        return _buildPerfilTab();
      case _ConfigTab.actualizaciones:
        return ActualizacionesTab(
          key: _actualizacionesKey,
          onRequestTabFocus: _focusCurrentTab,
        );
      case _ConfigTab.apariencia:
        return AparienciaTab(
          key: _aparienciaKey,
          onRequestTabFocus: _focusCurrentTab,
          onMenuPositionChanged: (v) {
            if (mounted) setState(() => _menuPosition = v);
          },
        );
    }
  }

  Widget _buildPerfilTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_circle_rounded,
                  color: Color(0xFFFF6B35),
                  size: 48,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Perfiles de Usuario',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cambia o administra tu perfil local para tener tu propio historial, favoritos y preferencias.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Focus(
                focusNode: _perfilCardFocus,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _focusCurrentTab();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    _openProfileSelection();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return InkWell(
                      onTap: _openProfileSelection,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: hasFocus ? Colors.white : const Color(0xFFFF6B35),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: hasFocus
                              ? [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.switch_account_rounded,
                              color: hasFocus ? Colors.black : Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Cambiar perfil',
                              style: TextStyle(
                                color: hasFocus ? Colors.black : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
        ),
      ),
    );
  }

  void _openProfileSelection() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileSelectionPage(
          allowDismiss: true,
        ),
      ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
      color: const Color(0xFF121214),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(_tabLabels.length, (i) {
          final selected = _tab.index == i;
          final tabEnum = _ConfigTab.values[i];
          return Expanded(
            child: Focus(
              focusNode: _tabNodes[i],
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;

                if (key == LogicalKeyboardKey.arrowRight) {
                  if (i < _tabNodes.length - 1) {
                    _selectTab(i + 1);
                    _tabNodes[i + 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }

                if (key == LogicalKeyboardKey.arrowLeft) {
                  if (i > 0) {
                    _selectTab(i - 1);
                    _tabNodes[i - 1].requestFocus();
                  } else {
                    widget.onRequestMenuFocus?.call();
                  }
                  return KeyEventResult.handled;
                }

                if (key == LogicalKeyboardKey.arrowDown ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.enter) {
                  if (_movingFocusToContent) return KeyEventResult.handled;
                  _movingFocusToContent = true;
                  _enterTabContent(tabEnum);
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  return InkWell(
                    onTap: () => _selectTab(i, focusContent: true),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: hasFocus
                            ? const Color(0xFFFF6B35).withValues(alpha: 0.22)
                            : (selected
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasFocus
                              ? Colors.white
                              : (selected
                                  ? const Color(0xFFFF6B35)
                                  : Colors.transparent),
                          width: hasFocus ? 2.0 : 1.0,
                        ),
                      ),
                      child: Text(
                        _tabLabels[i],
                        style: TextStyle(
                          color: hasFocus
                              ? Colors.white
                              : (selected
                                  ? const Color(0xFFFF6B35)
                                  : Colors.white70),
                          fontSize: 14,
                          fontWeight: selected || hasFocus
                              ? FontWeight.bold
                              : FontWeight.normal,
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopTabs(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}