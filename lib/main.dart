import 'package:flutter/material.dart';
import 'widgets/draggable_window.dart';
import 'models/window_data.dart';
import 'widgets/taskbar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const WindowManager(),
    );
  }
}

class WindowManager extends StatefulWidget {
  const WindowManager({super.key});

  @override
  State<WindowManager> createState() => _WindowManagerState();
}

class _WindowManagerState extends State<WindowManager> {
  final List<WindowData> _windows = [];
  int _nextWindowId = 0;

  @override
  void initState() {
    super.initState();
    _addWindow(
      'File Explorer',
      const Offset(100, 100),
      const Center(
        child: Text('View your files...', style: TextStyle(color: Colors.white)),
      ),
      Icons.folder_open,
    );
    _addWindow(
      'Terminal',
      const Offset(150, 150),
      const Center(
        child: Text('Run your commands...', style: TextStyle(color: Colors.white)),
      ),
      Icons.web,
    );
  }

  void _addWindow(String title, Offset position, Widget child, IconData icon) {
    setState(() {
      final id = 'window_${_nextWindowId++}';
      _windows.add(
        WindowData(
          id: id,
          title: title,
          position: position,
          size: const Size(400, 300),
          child: child,
          icon: icon,
        ),
      );
      _bringToFront(id);
    });
  }

  void _bringToFront(String id) {
    final windowIndex = _windows.indexWhere((w) => w.id == id);
    if (windowIndex != -1) {
      final window = _windows[windowIndex];
      if(window.isMinimized) {
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
    final sortedWindowsForTaskbar = List<WindowData>.from(_windows);
    sortedWindowsForTaskbar.sort((a, b) {
      final aId = int.tryParse(a.id.split('_').last) ?? 0;
      final bId = int.tryParse(b.id.split('_').last) ?? 0;
      return aId.compareTo(bId);
    });
    
    final topMostIndex = _windows.lastIndexWhere((w) => !w.isMinimized);
    final activeWindowId = topMostIndex != -1 ? _windows[topMostIndex].id : null;

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
                children: _windows.where((w) => !w.isMinimized).map((data) {
                  final bool isActive = data.id == activeWindowId;
                  return DraggableWindow(
                    key: ValueKey(data.id),
                    id: data.id,
                    initialPosition: data.position,
                    initialSize: data.size,
                    title: data.title,
                    icon: data.icon,
                    isActive: isActive,
                    isMaximized: data.isMaximized,
                    onBringToFront: _bringToFront,
                    onMinimize: _minimizeWindow,
                    onClose: _removeWindow,
                    onMove: _updateWindowPosition,
                    onResize: _updateWindowSize,
                    onMaximizeChanged: _updateWindowMaximizeState,
                    child: data.child,
                  );
                }).toList(),
              ),
            ),
            Taskbar(
              windows: sortedWindowsForTaskbar,
              activeWindowId: activeWindowId,
              onWindowIconTap: _onWindowIconTap,
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () => _addWindow(
              'New Window',
              const Offset(200, 200),
              const Center(child: Text('This is the new window content area', style: TextStyle(color: Colors.white))),
              Icons.add_circle_outline,
            ),
            tooltip: 'Add New Window',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 32),
        ]
      )
    );
  }
}