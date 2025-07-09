import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../models/credentials.dart';

class TerminalPage extends StatefulWidget {
  final SSHCredentials credentials;
  final bool isActive;
  final VoidCallback onSessionEnd;

  const TerminalPage({
    super.key,
    required this.credentials,
    required this.isActive,
    required this.onSessionEnd,
  });

  @override
  _TerminalPageState createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final Terminal terminal = Terminal(maxLines: 10000);
  final FocusNode _focusNode = FocusNode();
  SSHClient? client;
  SSHSession? shell;

  @override
  void initState() {
    super.initState();
    _startSshShell();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TerminalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _focusNode.requestFocus();
    } else if (!widget.isActive && oldWidget.isActive) {
      _focusNode.unfocus();
    }
  }

  Future<void> _startSshShell() async {
    try {
      client = SSHClient(
        await SSHSocket.connect(widget.credentials.host, 22),
        username: widget.credentials.username,
        onPasswordRequest: () => widget.credentials.password,
      );

      shell = await client!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      terminal.onOutput = (data) {
        shell?.write(utf8.encode(data));
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        shell?.resizeTerminal(width, height);
      };

      shell?.stdout.listen((data) {
        terminal.write(utf8.decode(data));
      });

      shell?.stderr.listen((data) {
        terminal.write(utf8.decode(data));
      });

      await shell?.done;
      if (mounted) {
        widget.onSessionEnd();
      }

    } catch (e) {
      if (mounted) {
        terminal.write('Error: $e');
        widget.onSessionEnd();
      }
    }
  }

  TerminalKey? _mapLogicalKey(LogicalKeyboardKey key) {
    final keyMap = {
      LogicalKeyboardKey.enter: TerminalKey.enter,
      LogicalKeyboardKey.backspace: TerminalKey.backspace,
      LogicalKeyboardKey.arrowUp: TerminalKey.arrowUp,
      LogicalKeyboardKey.arrowDown: TerminalKey.arrowDown,
      LogicalKeyboardKey.arrowLeft: TerminalKey.arrowLeft,
      LogicalKeyboardKey.arrowRight: TerminalKey.arrowRight,
      LogicalKeyboardKey.tab: TerminalKey.tab,
      LogicalKeyboardKey.escape: TerminalKey.escape,
      LogicalKeyboardKey.delete: TerminalKey.delete,
      LogicalKeyboardKey.home: TerminalKey.home,
      LogicalKeyboardKey.end: TerminalKey.end,
      LogicalKeyboardKey.pageUp: TerminalKey.pageUp,
      LogicalKeyboardKey.pageDown: TerminalKey.pageDown,
      LogicalKeyboardKey.insert: TerminalKey.insert,
      LogicalKeyboardKey.f1: TerminalKey.f1,
      LogicalKeyboardKey.f2: TerminalKey.f2,
      LogicalKeyboardKey.f3: TerminalKey.f3,
      LogicalKeyboardKey.f4: TerminalKey.f4,
      LogicalKeyboardKey.f5: TerminalKey.f5,
      LogicalKeyboardKey.f6: TerminalKey.f6,
      LogicalKeyboardKey.f7: TerminalKey.f7,
      LogicalKeyboardKey.f8: TerminalKey.f8,
      LogicalKeyboardKey.f9: TerminalKey.f9,
      LogicalKeyboardKey.f10: TerminalKey.f10,
      LogicalKeyboardKey.f11: TerminalKey.f11,
      LogicalKeyboardKey.f12: TerminalKey.f12,
    };
    return keyMap[key];
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        final terminalKey = _mapLogicalKey(event.logicalKey);

        if (terminalKey != null) {
          terminal.keyInput(
            terminalKey,
            ctrl: HardwareKeyboard.instance.isControlPressed,
            shift: HardwareKeyboard.instance.isShiftPressed,
            alt: HardwareKeyboard.instance.isAltPressed,
          );
          return KeyEventResult.handled;
        } else if (event.character != null && event.character!.isNotEmpty) {
          terminal.textInput(event.character!);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: TerminalView(
        terminal,
        autofocus: false,
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    shell?.close();
    client?.close();
    super.dispose();
  }
}