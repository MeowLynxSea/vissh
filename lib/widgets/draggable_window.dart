import 'dart:ui';
import 'package:flutter/material.dart';

const double _kTitleBarHeight = 24.0;
const double _kResizeHandleSize = 8.0;
const double _kMinWindowWidth = 200.0;
const double _kMinWindowHeight = 150.0;

class DraggableWindow extends StatefulWidget {
  final String id;
  final Offset initialPosition;
  final Size initialSize;
  final String title;
  final Widget child;
  final IconData icon;
  final bool isActive;
  final bool isMaximized;
  final bool isMinimized;
  final Function(String, bool) onMaximizeChanged;
  final Function(String) onBringToFront;
  final Function(String) onClose;
  final Function(String) onMinimize;
  final Function(String, Offset) onMove;
  final Function(String, Size) onResize;

  const DraggableWindow({
    super.key,
    required this.id,
    required this.initialPosition,
    required this.initialSize,
    required this.title,
    required this.child,
    required this.icon,
    required this.isActive,
    required this.onBringToFront,
    required this.onClose,
    required this.onMinimize,
    required this.isMinimized,
    required this.onMove,
    required this.onResize,
    required this.isMaximized,
    required this.onMaximizeChanged,
  });

  @override
  DraggableWindowState createState() => DraggableWindowState();
}

class DraggableWindowState extends State<DraggableWindow> {
  late double _top;
  late double _left;
  late double _width;
  late double _height;

  bool _isMaximized = false;
  late double _preMaximizedTop;
  late double _preMaximizedLeft;
  late double _preMaximizedWidth;
  late double _preMaximizedHeight;

  late double _preDragTop;
  late double _preDragLeft;

  bool _isClosing = false;
  bool _isOpening = true;

  bool _showMaximizePreview = false;
  Duration _animationDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _top = widget.initialPosition.dy;
    _left = widget.initialPosition.dx;
    _width = widget.initialSize.width;
    _height = widget.initialSize.height;

    _isMaximized = widget.isMaximized;

