import 'package:flutter/material.dart';

class TaskManagerPage extends StatefulWidget {
  const TaskManagerPage({super.key});

  @override
  State<TaskManagerPage> createState() => _TaskManagerPageState();
}

class _TaskManagerPageState extends State<TaskManagerPage> {
  int _selectedIndex = 0;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    const collapsedWidth = 48.0;
    const expandedWidth = 108.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: _isExpanded ? expandedWidth : collapsedWidth,
            child: ClipRRect(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.2)))
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    IconButton(
                      icon: Icon(_isExpanded ? Icons.menu_open : Icons.menu, color: Colors.white, size: 20,),
                      tooltip: _isExpanded ? '收起' : '展开',
                      onPressed: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildNavItem(icon: Icons.apps, text: '应用', index: 0),
                    _buildNavItem(icon: Icons.bar_chart, text: '性能', index: 1),
                    _buildNavItem(icon: Icons.settings_applications, text: '服务', index: 2),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: IndexedStack(
                index: _selectedIndex,
                children: const [
                  Placeholder(child: Center(child: Text("应用页面", style: TextStyle(color: Colors.white)))),
                  Placeholder(child: Center(child: Text("性能页面", style: TextStyle(color: Colors.white)))),
                  Placeholder(child: Center(child: Text("服务页面", style: TextStyle(color: Colors.white)))),
                ],
              )
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({required IconData icon, required String text, required int index}) {
    final isSelected = _selectedIndex == index;

    return Tooltip(
      message: text,
      waitDuration: _isExpanded ? const Duration(days: 1) : const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: InkWell(
            onTap: () => setState(() => _selectedIndex = index),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(width: 4.0),
                    Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Icon(icon, color: Colors.white, size: 20,),
                    ),
                    if (_isExpanded)
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: _isExpanded ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeIn,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4.0),
                            child: Text(
                              text,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}