import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vissh/models/credentials.dart';
import '../models/window_data.dart';
import '../models/app_data.dart';

class Taskbar extends StatefulWidget {
  final List<WindowData> windows;
  final String? activeWindowId;
  final Function(String) onWindowIconTap;
  final double height;
  final String? connectionQuality;
  final List<AppData> apps;
  final Function(String) onAppLaunch;
  final SSHCredentials? credentials;
  final VoidCallback? onDisconnect;

  const Taskbar({
    super.key,
    required this.windows,
    required this.onWindowIconTap,
    required this.apps,
    required this.onAppLaunch,
    this.activeWindowId,
    this.height = 48.0,
    this.connectionQuality,
    this.credentials,
    this.onDisconnect,
  });

  @override
  State<Taskbar> createState() => _TaskbarState();
}

class _TaskbarState extends State<Taskbar> {
  late Timer _timer;
  String _currentTime = '';
  String _currentDate = '';
  bool _isInfoMenuOpen = false;
  bool _isStartMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (timer) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _currentTime = DateFormat('HH:mm').format(now);
      _currentDate = DateFormat('yyyy/M/d').format(now);
    });
  }

  Future<void> _showInfoMenu(BuildContext context) async {
    setState(() {
      _isInfoMenuOpen = true;
    });

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        const double rightMargin = 8.0;
        const double bottomMargin = 8.0;

        final double menuBottom = widget.height + bottomMargin;
        final double menuRight = rightMargin;

        final slideAnimation = Tween<Offset>(
          begin: const Offset(0, 0.8),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);

        final fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)).animate(animation);

        return Stack(
            children: [
              Positioned(
                right: menuRight,
                bottom: menuBottom,
                child: FadeTransition(
                  opacity: fadeAnimation,
                  child: SlideTransition(
                    position: slideAnimation,
                    child: _buildInfoMenuContent(),
                  ),
                ),
              ),
            ]
        );
      },
    );

    setState(() {
      _isInfoMenuOpen = false;
    });
  }

  Widget _buildInfoMenuContent() {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2))
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('连接详情', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(color: Colors.white30, height: 20),
                Text('状态: ${widget.connectionQuality ?? "未知"}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showStartMenu(BuildContext context) async {
    setState(() {
      _isStartMenuOpen = true;
    });

    final navigator = Navigator.of(context);

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        const double bottomMargin = 8.0;
        final double menuBottom = widget.height + bottomMargin;

        final slideAnimation = Tween<Offset>(
          begin: const Offset(0, 0.8),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);

        final fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)).animate(animation);

        final menuContent = FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: _StartMenuContent(
              apps: widget.apps,
              onAppLaunch: widget.onAppLaunch,
              credentials: widget.credentials,
              onDisconnect: widget.onDisconnect,
              onClose: () {
                if (navigator.canPop()) {
                  navigator.pop();
                }
              },
            ),
          ),
        );

        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: menuBottom,
              child: Align(
                alignment: Alignment.center,
                child: menuContent,
              ),
            ),
          ],
        );
      },
    );

    setState(() {
      _isStartMenuOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    IconData connectionQualityIcon;
    if (widget.connectionQuality == null || widget.connectionQuality!.isEmpty || widget.connectionQuality!.startsWith('断开')) {
      connectionQualityIcon = Icons.signal_wifi_off_outlined;
    } else if (widget.connectionQuality!.startsWith('良好')) {
      connectionQualityIcon = Icons.network_wifi_3_bar_rounded;
    } else if (widget.connectionQuality!.startsWith('一般')) {
      connectionQualityIcon = Icons.network_wifi_2_bar_rounded;
    } else {
      connectionQualityIcon = Icons.network_wifi_1_bar_rounded;
    }

    return Container(
      height: widget.height,
      color: Colors.black.withValues(alpha: 0.8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => _showStartMenu(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: _isStartMenuOpen ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Tooltip(
                    message: '开始',
                    child: Icon(
                      Icons.window,
                      color: Colors.white.withAlpha(220),
                      size: 24,
                    ),
                  ),
                ),
              ),
              Row(
                children: widget.windows.map((window) {
                  final isActive = widget.activeWindowId == window.id && !window.isMinimized;
                  return InkWell(
                    onTap: () => widget.onWindowIconTap(window.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Tooltip(
                        message: window.title,
                        child: Icon(
                          window.icon,
                          color: window.isMinimized ? Colors.white.withAlpha(150) : Colors.white.withAlpha(220),
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _isInfoMenuOpen ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Builder(builder: (context) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        hoverColor: Colors.white.withValues(alpha: 0.08),
                        onTap: () => _showInfoMenu(context),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(connectionQualityIcon, size: 20, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    );
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currentTime,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        _currentDate,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
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

class _StartMenuContent extends StatefulWidget {
  final List<AppData> apps;
  final Function(String) onAppLaunch;
  final VoidCallback onClose;
  final SSHCredentials? credentials;
  final VoidCallback? onDisconnect;

  const _StartMenuContent({
    required this.apps,
    required this.onAppLaunch,
    required this.onClose,
    this.credentials,
    this.onDisconnect,
  });

  @override
  State<_StartMenuContent> createState() => _StartMenuContentState();
}

class _StartMenuContentState extends State<_StartMenuContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Widget _buildStartMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: Colors.white.withValues(alpha: 0.08),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 90,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredApps = widget.apps.where((app) {
      final titleLower = app.title.toLowerCase();
      final idLower = app.id.toLowerCase();
      final searchLower = _searchQuery.toLowerCase();
      return titleLower.contains(searchLower) || idLower.contains(searchLower);
    }).toList();

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            width: 640,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: '搜索应用...',
                                hintStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                              ),
                            ),
                          ),
                          _searchController.text == '' ? Text(
                            '所有应用',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ) : Text(
                            '匹配的应用',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8.0,
                            runSpacing: 16.0,
                            children: filteredApps.isEmpty ? [ Text(
                              '没有匹配的结果',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ) ] : filteredApps.map((app) {
                              return _buildStartMenuItem(
                                icon: app.icon,
                                title: app.title,
                                onTap: () {
                                  widget.onClose();
                                  widget.onAppLaunch(app.id);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.credentials?.username ?? 'Unknown User',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.credentials?.host}:${widget.credentials?.port}',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          widget.onClose();
                          widget.onDisconnect?.call();
                        },
                        tooltip: '断开连接',
                        icon: const Icon(Icons.power_settings_new, color: Colors.white),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}