    if (_isMaximized) {
      _preMaximizedTop = _top;
      _preMaximizedLeft = _left;
      _preMaximizedWidth = _width;
      _preMaximizedHeight = _height;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final screenSize = MediaQuery.of(context).size;
          setState(() {
            _animationDuration = Duration.zero;
            _top = 0;
            _left = 0;
            _width = screenSize.width;
            _height = screenSize.height - 48.0;
          });
        }
      });
    }

    _preDragTop = _top;
    _preDragLeft = _left;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant DraggableWindow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isMinimized && !widget.isMinimized) {
      if (_isClosing) {
        setState(() {
          _isClosing = false;
        });
      }
    }

    if (widget.initialPosition != oldWidget.initialPosition) {
      _top = widget.initialPosition.dy;
      _left = widget.initialPosition.dx;
    }
    if (widget.initialSize != oldWidget.initialSize) {
      _width = widget.initialSize.width;
      _height = widget.initialSize.height;
    }
  }

  void _animateAndClose() {
    if (!mounted) return;
    setState(() {
      _isClosing = true;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onClose(widget.id);
    });
  }

  void animateAndMinimize() {
    if (!mounted) return;
    setState(() {
      _isClosing = true;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onMinimize(widget.id);
    });
  }

  void _toggleMaximize() {
    setState(() {
      _animationDuration = const Duration(milliseconds: 100);
      if (_isMaximized) {
        _top = _preMaximizedTop;
        _left = _preMaximizedLeft;
        _width = _preMaximizedWidth;
        _height = _preMaximizedHeight;
        _isMaximized = false;
        widget.onMove(widget.id, Offset(_left, _top));
        widget.onResize(widget.id, Size(_width, _height));
      } else {
        _preMaximizedTop = _top;
        _preMaximizedLeft = _left;
        _preMaximizedWidth = _width;
        _preMaximizedHeight = _height;

        final screenSize = MediaQuery.of(context).size;
        _top = 0;
        _left = 0;
        _width = screenSize.width;
        _height = screenSize.height - 48;
        _isMaximized = true;
      }
    });
    widget.onMaximizeChanged(widget.id, _isMaximized);
    widget.onBringToFront(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = _isMaximized ? BorderRadius.zero : BorderRadius.circular(8.0);

    const animationDuration = Duration(milliseconds: 100);
    const animationCurve = Curves.easeOut;

    return AnimatedOpacity(
      duration: animationDuration,
      curve: animationCurve,
      opacity: (_isClosing || _isOpening) ? 0.0 : 1.0,
      child: AnimatedContainer(
        duration: animationDuration,
        curve: animationCurve,
        transform: Matrix4.identity()..scale((_isClosing || _isOpening) ? 0.85 : 1.0),
        transformAlignment: Alignment.center,
        child: Stack(
          children: [
            if (_showMaximizePreview && !_isMaximized)
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showMaximizePreview ? 1.0 : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.0),
                    ),
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              top: _top,
              left: _left,
              width: _width,
              height: _height,
              child: GestureDetector(
                onPanDown: (details) => widget.onBringToFront(widget.id),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: _animationDuration,
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        boxShadow: _isMaximized ? [] : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: widget.isActive ? 0.4 : 0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: borderRadius,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: borderRadius,
                              border: _isMaximized ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              children: [
                                _buildTitleBar(),
                                Expanded(
                                  child: ClipRect(
                                    child: widget.child,
                                  )
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!_isMaximized) ..._buildResizeHandles(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    final titleBarColor = widget.isActive
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.05);

    return GestureDetector(
      onDoubleTap: _toggleMaximize,
      child: AnimatedContainer(
        duration: _animationDuration,
        height: _kTitleBarHeight,
        decoration: BoxDecoration(
          color: titleBarColor,
          borderRadius: _isMaximized
              ? BorderRadius.zero
              : const BorderRadius.only(
                  topLeft: Radius.circular(8.0),
                  topRight: Radius.circular(8.0),
                ),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Tooltip(
                message: '',
                child: Icon(
                  widget.icon,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 16,
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onPanStart: (details) {
                  widget.onBringToFront(widget.id);
                  if (_isMaximized) {
                    final mouseX = details.globalPosition.dx;
                    setState(() {
                      _isMaximized = false;
                      _animationDuration = Duration.zero;
                      _width = _preMaximizedWidth;
                      _height = _preMaximizedHeight;
                      _left = mouseX - (_width / 2);
                      _top = details.globalPosition.dy - (_kTitleBarHeight / 2);
                    });
                    widget.onMaximizeChanged(widget.id, false);
                  } else {
                    _preDragTop = _top;
                    _preDragLeft = _left;
                  }
                },
                onPanUpdate: (details) {
                  if (_isMaximized) return;
                  setState(() {
                    _animationDuration = Duration.zero;
                    _left += details.delta.dx;
                    _top += details.delta.dy;

                    if (details.globalPosition.dy < 5) {
                      if (!_showMaximizePreview) {
                        setState(() => _showMaximizePreview = true);
                      }
                    } else {
                      if (_showMaximizePreview) {
                        setState(() => _showMaximizePreview = false);
                      }
                    }
                  });
                },
                onPanEnd: (details) {
                  if (!_isMaximized) {
                    widget.onMove(widget.id, Offset(_left, _top));
                  }

                  if (_showMaximizePreview && !_isMaximized) {
                    setState(() {
                      _preMaximizedTop = _preDragTop;
                      _preMaximizedLeft = _preDragLeft;
                      _preMaximizedWidth = _width;
                      _preMaximizedHeight = _height;

                      final screenSize = MediaQuery.of(context).size;
                      _top = 0;
                      _left = 0;
                      _width = screenSize.width;
                      _height = screenSize.height - 48.0;
                      _isMaximized = true;
                      _animationDuration = const Duration(milliseconds: 100);
                    });
                    widget.onMaximizeChanged(widget.id, true);
                    widget.onBringToFront(widget.id);
                    widget.onMove(widget.id, Offset(_left, _top));
                    widget.onResize(widget.id, Size(_width, _height));
                  }
                  
                  if (_showMaximizePreview) {
                    setState(() {
                      _showMaximizePreview = false;
                    });
                  }
                },
                child: Text(
                  widget.title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w400, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _buildControlButton(Icons.minimize, animateAndMinimize, Colors.black12),
            _buildControlButton(
              _isMaximized ? Icons.filter_none : Icons.check_box_outline_blank,
              _toggleMaximize,
              Colors.black12
            ),
            _buildControlButton(Icons.close, _animateAndClose, Colors.redAccent, isLast: true,),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, Color hoverColor, {bool isLast = false}) {
  final BorderRadius borderRadius = isLast
      ? const BorderRadius.only(
          topRight: Radius.circular(8.0),
        )
      : BorderRadius.zero;

  return SizedBox(
    width: 40,
    height: _kTitleBarHeight,
    child: Material(
      color: Colors.transparent,
      borderRadius: borderRadius, 
      child: InkWell(
        hoverColor: hoverColor,
        onTap: onPressed,
        customBorder: RoundedRectangleBorder(
          borderRadius: borderRadius,
        ),
        child: Icon(icon, color: Colors.white, size: 12),
      ),
    ),
  );
}

  List<Widget> _buildResizeHandles() {
    void handleResizeEnd() {
      widget.onResize(widget.id, Size(_width, _height));
    }
    
    void handleMoveEnd() {
       widget.onMove(widget.id, Offset(_left, _top));
    }

    return [
      // Right-Bottom
      Positioned(
        right: 0,
        bottom: 0,
        width: _kResizeHandleSize,
        height: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDownRight,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                _width = (_width + details.delta.dx).clamp(_kMinWindowWidth, double.infinity);
                _height = (_height + details.delta.dy).clamp(_kMinWindowHeight, double.infinity);
              });
            },
            onPanEnd: (d) => handleResizeEnd(),
          ),
        ),
      ),
      // Right
      Positioned(
        right: 0,
        top: _kTitleBarHeight,
        bottom: _kResizeHandleSize,
        width: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeRight,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                _width = (_width + details.delta.dx).clamp(_kMinWindowWidth, double.infinity);
              });
            },
            onPanEnd: (d) => handleResizeEnd(),
          ),
        ),
      ),
      // Bottom
      Positioned(
        bottom: 0,
        left: _kResizeHandleSize,
        right: _kResizeHandleSize,
        height: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDown,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                _height = (_height + details.delta.dy).clamp(_kMinWindowHeight, double.infinity);
              });
            },
            onPanEnd: (d) => handleResizeEnd(),
          ),
        ),
      ),
      // Top
      Positioned(
        top: 0,
        left: _kResizeHandleSize,
        right: _kResizeHandleSize,
        height: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUp,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                final newHeight = (_height - details.delta.dy).clamp(_kMinWindowHeight, double.infinity);
                _top += _height - newHeight;
                _height = newHeight;
              });
            },
            onPanEnd: (d) { handleResizeEnd(); handleMoveEnd(); },
          ),
        ),
      ),
      // Left-Bottom
      Positioned(
        left: 0,
        bottom: 0,
        width: _kResizeHandleSize,
        height: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDownLeft,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                final newWidth = (_width - details.delta.dx).clamp(_kMinWindowWidth, double.infinity);
                _left += _width - newWidth;
                _width = newWidth;
                _height = (_height + details.delta.dy).clamp(_kMinWindowHeight, double.infinity);
              });
            },
            onPanEnd: (d) { handleResizeEnd(); handleMoveEnd(); },
          ),
        ),
      ),
      // Left
      Positioned(
        left: 0,
        top: _kTitleBarHeight,
        bottom: _kResizeHandleSize,
        width: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeft,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                final newWidth = (_width - details.delta.dx).clamp(_kMinWindowWidth, double.infinity);
                _left += _width - newWidth;
                _width = newWidth;
              });
            },
            onPanEnd: (d) { handleResizeEnd(); handleMoveEnd(); },
          ),
        ),
      ),
      // Left-Top
      Positioned(
        left: 0,
        top: 0,
        width: _kResizeHandleSize,
        height: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeft,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                final newWidth = (_width - details.delta.dx).clamp(_kMinWindowWidth, double.infinity);
                final newHeight = (_height - details.delta.dy).clamp(_kMinWindowHeight, double.infinity);
                _left += _width - newWidth;
                _top += _height - newHeight;
                _width = newWidth;
                _height = newHeight;
              });
            },
            onPanEnd: (d) { handleResizeEnd(); handleMoveEnd(); },
          ),
        ),
      ),
      // Right-Top
      Positioned(
        right: 0,
        top: 0,
        width: _kResizeHandleSize,
        height: _kResizeHandleSize,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpRight,
          child: GestureDetector(
            onPanStart: (d) { widget.onBringToFront(widget.id); _animationDuration = Duration.zero; },
            onPanUpdate: (details) {
              setState(() {
                final newHeight = (_height - details.delta.dy).clamp(_kMinWindowHeight, double.infinity);
                 _top += _height - newHeight;
                _width = (_width + details.delta.dx).clamp(_kMinWindowWidth, double.infinity);
                _height = newHeight;
              });
            },
            onPanEnd: (d) { handleResizeEnd(); handleMoveEnd(); },
          ),
        ),
      ),
    ];
  }
}