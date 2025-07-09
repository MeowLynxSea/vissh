import 'package:flutter/material.dart';

class WindowData {
  final String id;
  final String title;
  final Widget child;
  final IconData icon;
  Offset position;
  Size size;
  bool isMinimized;
  bool isMaximized;

  WindowData({
    required this.id,
    required this.title,
    required this.child,
    required this.icon,
    required this.position,
    required this.size,
    this.isMinimized = false,
    this.isMaximized = false,
  });
}