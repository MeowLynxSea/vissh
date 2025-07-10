import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:vissh/models/credentials.dart';
import 'package:vissh/models/process_info.dart';

class TaskManagerPage extends StatefulWidget {
  final SSHCredentials credentials;
  const TaskManagerPage({super.key, required this.credentials});

  @override
  State<TaskManagerPage> createState() => _TaskManagerPageState();
}

class _TaskManagerPageState extends State<TaskManagerPage> {
  int _selectedIndex = 0;
  bool _isExpanded = false;

  SSHClient? _client;
  List<ProcessInfo> _processes = [];
  Map<String, ProcessInfo> _previousProcesses = {};

  double _totalCpuUsage = 0.0;
  double _totalMemUsage = 0.0;
  double _totalDiskPercentage = 0.0;

  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  final int _refreshInterval = 5;

  int? _totalMemoryKB;

  int _sortColumnIndex = 0;
  bool _isAscending = true;

  String? _selectedPid;
  bool _isRunTaskDialogVisible = false;

  final List<double> _columnWidths = [250.0, 90.0, 90.0, 90.0, 90.0, 50.0];
  final List<double> _minColumnWidths = [150.0, 90.0, 90.0, 90.0, 90.0, 20.0];
  final List<String> _columnTitles = ['名称', 'PID', 'CPU', '内存', '磁盘', ''];

  final double _headerHeight = 56.0;
  final double _rowHeight = 36.0;
  final double _resizerWidth = 6.0;
  final Color _borderColor = Colors.white.withValues(alpha: 0.2);

