import 'dart:async';
import 'package:flutter/material.dart';
import '../models/window_data.dart';

class Taskbar extends StatefulWidget {
  final List<WindowData> windows;
  final String? activeWindowId;
  final Function(String) onWindowIconTap;
  final double height;

  const Taskbar({
    super.key,
    required this.windows,
    required this.onWindowIconTap,
    this.activeWindowId,
    this.height = 48.0,
  });

  @override
  State<Taskbar> createState() => _TaskbarState();
}

class _TaskbarState extends State<Taskbar> {
  late Timer _timer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    setState(() {
      _currentTime = '$hour:$minute';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: Colors.black.withValues(alpha: 0.8),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      child: Icon(window.icon, color: window.isMinimized ? Colors.white.withAlpha(150) : Colors.white.withAlpha(220), size: 24),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              _currentTime,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}