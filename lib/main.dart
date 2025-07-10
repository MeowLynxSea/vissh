import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:vissh/pages/terminal_page.dart';
import 'package:vissh/widgets/draggable_window.dart';
import 'package:vissh/models/window_data.dart';
import 'package:vissh/widgets/taskbar.dart';
import 'package:vissh/pages/login_page.dart';
import 'package:vissh/models/credentials.dart';
import 'package:flutter/services.dart';
import 'package:vissh/models/app_data.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}

class WindowManager extends StatefulWidget {
  final SSHClient sshClient;
  final SSHCredentials credentials;

  const WindowManager({
    super.key,
    required this.sshClient,
    required this.credentials,
  });

  @override
  State<WindowManager> createState() => _WindowManagerState();
}

class _WindowManagerState extends State<WindowManager> {
  final List<WindowData> _windows = [];
  int _nextWindowId = 0;

  bool _isVerified = false;
  String _verificationMessage = '连接到服务器...';
  String _verificationFailedMessage = '';

  String _connectionQuality = '';
  Timer? _connectionQualityTimer;

  final List<AppData> _apps = [];

  @override
  void initState() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.bottom]);
    super.initState();
    _verifyConnection();
    _initializeAppList();

    widget.sshClient.done.then((_) {
      if (mounted) {
        _connectionQualityTimer?.cancel();
        Navigator.of(context).pop('disconnected');
      }
    });
  }

  @override
  void dispose() {
    _connectionQualityTimer?.cancel();
    super.dispose();
  }

  void _initializeAppList() {
    _apps.add(AppData(
      id: 'file_explorer',
      title: 'File Explorer',
      icon: Icons.folder_open,
      childBuilder: (id) => const Center(
        child: Text('View your files...', style: TextStyle(color: Colors.white)),
      ),
    ));
    _apps.add(AppData(
      id: 'terminal',
      title: 'Terminal',
      icon: Icons.terminal,
      childBuilder: (id) => TerminalPage(
        credentials: widget.credentials,
        onSessionEnd: () => _removeWindow(id),
      ),
    ));
  }

  Future<void> _verifyConnection() async {
    try {
      await widget.sshClient.run('echo Vissh SSH Connection Verified');
      if (!mounted) return;
      setState(() {
        _isVerified = true;
        _setupInitialWindows();
      });
      _startConnectionQualityChecks();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verificationMessage = '无法登录';
        _verificationFailedMessage = '请检查服务器地址和凭据，然后重试。\n错误: $e';
      });
    }
  }

  void _startConnectionQualityChecks() {
    _connectionQualityTimer =
        Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectionQuality();
    });
  }

  Future<void> _checkConnectionQuality() async {
    if (!mounted) return;
    try {
      final stopwatch = Stopwatch()..start();
      await widget.sshClient.run('echo');
      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      String quality;
      if (latency < 150) {
        quality = '良好';
      } else if (latency < 500) {
        quality = '一般';
      } else {
        quality = '差';
      }
      if (mounted) {
        setState(() {
          _connectionQuality = '$quality (${latency}ms)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionQuality = '断开连接';
        });
      }
    }
  }

  void _setupInitialWindows() {
    _launchApp('file_explorer', const Offset(100, 100));
    _launchApp('terminal', const Offset(150, 150));
  }

  void _launchApp(String appId, [Offset? position]) {
    final app = _apps.firstWhere((app) => app.id == appId, orElse: () => throw Exception('App not found: $appId'));
    final id = 'window_${_nextWindowId++}';
    final windowChild = app.childBuilder(id);
    
    final initialPosition = position ?? Offset(100.0 + (_windows.length * 20), 100.0 + (_windows.length * 20));

    setState(() {
      _windows.add(
        WindowData(
          id: id,
          title: app.title,
          position: initialPosition,
          size: const Size(700, 500),
          child: windowChild,
          icon: app.icon,
        ),
      );
      _bringToFront(id);
    });
  }

  void _bringToFront(String id) {
    final windowIndex = _windows.indexWhere((w) => w.id == id);
    if (windowIndex != -1) {
      final window = _windows[windowIndex];
      if (window.isMinimized) {
        window.isMinimized = false;
      }
      if (windowIndex != _windows.length - 1) {
        final window = _windows.removeAt(windowIndex);
        _windows.add(window);
      }
      setState(() {});
    }
  }

  void _minimizeWindow(String id) {
    setState(() {
      final windowIndex = _windows.indexWhere((w) => w.id == id);
      if (windowIndex != -1) {
        _windows[windowIndex].isMinimized = true;
      }
    });
  }

  void _onWindowIconTap(String id) {
    final windowIndex = _windows.indexWhere((w) => w.id == id);
    if (windowIndex == -1) return;

    final window = _windows[windowIndex];
    final topMostIndex = _windows.lastIndexWhere((w) => !w.isMinimized);

    setState(() {
      if (window.isMinimized) {
        window.isMinimized = false;
        _bringToFront(id);
      } else {
        if (topMostIndex != -1 && _windows[topMostIndex].id == id) {
          _minimizeWindow(id);
        } else {
          _bringToFront(id);
        }
      }
    });
  }

  void _removeWindow(String id) {
    setState(() {
      _windows.removeWhere((w) => w.id == id);
    });
  }

  void _updateWindowPosition(String id, Offset position) {
    final windowIndex = _windows.indexWhere((w) => w.id == id);
    if (windowIndex != -1) {
      setState(() {
        _windows[windowIndex].position = position;
      });
    }
  }

  void _updateWindowSize(String id, Size size) {
    final windowIndex = _windows.indexWhere((w) => w.id == id);
    if (windowIndex != -1) {
      setState(() {
        _windows[windowIndex].size = size;
      });
    }
  }

  void _updateWindowMaximizeState(String id, bool isMaximized) {
    final windowIndex = _windows.indexWhere((w) => w.id == id);
    if (windowIndex != -1) {
      setState(() {
        _windows[windowIndex].isMaximized = isMaximized;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVerified) {
      bool hasError = _verificationFailedMessage.isNotEmpty;
      return Scaffold(
        backgroundColor: const Color(0xff0078D4),
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage('https://www.meowdream.cn/background.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 120),
                hasError
                    ? const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 48)
                    : SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.8)),
                        ),
                      ),
                const SizedBox(height: 40),
                Text(
                  _verificationMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 10),
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: Text(
                      _verificationFailedMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ),
                if (hasError) const SizedBox(height: 16),
                if (hasError)
                  TextButton(
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text(
                      '返回',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final topMostIndex = _windows.lastIndexWhere((w) => !w.isMinimized);
    final activeWindowId =
        topMostIndex != -1 ? _windows[topMostIndex].id : null;

    final sortedWindowsForTaskbar = List<WindowData>.from(_windows);
    sortedWindowsForTaskbar.sort((a, b) {
      final aId = int.tryParse(a.id.split('_').last) ?? 0;
      final bId = int.tryParse(b.id.split('_').last) ?? 0;
      return aId.compareTo(bId);
    });

    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage('https://www.meowdream.cn/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  for (final data in _windows)
                    Offstage(
                      offstage: data.isMinimized,
                      child: DraggableWindow(
                        key: data.key,
                        id: data.id,
                        initialPosition: data.position,
                        initialSize: data.size,
                        title: data.title,
                        icon: data.icon,
                        isActive: data.id == activeWindowId,
                        isMaximized: data.isMaximized,
                        isMinimized: data.isMinimized,
                        onBringToFront: _bringToFront,
                        onMinimize: _minimizeWindow,
                        onClose: _removeWindow,
                        onMove: _updateWindowPosition,
                        onResize: _updateWindowSize,
                        onMaximizeChanged: _updateWindowMaximizeState,
                        child: data.child,
                      ),
                    )
                ],
              ),
            ),
            Taskbar(
              windows: sortedWindowsForTaskbar,
              apps: _apps,
              onAppLaunch: (appId) => _launchApp(appId),
              activeWindowId: activeWindowId,
              onWindowIconTap: _onWindowIconTap,
              connectionQuality: _connectionQuality,
            ),
          ],
        ),
      ),
    );
  }
}