  @override
  void initState() {
    super.initState();
    _connectAndFetch();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
      if (mounted) {
        _fetchProcessInfo();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _client?.close();
    super.dispose();
  }

  Future<void> _connectAndFetch() async {
    try {
      final socket = await SSHSocket.connect(widget.credentials.host, widget.credentials.port);
      _client = SSHClient(
        socket,
        username: widget.credentials.username,
        onPasswordRequest: () => widget.credentials.password,
      );
      await _getTotalMemory();
      await _fetchProcessInfo();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '无法连接到服务器: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getTotalMemory() async {
    if (_client == null) return;
    try {
      final result = await _client!.run('cat /proc/meminfo');
      final meminfo = utf8.decode(result);
      final memTotalLine = meminfo.split('\n').firstWhere((line) => line.startsWith('MemTotal:'));
      final parts = memTotalLine.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        _totalMemoryKB = int.tryParse(parts[1]);
      }
    } catch (e) { /* ... */ }
  }

  Future<void> _fetchProcessInfo() async {
    if (_client == null) return;

    if (mounted && _processes.isEmpty) {
      setState(() { _isLoading = true; });
    }

    try {
      const command = r'''
      export LC_ALL=C;
      ps -eo pid,user,%cpu,%mem,comm --no-headers | while read pid user cpu mem comm; do
        if [ -f /proc/$pid/io ]; then
          io_stats=$(cat /proc/$pid/io)
          read_bytes=$(echo "$io_stats" | grep 'read_bytes:' | awk '{print $2}')
          write_bytes=$(echo "$io_stats" | grep 'write_bytes:' | awk '{print $2}')
        else
          read_bytes=0
          write_bytes=0
        fi
        echo "$pid|$user|$cpu|$mem|$comm|$read_bytes|$write_bytes"
      done
      ''';

      final result = await _client!.run(command);
      final output = utf8.decode(result);
      final lines = output.trim().split('\n');

      var tempProcesses = <Map<String, dynamic>>[];
      double tempTotalCpu = 0;
      double tempTotalMem = 0;
      double totalCurrentDiskSpeed = 0;

      for (var line in lines) {
        final parts = line.split('|');
        if (parts.length < 7) continue;

        final pid = parts[0];
        final cpuUsage = double.tryParse(parts[2]) ?? 0.0;
        final memUsagePercent = double.tryParse(parts[3]) ?? 0.0;
        
        final readBytes = int.tryParse(parts[5]) ?? 0;
        final writeBytes = int.tryParse(parts[6]) ?? 0;

        double diskSpeed = 0;
        if (_previousProcesses.containsKey(pid)) {
          final previous = _previousProcesses[pid]!;
          final readDiff = readBytes - previous.diskReadBytes;
          final writeDiff = writeBytes - previous.diskWriteBytes;
          diskSpeed = (readDiff + writeDiff) / _refreshInterval;
        }

        tempTotalCpu += cpuUsage;
        tempTotalMem += memUsagePercent;
        totalCurrentDiskSpeed += (diskSpeed < 0 ? 0 : diskSpeed);

        tempProcesses.add({
          'pid': pid,
          'user': parts[1],
          'cpuUsage': cpuUsage,
          'memUsage': memUsagePercent,
          'command': parts[4],
          'readBytes': readBytes,
          'writeBytes': writeBytes,
          'diskSpeed': diskSpeed < 0 ? 0 : diskSpeed,
        });
      }
      
      const double baselineDiskSpeed = 100 * 1024 * 1024;
      final double maxScaleSpeed = max(totalCurrentDiskSpeed, baselineDiskSpeed);

      _processes = tempProcesses.map((data) {
        double diskUsagePercentage = 0;
        if (maxScaleSpeed > 0) {
          diskUsagePercentage = (data['diskSpeed'] / maxScaleSpeed) * 100;
        }

        double memInMB = 0.0;
        if(_totalMemoryKB != null) {
          memInMB = (_totalMemoryKB! * (data['memUsage'] / 100)) / 1024;
        }

        return ProcessInfo(
          pid: data['pid'],
          user: data['user'],
          cpuUsage: data['cpuUsage'],
          memUsage: data['memUsage'],
          command: data['command'],
          memInMB: memInMB,
          diskReadBytes: data['readBytes'],
          diskWriteBytes: data['writeBytes'],
          diskSpeed: data['diskSpeed'],
          diskUsagePercentage: diskUsagePercentage,
        );
      }).toList();

      _sortProcesses();

      _previousProcesses = { for (var p in _processes) p.pid : p };

      if (mounted) {
        setState(() { 
          _totalCpuUsage = tempTotalCpu;
          _totalMemUsage = tempTotalMem;
          _totalDiskPercentage = (totalCurrentDiskSpeed / maxScaleSpeed) * 100;
          _isLoading = false; 
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '获取进程信息失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _sortProcesses() {
    _processes.sort((a, b) {
      int compare;
      switch (_sortColumnIndex) {
        case 0: compare = a.command.toLowerCase().compareTo(b.command.toLowerCase()); break;
        case 1: compare = int.parse(a.pid).compareTo(int.parse(b.pid)); break;
        case 2: compare = a.cpuUsage.compareTo(b.cpuUsage); break;
        case 3: compare = a.memUsage.compareTo(b.memUsage); break;
        case 4: compare = a.diskUsagePercentage.compareTo(b.diskUsagePercentage); break;
        default: compare = a.command.toLowerCase().compareTo(b.command.toLowerCase());
      }
      return _isAscending ? compare : -compare;
    });
  }

  void _onSort(int columnIndex) {
    if(columnIndex >= _columnTitles.length -1) return;

    setState(() {
      if (_sortColumnIndex == columnIndex) {
        if (_isAscending) { _isAscending = false; } 
        else { _sortColumnIndex = 0; _isAscending = true; }
      } else {
        _sortColumnIndex = columnIndex;
        _isAscending = true;
      }
      _sortProcesses();
    });
  }

  Future<void> _endSelectedTask() async {
    if (_client == null || _selectedPid == null) return;

    final pid = _selectedPid;

    try {
      await _client!.run('kill $pid');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已向进程 $pid 发送结束信号。')),
        );
        setState(() {
          _selectedPid = null;
        });
        await _fetchProcessInfo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('结束任务 $pid 失败: $e', style: const TextStyle(color: Colors.red))),
        );
      }
    }
  }

  Future<void> _runNewTask(String command) async {
    if (_client == null) return;
    try {
      final bgCommand = 'nohup $command > /dev/null 2>&1 &';
      await _client!.run(bgCommand);
      
      if (mounted) {
        setState(() {
          _isRunTaskDialogVisible = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('任务 "$command" 已在后台运行。')),
        );
        await Future.delayed(const Duration(seconds: 1));
        await _fetchProcessInfo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('运行任务 "$command" 失败: $e', style: const TextStyle(color: Colors.red))),
        );
      }
    }
  }

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
                    border: Border(
                        right: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2)))),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    IconButton(
                      icon: Icon(
                        _isExpanded ? Icons.menu_open : Icons.menu,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: _isExpanded ? '收起' : '展开',
                      onPressed: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildNavItem(icon: Icons.apps, text: '应用', index: 0),
                    _buildNavItem(
                        icon: Icons.bar_chart, text: '性能', index: 1),
                    _buildNavItem(
                        icon: Icons.settings_applications,
                        text: '服务',
                        index: 2),
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
                  children: [
                    _buildPageContent(),
                    const Placeholder(
                        child: Center(
                            child: Text("性能页面",
                                style: TextStyle(color: Colors.white)))),
                    const Placeholder(
                        child: Center(
                            child: Text("服务页面",
                                style: TextStyle(color: Colors.white)))),
                  ],
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            const SizedBox(height: 16),
            Expanded(child: _buildResizableProcessTable()),
          ],
        ),
        if (_isRunTaskDialogVisible)
          _RunTaskDialog(
            onRun: _runNewTask,
            onCancel: () {
              setState(() {
                _isRunTaskDialogVisible = false;
              });
            },
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('进程', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          Row(
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _isRunTaskDialogVisible = true;
                  });
                },
                child: const Text('运行新任务', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _selectedPid == null ? null : _endSelectedTask,
                style: ButtonStyle(
                  side: WidgetStateProperty.resolveWith<BorderSide>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return BorderSide(color: Colors.grey.withValues(alpha: 0.5));
                      }
                      return BorderSide(color: Colors.white.withValues(alpha: 0.5));
                    },
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return Colors.grey.withValues(alpha: 0.8);
                      }
                      return Colors.white;
                    },
                  ),
                ),
                child: const Text('结束任务'),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildResizableProcessTable() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
          child:
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }
    
    final double totalWidth = _columnWidths.reduce((a, b) => a + b) + ((_columnTitles.length - 1) * _resizerWidth);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTableHeader(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _processes.length,
                    itemExtent: _rowHeight,
                    itemBuilder: (context, index) {
                      return _buildTableRow(_processes[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      height: _headerHeight,
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _borderColor))),
      child: Row(
        children: List.generate(_columnTitles.length, (index) {
          bool isLastColumn = index == _columnTitles.length - 1;
          
          Widget headerContent;
          switch(index) {
            case 2:
              headerContent = _buildDoubleLineHeader(
                '${_totalCpuUsage.toStringAsFixed(0)}%', 
                _columnTitles[index], 
                index
              );
              break;
            case 3:
              headerContent = _buildDoubleLineHeader(
                '${_totalMemUsage.toStringAsFixed(0)}%', 
                _columnTitles[index], 
                index
              );
              break;
            case 4:
              headerContent = _buildDoubleLineHeader(
                '${_totalDiskPercentage.toStringAsFixed(0)}%',
                _columnTitles[index], 
                index
              );
              break;
            default:
              headerContent = _buildSingleLineHeader(_columnTitles[index], index);
          }

          return Row(
            children: [
              InkWell(
                onTap: () => _onSort(index),
                child: Container(
                  width: _columnWidths[index],
                  height: _headerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: headerContent,
                ),
              ),
              if (!isLastColumn)
                GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final newWidth = _columnWidths[index] + details.delta.dx;
                      if (newWidth > _minColumnWidths[index]) {
                        _columnWidths[index] = newWidth;
                      }
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: Container(
                      width: _resizerWidth,
                      height: _headerHeight,
                      alignment: Alignment.center,
                      child: Container(
                        width: 1,
                        color: _borderColor,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSingleLineHeader(String title, int index) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          if (_sortColumnIndex == index)
            Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  Widget _buildDoubleLineHeader(String topText, String bottomText, int index) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(topText, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(bottomText, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            if (_sortColumnIndex == index)
              Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.white, size: 16),
          ],
        ),
      ],
    );
  }

  Widget _buildTableRow(ProcessInfo process) {
    final bool isSelected = process.pid == _selectedPid;
    return Material(
      color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedPid = null;
            } else {
              _selectedPid = process.pid;
            }
          });
        },
        child: Container(
          height: _rowHeight,
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor.withValues(alpha: 0.1)))),
          child: Row(
            children: List.generate(_columnTitles.length, (index) {
              switch(index) {
                case 3: return _buildMemoryCell(process, index);
                case 4: return _buildDiskCell(process, index);
              }

              String text = '';
              switch(index) {
                case 0: text = process.command; break;
                case 1: text = process.pid; break;
                case 2: text = '${process.cpuUsage.toStringAsFixed(1)}%'; break;
                default: text = ''; break;
              }
              return _buildTableCell(Text(text), index);
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildDiskCell(ProcessInfo process, int columnIndex) {
    final text = '${process.diskUsagePercentage.toStringAsFixed(1)}%';
    final tooltipMessage = _formatSpeed(process.diskSpeed);
    
    return _buildTableCell(
      Tooltip(
        message: tooltipMessage,
        child: Text(text),
      ), 
      columnIndex
    );
  }
  
  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(1)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  Widget _buildMemoryCell(ProcessInfo process, int columnIndex) {
    final text = '${process.memUsage.toStringAsFixed(1)}%';
    final tooltipMessage = '${process.memInMB.toStringAsFixed(1)} MB';
    
    return _buildTableCell(
      Tooltip(
        message: tooltipMessage,
        child: Text(text),
      ), 
      columnIndex
    );
  }

  Widget _buildTableCell(Widget child, int columnIndex) {
    bool isLastColumn = columnIndex == _columnTitles.length - 1;
    return Row(
      children: [
        Container(
          width: _columnWidths[columnIndex],
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            child: child,
          ),
        ),
        if (!isLastColumn)
          Container(
            width: _resizerWidth,
            height: _rowHeight,
            alignment: Alignment.center,
            child: Container(
              width: 1,
              height: _rowHeight * 0.6,
              color: _borderColor.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }

  Widget _buildNavItem(
      {required IconData icon, required String text, required int index}) {
    final isSelected = _selectedIndex == index;

    return Tooltip(
      message: text,
      waitDuration: _isExpanded
          ? const Duration(days: 1)
          : const Duration(milliseconds: 500),
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
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(width: 4.0),
                    Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 20,
                      ),
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


class _RunTaskDialog extends StatefulWidget {
  final Function(String) onRun;
  final VoidCallback onCancel;

  const _RunTaskDialog({required this.onRun, required this.onCancel});

  @override
  State<_RunTaskDialog> createState() => _RunTaskDialogState();
}

class _RunTaskDialogState extends State<_RunTaskDialog> {
  final _commandController = TextEditingController();

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onCancel,
        child: Material(
          color: Colors.black.withValues(alpha: 0.5),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 350,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B2B),
                  borderRadius: BorderRadius.circular(8),
                   boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                    )
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('运行新任务', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _commandController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '输入要运行的指令',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[700]!),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: widget.onCancel,
                          child: const Text('取消', style: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (_commandController.text.isNotEmpty) {
                              widget.onRun(_commandController.text);
                            }
                          },
                          child: const Text('运行'),
                        ),
                      ],
                    )
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