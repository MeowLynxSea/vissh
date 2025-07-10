import 'package:flutter/material.dart';

class AppData {
  final String id;
  final String title;
  final IconData icon;
  final Widget Function(String id) childBuilder;

  AppData({
    required this.id,
    required this.title,
    required this.icon,
    required this.childBuilder,
  });
}