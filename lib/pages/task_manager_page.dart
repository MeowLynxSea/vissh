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

  CpuStaticInfo? _cpuStaticInfo;
  CpuDynamicInfo _cpuDynamicInfo = CpuDynamicInfo.initial();
  List<List<double>> _perCpuHistory = [];
  List<int>? _lastTotalCpuTimes;
  List<List<int>>? _lastPerCpuTimes;

  int? _totalMemoryKB;
  
  int _selectedPerformanceMetricIndex = 0;
  final Map<String, List<double>> _metricHistory = {
    'cpu': [],
    'memory': [],
    'disk': [],
    'network': [0.0],
  };

  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  final int _refreshInterval = 3;

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

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _connectAndFetch();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
      if (mounted) {
        _fetchProcessInfo();
        _fetchCpuPerformanceInfo();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _client?.close();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
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
      await _fetchCpuStaticInfo(); 
      await _fetchCpuPerformanceInfo();
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

  Future<void> _fetchCpuStaticInfo() async {
    if (_client == null) return;
    try {
      final result = await _client!.run('lscpu');
      final output = utf8.decode(result);
      final lines = output.split('\n');
      final cpuMap = <String, String>{};
      for (var line in lines) {
        final parts = line.split(':');
        if (parts.length == 2) {
          cpuMap[parts[0].trim()] = parts[1].trim();
        }
      }

      String modelName = cpuMap['Model name'] ?? '未知';
      final baseSpeedMatch = RegExp(r'@\s*([\d.]+GHz)').firstMatch(modelName);
      final baseSpeed = baseSpeedMatch?.group(1) ?? '${(double.tryParse(cpuMap['CPU max MHz'] ?? '0') ?? 0) / 1000} GHz';
      
      final threads = int.tryParse(cpuMap['CPU(s)'] ?? '0') ?? 0;

      setState(() {
        _cpuStaticInfo = CpuStaticInfo(
          modelName: modelName.split('@')[0].trim(),
          architecture: cpuMap['Architecture'] ?? '未知',
          baseSpeed: baseSpeed,
          sockets: int.tryParse(cpuMap['Socket(s)'] ?? '1') ?? 1,
          cores: int.tryParse(cpuMap['Core(s) per socket'] ?? '0') ?? 0,
          threads: threads,
          virtualization: cpuMap['Virtualization'] ?? '不支持',
          l1dCache: cpuMap['L1d cache'] ?? 'N/A',
          l1iCache: cpuMap['L1i cache'] ?? 'N/A',
          l2Cache: cpuMap['L2 cache'] ?? 'N/A',
          l3Cache: cpuMap['L3 cache'] ?? 'N/A',
        );
        _perCpuHistory = List.generate(threads, (_) => []);
      });
    } catch (e) { /* ... */ }
  }

  Future<double> _fetchCpuSpeed() async {
    if (_client == null) return 0.0;

    try {
      final result = await _client!.run('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq');
      final speedKHz = double.tryParse(utf8.decode(result).trim()) ?? 0.0;
      if (speedKHz > 0) return speedKHz / 1000000.0;
    } catch (e) { /* ... */ }

    try {
      final result = await _client!.run('lscpu');
      final output = utf8.decode(result);
      final lines = output.split('\n');
      final mhzLine = lines.firstWhere(
        (line) => line.contains('CPU MHz:'),
        orElse: () => '',
      );
      if (mhzLine.isNotEmpty) {
        final speedMHz = double.tryParse(mhzLine.split(':').last.trim()) ?? 0.0;
        if (speedMHz > 0) return speedMHz / 1000.0;
      }
    } catch (e) { /* ... */ }

    try {
      final result = await _client!.run('cat /proc/cpuinfo | grep "cpu MHz" | head -n 1');
      final output = utf8.decode(result);
      if (output.isNotEmpty) {
          final speedMHz = double.tryParse(output.split(':').last.trim()) ?? 0.0;
          if (speedMHz > 0) return speedMHz / 1000.0;
      }
    } catch (e) { /* ... */ }

    return 0.0;
  }
  
  Future<void> _fetchCpuPerformanceInfo() async {
    if (_client == null) return;
    try {
      final double currentSpeed = await _fetchCpuSpeed();

      const command = 'cat /proc/stat && echo "---" && cat /proc/uptime && echo "---" && cat /proc/sys/fs/file-nr | awk \'{print \$1}\' && echo "---" && ps -eLf --no-headers | wc -l';
      final result = await _client!.run(command);
      final parts = utf8.decode(result).split('---');
      if (parts.length < 4) return;

      final statLines = parts[0].trim().split('\n');
      final cpuLines = statLines.where((line) => line.startsWith('cpu')).toList();
      if (cpuLines.isEmpty) return;
      
      final totalCpuTimes = cpuLines[0].split(RegExp(r'\s+')).sublist(1).map((e) => int.tryParse(e) ?? 0).toList();
      double totalCpuUsage = 0;
      if (_lastTotalCpuTimes != null) {
        totalCpuUsage = _calculateCpuUsage(totalCpuTimes, _lastTotalCpuTimes!);
      }
      _lastTotalCpuTimes = totalCpuTimes;
      _updateHistory('cpu', totalCpuUsage.clamp(0.0, 100.0));

      final perCpuTimes = <List<int>>[];
      if (cpuLines.length > 1) {
        for(int i = 1; i < cpuLines.length; i++) {
          final coreTimes = cpuLines[i].split(RegExp(r'\s+')).sublist(1).map((e) => int.tryParse(e) ?? 0).toList();
          perCpuTimes.add(coreTimes);
          if (_lastPerCpuTimes != null && _lastPerCpuTimes!.length > (i - 1)) {
            final coreUsage = _calculateCpuUsage(coreTimes, _lastPerCpuTimes![i-1]);
            if(_perCpuHistory.length > (i - 1)) {
              var history = _perCpuHistory[i-1];
              history.add(coreUsage.clamp(0.0, 100.0));
              if (history.length > 60) {
                 history.removeAt(0);
              }
              _perCpuHistory[i-1] = List.from(history);
            }
          } else {
            if(_perCpuHistory.length > (i - 1)) {
              _perCpuHistory[i-1] = [0.0];
            }
          }
        }
        _lastPerCpuTimes = perCpuTimes;
      }
      
      final uptimeSecondsStr = parts[1].trim().split(' ')[0];
      final totalSeconds = double.tryParse(uptimeSecondsStr)?.toInt() ?? 0;
      final days = totalSeconds ~/ (24 * 3600);
      final hours = (totalSeconds % (24 * 3600)) ~/ 3600;
      final minutes = (totalSeconds % 3600) ~/ 60;
      final seconds = totalSeconds % 60;
      final uptimeStr = '$days:${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      final handles = int.tryParse(parts[2].trim()) ?? 0;
      final totalThreads = int.tryParse(parts[3].trim()) ?? 0;
      
      if (mounted) {
        setState(() {
          _totalCpuUsage = totalCpuUsage;
          _cpuDynamicInfo = CpuDynamicInfo(
            currentSpeed: currentSpeed,
            utilization: totalCpuUsage,
            processes: _processes.length,
            threads: totalThreads,
            handles: handles,
            uptime: uptimeStr
          );
        });
      }
    } catch (e) {
      print('获取CPU动态信息失败: $e');
    }
  }

  double _calculateCpuUsage(List<int> current, List<int> previous) {
    final prevIdle = previous[3] + previous[4];
    final idle = current[3] + current[4];

    num prevNonIdle = 0;
    for (var i in [0, 1, 2, 5, 6, 7]) { prevNonIdle += previous.length > i ? previous[i] : 0; }
    num nonIdle = 0;
    for (var i in [0, 1, 2, 5, 6, 7]) { nonIdle += current.length > i ? current[i] : 0; }

    final prevTotal = prevIdle + prevNonIdle;
    final total = idle + nonIdle;

    final totalDiff = total - prevTotal;
    final idleDiff = idle - prevIdle;

    if (totalDiff == 0) return 0.0;
    
    return ((totalDiff - idleDiff) / totalDiff) * 100.0;
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
      double tempTotalMem = 0;
      double totalCurrentDiskSpeed = 0;

      final int cpuThreads = _cpuStaticInfo?.threads ?? 1;

      for (var line in lines) {
        final parts = line.split('|');
        if (parts.length < 7) continue;

        final pid = parts[0];
        
        final rawCpuUsage = double.tryParse(parts[2]) ?? 0.0;
        final cpuUsage = (cpuThreads > 0) ? (rawCpuUsage / cpuThreads) : rawCpuUsage;
        
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
          _totalMemUsage = tempTotalMem;
          _totalDiskPercentage = (totalCurrentDiskSpeed / maxScaleSpeed) * 100;
          _isLoading = false;

          _updateHistory('memory', _totalMemUsage);
          _updateHistory('disk', _totalDiskPercentage > 100 ? 100 : _totalDiskPercentage);
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

  void _updateHistory(String key, double value) {
    const historyLength = 60;
    if (!_metricHistory.containsKey(key)) {
      _metricHistory[key] = [];
    }
    _metricHistory[key]!.add(value);
    if (_metricHistory[key]!.length > historyLength) {
      _metricHistory[key]!.removeAt(0);
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
      body: Stack(
        children: [
          Row(
            children: [
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
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: switch (_selectedIndex) {
                        0 => KeyedSubtree(key: const ValueKey<int>(0), child: _buildPageContent()),
                        1 => KeyedSubtree(key: const ValueKey<int>(1), child: _buildPerformancePage()),
                        _ => KeyedSubtree(
                            key: const ValueKey<int>(2),
                            child: const Center(
                              child: Text("服务页面", style: TextStyle(color: Colors.white)),
                            ),
                          ),
                      },
                    )),
              ),
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
      ),
    );
  }

  Widget _buildPerformancePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPerformanceTopBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPerformanceSidebar(),
              Expanded(
                child: _buildPerformanceDetails(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTopBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('性能', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
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
                onPressed: () => {},
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
                child: const Text('复制'),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPerformanceSidebar() {
    final cpuUtilization = _totalCpuUsage > 100.0 ? 100.0 : _totalCpuUsage;
    final memoryUtilization = _totalMemUsage;
    final diskUtilization = _totalDiskPercentage > 100.0 ? 100.0 : _totalDiskPercentage;

    final totalMemoryGB = _totalMemoryKB != null ? (_totalMemoryKB! / (1024 * 1024)) : 0.0;
    final usedMemoryGB = totalMemoryGB * (memoryUtilization / 100);
    
    return Container(
      width: 280, 
      padding: const EdgeInsets.only(top: 8.0),
      color: Colors.white.withValues(alpha: 0.02),
      child: ListView(
        children: [
          _buildMetricTile(
            index: 0,
            title: 'CPU',
            utilization: cpuUtilization,
            detailsLine1: "${cpuUtilization.toStringAsFixed(0)}%",
            detailsLine2: "${_cpuDynamicInfo.currentSpeed.toStringAsFixed(2)} GHz",
            historyData: _metricHistory['cpu'] ?? [],
            color: const Color(0xFF1B66B1),
          ),
          _buildMetricTile(
            index: 1,
            title: '内存',
            utilization: memoryUtilization,
            detailsLine1: "${usedMemoryGB.toStringAsFixed(1)}/${totalMemoryGB.toStringAsFixed(1)} GB",
            detailsLine2: "${memoryUtilization.toStringAsFixed(0)}%",
            historyData: _metricHistory['memory'] ?? [],
            color: const Color(0xFF8635A8),
          ),
           _buildMetricTile(
            index: 2,
            title: '磁盘 0 (E:)',
            utilization: diskUtilization,
            detailsLine1: "SSD (NVMe)",
            detailsLine2: "${diskUtilization.toStringAsFixed(0)}%", 
            historyData: _metricHistory['disk'] ?? [],
            color: const Color(0xFF4E731C),
          ),
           _buildMetricTile(
            index: 3,
            title: 'Wi-Fi',
            utilization: 5.0,
            detailsLine1: "WLAN",
            detailsLine2: "发送: 56.0 接收: 72.0 Kbps",
            historyData: _metricHistory['network'] ?? [],
            color: const Color(0xFFB86A1A),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required int index,
    required String title,
    required double utilization,
    required String detailsLine1,
    required String detailsLine2,
    required List<double> historyData,
    required Color color,
  }) {
    final isSelected = _selectedPerformanceMetricIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPerformanceMetricIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(4.0),
          border: isSelected ? Border(left: BorderSide(color: color, width: 2)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: CustomPaint(
                painter: SparklinePainter(data: historyData, color: color),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(detailsLine1, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  Text(detailsLine2, style: TextStyle(color: Colors.grey[500], fontSize: 11), overflow: TextOverflow.ellipsis,),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceDetails() {
    return switch (_selectedPerformanceMetricIndex) {
      0 => _buildCpuDetailsPage(),
      _ => _buildPlaceholderDetailsPage(),
    };
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

  Widget _buildCpuDetailsPage() {
    if (_cpuStaticInfo == null) {
      return const Center(child: Text('正在加载CPU信息...', style: TextStyle(color: Colors.white70)));
    }

    final titleStyle = const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300);

    return Scrollbar(
      controller: _verticalScrollController,
      child: ListView(
        controller: _verticalScrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('CPU', style: titleStyle),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _cpuStaticInfo!.modelName,
                  textAlign: TextAlign.end,
                  style: titleStyle.copyWith(fontSize: 16, height: 1.8),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2,
            ),
            itemCount: _cpuStaticInfo!.threads,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: CustomPaint(
                  painter: SparklinePainter(
                    data: _perCpuHistory.length > index ? _perCpuHistory[index] : [],
                    color: const Color(0xFF1B66B1),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Scrollbar(
            controller: _horizontalScrollController,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 550),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildStatItem('利用率', '${_cpuDynamicInfo.utilization.toStringAsFixed(0)} %'),
                              const SizedBox(width: 16),
                              _buildStatItem('速度', '${_cpuDynamicInfo.currentSpeed.toStringAsFixed(2)} GHz'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildStatItem('进程', _cpuDynamicInfo.processes.toString()),
                              const SizedBox(width: 16),
                              _buildStatItem('线程', _cpuDynamicInfo.threads.toString()),
                              const SizedBox(width: 16),
                              _buildStatItem('句柄', _cpuDynamicInfo.handles.toString()),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildStatItem('正常运行时间', _cpuDynamicInfo.uptime, isLast: true),
                        ],
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHardwareInfoItem('基准速度: ', _cpuStaticInfo!.baseSpeed),
                            _buildHardwareInfoItem('插槽: ', _cpuStaticInfo!.sockets.toString()),
                            _buildHardwareInfoItem('内核: ', _cpuStaticInfo!.cores.toString()),
                            _buildHardwareInfoItem('逻辑处理器: ', _cpuStaticInfo!.threads.toString()),
                            _buildHardwareInfoItem('虚拟化: ', _cpuStaticInfo!.virtualization),
                            _buildHardwareInfoItem('L1 缓存: ', '${_cpuStaticInfo!.l1dCache} (D) / ${_cpuStaticInfo!.l1iCache} (I)'),
                            _buildHardwareInfoItem('L2 缓存: ', _cpuStaticInfo!.l2Cache),
                            _buildHardwareInfoItem('L3 缓存: ', _cpuStaticInfo!.l3Cache),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500)),
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildHardwareInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPlaceholderDetailsPage() {
    String title;
    switch (_selectedPerformanceMetricIndex) {
      case 1: title = '内存'; break;
      case 2: title = '磁盘 0 (E:)'; break;
      case 3: title = 'Wi-Fi'; break;
      default: title = '详情';
    }

    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  '详细图表和统计信息占位符',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ),
        ],
      ),
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
        return Scrollbar(
          controller: _horizontalScrollController,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTableHeader(),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemCount: _processes.length,
                        itemExtent: _rowHeight,
                        itemBuilder: (context, index) {
                          return _buildTableRow(_processes[index]);
                        },
                      ),
                    ),
                  ),
                ],
              ),
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

class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.05)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    const maxValue = 100.0;
    
    final path = Path();
    final fillPath = Path();

    double stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      double value = data[i].clamp(0.0, maxValue);
      double x = i * stepX;
      double y = size.height - (value / maxValue * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}