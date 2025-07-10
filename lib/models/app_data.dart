import 'package:flutter/material.dart';
import 'package:vissh/models/credentials.dart';

class AppData {
  final String id;
  final String title;
  final IconData icon;
  final Widget Function(String id, SSHCredentials credentials) childBuilder;

  AppData({
    required this.id,
    required this.title,
    required this.icon,
    required this.childBuilder,
  });
}