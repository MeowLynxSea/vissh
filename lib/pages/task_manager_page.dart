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

  MemoryInfo _memoryInfo = MemoryInfo.initial();

  CpuStaticInfo? _cpuStaticInfo;
  CpuDynamicInfo _cpuDynamicInfo = CpuDynamicInfo.initial();
  List<List<double>> _perCpuHistory = [];
  List<int>? _lastTotalCpuTimes;
  List<List<int>>? _lastPerCpuTimes;

  int? _totalMemoryKB;
  MemoryHardwareInfo _memoryHardwareInfo = MemoryInfo.initial().hardwareInfo;
  
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

  List<DiskInfo> _disks = [];
  Map<String, String> _previousDiskStats = {};
  DateTime? _lastDiskFetchTime;

  final List<double> _columnWidths = [250.0, 90.0, 90.0, 90.0, 90.0, 50.0];
  final List<double> _minColumnWidths = [150.0, 90.0, 90.0, 90.0, 90.0, 20.0];
  final List<String> _columnTitles = ['名称', 'PID', 'CPU', '内存', '磁盘', ''];

  final double _headerHeight = 56.0;
  final double _rowHeight = 36.0;
  final double _resizerWidth = 6.0;
  final Color _borderColor = Colors.white.withValues(alpha: 0.2);

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalMemoryScrollController = ScrollController();
  final ScrollController _horizontalDiskScrollController = ScrollController();


  @override
  void initState() {
    super.initState();
    _connectAndFetch();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
      if (mounted) {
        _fetchProcessInfo();
        _fetchCpuPerformanceInfo();
        if (_selectedIndex == 1) {
          _fetchMemoryDetails();
          _fetchDiskInfo();
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _client?.close();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _horizontalMemoryScrollController.dispose();
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
      await Future.wait([
        _fetchCpuStaticInfo(),
        _getTotalMemory(),
        _fetchMemoryDetails(),
        _fetchMemoryHardwareInfo(),
        _fetchDiskInfo(),
      ]);
      await _fetchCpuPerformanceInfo();
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

  Future<void> _fetchDiskInfo() async {
    if (_client == null) return;

    // 这个脚本现在是完全可靠的
    const command = r'''
    set -e
    export LC_ALL=C
    
    ROOT_DEV=$(df / | awk 'NR==2 {print $1}')
    SWAP_DEVS=$(swapon -s | awk 'NR>1 {print $1}')

    lsblk -b -p -o NAME,TYPE,SIZE,MODEL,MOUNTPOINT | grep 'disk' | while read -r line; do
      DEVICE_PATH=$(echo "$line" | awk '{print $1}')
      DEVICE_NAME=$(basename "$DEVICE_PATH")
      
      SIZE_BYTES=$(echo "$line" | awk '{print $3}')
      MODEL=$(echo "$line" | awk '{ for(i=4; i<NF; i++) printf "%s ", $i }' | xargs)
      MOUNTS=$(lsblk -n -o MOUNTPOINT "$DEVICE_PATH" | sed '/^$/d' | tr '\n' ' ' | xargs)

      if [ -f "/sys/block/$DEVICE_NAME/queue/rotational" ]; then
        IS_ROTATIONAL=$(cat "/sys/block/$DEVICE_NAME/queue/rotational")
        [ "$IS_ROTATIONAL" = "0" ] && TYPE="SSD" || TYPE="HDD"
      else
        TYPE="未知"
      fi

      IS_SYSTEM_DISK="否"
      echo "$ROOT_DEV" | grep -q "$DEVICE_NAME" && IS_SYSTEM_DISK="是"
      
      HAS_PAGE_FILE="否"
      for SWAP_DEV in $SWAP_DEVS; do
        echo "$SWAP_DEV" | grep -q "$DEVICE_NAME" && HAS_PAGE_FILE="是" && break
      done

      if [ -f "/proc/diskstats" ]; then
        DISK_STATS=$(grep -w "$DEVICE_NAME" /proc/diskstats)
      else
        DISK_STATS=""
      fi

      echo "START_DISK"
      echo "DEVICE_NAME:$DEVICE_NAME" # <--- 我们将使用这个 'sda', 'sdb' 等作为稳定ID
      echo "DEVICE_PATH:$DEVICE_PATH"
      echo "MOUNTS:$MOUNTS"
      echo "MODEL:$MODEL"
      echo "SIZE_BYTES:$SIZE_BYTES"
      echo "TYPE:$TYPE"
      echo "IS_SYSTEM_DISK:$IS_SYSTEM_DISK"
      echo "HAS_PAGE_FILE:$HAS_PAGE_FILE"
      echo "DISK_STATS:$DISK_STATS"
      echo "END_DISK"
    done
    ''';

    try {
      final result = await _client!.run(command);
      final output = utf8.decode(result);

      final now = DateTime.now();
      double intervalSeconds = 1.0;
      if (_lastDiskFetchTime != null) {
        intervalSeconds = now.difference(_lastDiskFetchTime!).inMilliseconds / 1000.0;
        if (intervalSeconds == 0) intervalSeconds = 1.0;
      }

      final currentDiskStats = <String, String>{};
      final newDisks = <DiskInfo>[];

      final diskBlocks = output.split("START_DISK").where((b) => b.isNotEmpty);

      for (var block in diskBlocks) {
        final lines = block.trim().split('\n');
        final diskData = <String, String>{};
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length > 1) {
            diskData[parts[0]] = parts.sublist(1).join(':');
          }
        }
        
        // --- FIX START: 使用内核设备名 ('sda' 等) 作为稳定ID ---
        final stableId = diskData['DEVICE_NAME'] ?? DateTime.now().toIso8601String(); // 使用 DEVICE_NAME 作为唯一、稳定的ID
        final statsLine = diskData['DISK_STATS'] ?? '';
        currentDiskStats[stableId] = statsLine;

        final mounts = diskData['MOUNTS']?.replaceAll('/ ', ' / ') ?? '';
        final displayName = '磁盘 ${newDisks.length} ($mounts)';

        final staticInfo = DiskStaticInfo(
          model: diskData['MODEL'] ?? '未知设备',
          type: diskData['TYPE'] ?? '未知',
          capacity: _formatBytes(int.tryParse(diskData['SIZE_BYTES'] ?? '0') ?? 0),
          formatted: _formatBytes(int.tryParse(diskData['SIZE_BYTES'] ?? '0') ?? 0),
          isSystemDisk: (diskData['IS_SYSTEM_DISK'] ?? '否') == '是',
          hasPageFile: (diskData['HAS_PAGE_FILE'] ?? '否') == '是',
        );

        DiskDynamicInfo dynamicInfo;
        
        // 关键修复：使用 stableId 进行查找
        final existingDisk = _disks.firstWhere(
          (d) => d.id == stableId,
          orElse: () => DiskInfo.initial(displayName, staticInfo.model, id: stableId),
        );
        
        final prevStats = _previousDiskStats[stableId];
        // --- FIX END ---
        
        if (statsLine.isNotEmpty && prevStats != null && prevStats.isNotEmpty) {
          final current = statsLine.trim().split(RegExp(r'\s+'));
          final previous = prevStats.trim().split(RegExp(r'\s+'));

          final readsCompleted = (int.tryParse(current[3]) ?? 0) - (int.tryParse(previous[3]) ?? 0);
          final writesCompleted = (int.tryParse(current[7]) ?? 0) - (int.tryParse(previous[7]) ?? 0);
          final readSectors = (int.tryParse(current[5]) ?? 0) - (int.tryParse(previous[5]) ?? 0);
          final writeSectors = (int.tryParse(current[9]) ?? 0) - (int.tryParse(previous[9]) ?? 0);
          final timeSpentIO = (int.tryParse(current[12]) ?? 0) - (int.tryParse(previous[12]) ?? 0);

          final totalIOs = readsCompleted + writesCompleted;
          final avgResponseTime = (totalIOs > 0) ? (timeSpentIO / totalIOs) : 0.0;
          
          final readSpeed = (readSectors * 512) / intervalSeconds;
          final writeSpeed = (writeSectors * 512) / intervalSeconds;
          final activeTimePercentage = (timeSpentIO / (intervalSeconds * 1000)) * 100;

          final activeTimeHistory = List<double>.from(existingDisk.dynamicInfo.activeTimeHistory)..add(activeTimePercentage.clamp(0, 100));
          if (activeTimeHistory.length > 60) activeTimeHistory.removeAt(0);

          final totalTransferSpeed = (readSpeed + writeSpeed) / (1024 * 1024);
          final transferRateHistory = List<double>.from(existingDisk.dynamicInfo.transferRateHistory)..add(totalTransferSpeed);
          if (transferRateHistory.length > 60) transferRateHistory.removeAt(0);

          dynamicInfo = existingDisk.dynamicInfo.copyWith(
            activeTimePercentage: activeTimePercentage,
            readSpeed: readSpeed / 1024,
            writeSpeed: writeSpeed / 1024,
            avgResponseTime: avgResponseTime,
            activeTimeHistory: activeTimeHistory,
            transferRateHistory: transferRateHistory,
            totalTransferSpeed: totalTransferSpeed,
          );

        } else {
          dynamicInfo = existingDisk.dynamicInfo;
        }

        // 关键修复：创建DiskInfo对象时传入stableId
        newDisks.add(DiskInfo(id: stableId, deviceName: displayName, staticInfo: staticInfo, dynamicInfo: dynamicInfo));
      }

      if (mounted) {
        setState(() {
          _disks = newDisks;
          _previousDiskStats = currentDiskStats;
          _lastDiskFetchTime = now;
        });
      }

    } catch (e) {
      // print('获取磁盘信息失败: $e');
    }
  }

  String _formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _fetchMemoryDetails() async {
    if (_client == null) return;
    try {
      final result = await _client!.run('cat /proc/meminfo');
      final meminfo = utf8.decode(result);
      final lines = meminfo.split('\n');
      final memMap = <String, int>{};
      for (var line in lines) {
        final parts = line.split(RegExp(r':\s*'));
        if (parts.length == 2) {
          final value = int.tryParse(parts[1].replaceAll(RegExp(r'\s*kB'), '').trim());
          if (value != null) {
            memMap[parts[0]] = value;
          }
        }
      }

      final total = memMap['MemTotal'] ?? 0;
      final free = memMap['MemFree'] ?? 0;
      final available = memMap['MemAvailable'] ?? 0;
      final used = total - available;
      final usedPercentage = total > 0 ? (used / total) * 100 : 0.0;

      final history = List<double>.from(_memoryInfo.usageHistory);
      history.add(usedPercentage);
      if (history.length > 60) {
        history.removeAt(0);
      }

      if (mounted) {
        setState(() {
          _memoryInfo = MemoryInfo(
            total: total,
            free: free,
            available: available,
            buffers: memMap['Buffers'] ?? 0,
            cached: memMap['Cached'] ?? 0,
            swapTotal: memMap['SwapTotal'] ?? 0,
            swapFree: memMap['SwapFree'] ?? 0,
            active: memMap['Active'] ?? 0,
            inactive: memMap['Inactive'] ?? 0,
            pagedPool: memMap['SReclaimable'] ?? 0, // 使用 SReclaimable 作为 Paged Pool
            nonPagedPool: memMap['SUnreclaim'] ?? 0, // 使用 SUnreclaim 作为 Non-paged Pool
            hardwareReserved: memMap['HardwareCorrupted'] ?? 0, // 使用 HardwareCorrupted 作为硬件保留
            usedPercentage: usedPercentage,
            usageHistory: history,
            hardwareInfo: _memoryInfo.hardwareInfo, // 保持已获取的硬件信息
          );
        });
      }
    } catch (e) { /* ... */ }
  }

  Future<void> _fetchMemoryHardwareInfo() async {
    if (_client == null) return;
    try {
      final result = await _client!.run('sudo dmidecode -t memory');
      final output = utf8.decode(result);
      final outputLower = output.toLowerCase();

      if (output.trim().isEmpty ||
          outputLower.contains('command not found') ||
          outputLower.contains('no smbios nor dmi entry point found')) {
        throw Exception('dmidecode failed or no SMBIOS data available');
      }

      String speed = '未知';
      String slots = '未知';
      String formFactor = '未知';

      var speedMatch = RegExp(r'Speed:\s*(\d+\s*MT/s)', caseSensitive: false).firstMatch(output);
      speedMatch ??= RegExp(r'Configured Memory Speed:\s*(\d+\s*MT/s)', caseSensitive: false).firstMatch(output);
      speedMatch ??= RegExp(r'Speed:\s*(\d+\s*MHz)', caseSensitive: false).firstMatch(output);
      speedMatch ??= RegExp(r'Configured Memory Speed:\s*(\d+\s*MHz)', caseSensitive: false).firstMatch(output);
      
      if (speedMatch != null) {
        final matchedSpeed = speedMatch.group(1)!;
        if (!matchedSpeed.toLowerCase().contains('unknown')) {
           speed = matchedSpeed;
        }
      }

      final populatedSlots = 'Memory Device'.allMatches(output).length;

      if (populatedSlots > 0) {
        String totalSlotsDevice = '未知';
        final arrayMatch = RegExp(r'Physical Memory Array.*?Number Of Devices:\s*(\d+)', dotAll: true).firstMatch(output);

        if (arrayMatch != null) {
            totalSlotsDevice = arrayMatch.group(1)!;
            slots = '$populatedSlots/$totalSlotsDevice';
        } else {
          slots = '$populatedSlots/$populatedSlots';
        }
      }
      
      final formFactorMatch = RegExp(r'Form Factor:\s*([\w-]+)', caseSensitive: false).firstMatch(output);
      if (formFactorMatch != null) {
        final matchedFormFactor = formFactorMatch.group(1)!;
        if (!matchedFormFactor.toLowerCase().contains('unknown')) {
          formFactor = matchedFormFactor.toUpperCase();
        }
      }

      if (mounted) {
        setState(() {
          _memoryHardwareInfo = MemoryHardwareInfo(
            speed: speed,
            slotsUsed: slots,
            formFactor: formFactor,
          );
          _memoryInfo = _memoryInfo.copyWith(hardwareInfo: _memoryHardwareInfo);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _memoryHardwareInfo = MemoryHardwareInfo(speed: '未知', slotsUsed: '未知', formFactor: '未知');
          _memoryInfo = _memoryInfo.copyWith(hardwareInfo: _memoryHardwareInfo);
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
    } catch (e) { /* ... */ }
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
          ...List.generate(_disks.length, (diskIndex) {
            final disk = _disks[diskIndex];
            final overallIndex = 2 + diskIndex; 
            return _buildMetricTile(
              index: overallIndex,
              title: disk.deviceName,
              utilization: disk.dynamicInfo.activeTimePercentage,
              detailsLine1: "${disk.dynamicInfo.totalTransferSpeed.toStringAsFixed(1)} MB/s",
              detailsLine2: "${disk.dynamicInfo.activeTimePercentage.toStringAsFixed(0)}%",
              historyData: disk.dynamicInfo.activeTimeHistory,
              color: const Color(0xFF4E731C),
            );
          }),
          _buildMetricTile(
            index: 2 + _disks.length,
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
                painter: SparklinePainter(data: historyData, color: color, maxValue: 100.0),
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
    if (_selectedPerformanceMetricIndex == 0) {
      return _buildCpuDetailsPage();
    }
    if (_selectedPerformanceMetricIndex == 1) {
      return _buildMemoryDetailsPage();
    }
    int diskIndex = _selectedPerformanceMetricIndex - 2;
    if (diskIndex >= 0 && diskIndex < _disks.length) {
      return _buildDiskDetailsPage(_disks[diskIndex]);
      
    }
    return _buildPlaceholderDetailsPage();
  }

  Widget _buildDiskDetailsPage(DiskInfo disk) {
    final titleStyle = const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300);

    // --- FIX START: 为图表动态计算最大值 ---
    double calculateMaxValue(List<double> data, double fallbackValue) {
      if (data.isEmpty) {
        return fallbackValue;
      }
      // reduce 在空列表上会引发错误，因此我们先检查是否为空。
      final maxVal = data.reduce(max);
      // 如果最大值是0，也使用备用值，以便图表有可见的高度。
      return maxVal > 0 ? maxVal : fallbackValue;
    }

    final activeTimeMaxValue = calculateMaxValue(disk.dynamicInfo.activeTimeHistory, 100.0);
    final transferRateMaxValue = calculateMaxValue(disk.dynamicInfo.transferRateHistory, 0.1);
    print(disk.dynamicInfo.transferRateHistory);
    // --- FIX END ---

    return Scrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _verticalScrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(disk.deviceName, style: titleStyle),
              const Spacer(),
              Expanded(
                child: Text(
                  disk.staticInfo.model,
                  textAlign: TextAlign.end,
                  style: titleStyle.copyWith(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // --- FIX START: 在图表构建中使用动态最大值 ---
          _buildGraphWithLabel(
            '活动时间',
            '${activeTimeMaxValue.toStringAsFixed(0)}%',
            disk.dynamicInfo.activeTimeHistory,
            const Color(0xFF4E731C),
            activeTimeMaxValue,
          ),
          const SizedBox(height: 16),
          _buildGraphWithLabel(
            '磁盘传输速率',
            '${transferRateMaxValue.toStringAsFixed(1)} MB/s',
            disk.dynamicInfo.transferRateHistory,
            const Color(0xFF4E731C),
            transferRateMaxValue,
          ),
          // --- FIX END ---
          const SizedBox(height: 24),

          Scrollbar(
            controller: _horizontalDiskScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalDiskScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 550),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailStat(
                                '${disk.dynamicInfo.activeTimePercentage.toStringAsFixed(0)} %', '活动时间'),
                            const SizedBox(height: 20),
                            _buildDetailStat(
                                _formatSpeed(disk.dynamicInfo.readSpeed * 1024),
                                '读取速度'),
                          ],
                        ),
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1, indent: 10, endIndent: 10),
                      Container(
                        width: 180,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailStat(
                                '${disk.dynamicInfo.avgResponseTime.toStringAsFixed(1)} 毫秒', '平均响应时间'),
                            const SizedBox(height: 20),
                            _buildDetailStat(
                                _formatSpeed(disk.dynamicInfo.writeSpeed * 1024),
                                '写入速度'),
                          ],
                        ),
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1, indent: 10, endIndent: 10),
                      SizedBox(
                        width: 180,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHardwareStat('容量:', disk.staticInfo.capacity),
                              _buildHardwareStat('已格式化:', disk.staticInfo.formatted),
                              _buildHardwareStat('系统磁盘:', disk.staticInfo.isSystemDisk ? '是' : '否'),
                              _buildHardwareStat('页面文件:', disk.staticInfo.hasPageFile ? '是' : '否'),
                              _buildHardwareStat('类型:', disk.staticInfo.type),
                            ],
                          ),
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

  Widget _buildGraphWithLabel(String label, String yAxisMax, List<double> data, Color color, double maxValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            Text(yAxisMax, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: CustomPaint(
              painter: SparklinePainter(
                data: data,
                color: color,
                fillColor: color.withValues(alpha: 0.8),
                maxValue: maxValue,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailStat(String value, String label, {String? subValue}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500)),
            if (subValue != null) ...[
              const SizedBox(width: 8),
              Text(subValue, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            ]
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ],
    );
  }

  Widget _buildHardwareStat(String label, String value) {
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

  Widget _buildMemoryDetailsPage() {
    final titleStyle = const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300);
    
    final totalGB = _memoryInfo.total / (1024 * 1024);
    final usedGB = (_memoryInfo.total - _memoryInfo.available) / (1024 * 1024);
    final availableGB = _memoryInfo.available / (1024 * 1024);
    final cachedGB = _memoryInfo.cached / (1024 * 1024);
    
    final committedGB = (_memoryInfo.total - _memoryInfo.available + _memoryInfo.swapUsed) / (1024 * 1024);
    final totalCommittedGB = (_memoryInfo.total + _memoryInfo.swapTotal) / (1024 * 1024);

    final pagedPoolMB = _memoryInfo.pagedPool / 1024;
    final nonPagedPoolMB = _memoryInfo.nonPagedPool / 1024;
    final hardwareReservedMB = _memoryInfo.hardwareReserved / 1024;

    final usedPercentage = totalGB > 0 ? (usedGB / totalGB) : 0.0;
    
    return Scrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _verticalScrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('内存', style: titleStyle),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${totalGB.toStringAsFixed(1)} GB', style: titleStyle.copyWith(fontSize: 20)),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
  
          SizedBox(
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: CustomPaint(
                painter: SparklinePainter(
                  data: _memoryInfo.usageHistory,
                  color: const Color(0xFF8635A8),
                  fillColor: const Color(0xFF283C55),
                  maxValue: 100.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
  
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('内存组合', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                height: 20,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black.withValues(alpha: 0.5)),
                  color: Colors.transparent,
                ),
                child: ClipRRect(
                  child: Row(
                    children: [
                      Expanded(
                        flex: (usedPercentage * 1000).toInt(),
                        child: Container(color: const Color(0xFF283C55)),
                      ),
                      Expanded(
                        flex: ((cachedGB / totalGB) * 1000).toInt(),
                        child: Container(color: Colors.teal.withValues(alpha: 0.5)),
                      ),
                      Expanded(
                        flex: ((1 - usedPercentage - (cachedGB / totalGB)) * 1000).toInt(),
                        child: Container(color: Colors.transparent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
  
          Scrollbar(
            controller: _horizontalMemoryScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalMemoryScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 550),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailStat('${usedGB.toStringAsFixed(1)} GB', '使用中'),
                            const SizedBox(height: 20),
                            _buildDetailStat('${committedGB.toStringAsFixed(1)}/${totalCommittedGB.toStringAsFixed(1)} GB', '已提交'),
                            const SizedBox(height: 20),
                             _buildDetailStat('${pagedPoolMB.toStringAsFixed(1)} MB', '分页缓冲池'),
                          ],
                        ),
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1, indent: 10, endIndent: 10),
                      Container(
                        width: 180,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailStat('${availableGB.toStringAsFixed(1)} GB', '可用'),
                            const SizedBox(height: 20),
                            _buildDetailStat('${cachedGB.toStringAsFixed(1)} GB', '已缓存'),
                             const SizedBox(height: 20),
                            _buildDetailStat('${nonPagedPoolMB.toStringAsFixed(1)} MB', '非分页缓冲池'),
                          ],
                        ),
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1, indent: 10, endIndent: 10),
                      SizedBox(
                        width: 180,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHardwareStat('速度:', _memoryHardwareInfo.speed),
                              _buildHardwareStat('已使用的插槽:', _memoryHardwareInfo.slotsUsed),
                              _buildHardwareStat('外形规格:', _memoryHardwareInfo.formFactor),
                              _buildHardwareStat('为硬件保留的内存:', '${hardwareReservedMB.toStringAsFixed(1)} MB'),
                            ],
                          ),
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
      thumbVisibility: true,
      child: ListView(
        controller: _verticalScrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('CPU', style: titleStyle),
              const Spacer(),
              Expanded(
                child: Text(
                  _cpuStaticInfo!.modelName,
                  textAlign: TextAlign.end,
                  style: titleStyle.copyWith(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
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
                    fillColor: const Color(0xFF283C55),
                    maxValue: 100.0,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 550),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailStat('${_cpuDynamicInfo.utilization.toStringAsFixed(0)} %', '利用率'),
                            const SizedBox(height: 20),
                            _buildDetailStat(_cpuDynamicInfo.processes.toString(), '进程'),
                            const SizedBox(height: 20),
                            _buildDetailStat(_cpuDynamicInfo.handles.toString(), '句柄'),
                          ],
                        ),
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1, indent: 10, endIndent: 10),
                      Container(
                         width: 180,
                         padding: const EdgeInsets.symmetric(horizontal: 16.0),
                         child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailStat('${_cpuDynamicInfo.currentSpeed.toStringAsFixed(2)} GHz', '速度'),
                              const SizedBox(height: 20),
                              _buildDetailStat(_cpuDynamicInfo.threads.toString(), '线程'),
                              const SizedBox(height: 20),
                              _buildDetailStat(_cpuDynamicInfo.uptime, '正常运行时间', subValue: ''),
                            ],
                         ),
                      ),
                      const VerticalDivider(color: Colors.white24, thickness: 1, indent: 10, endIndent: 10),
                      SizedBox(
                        width: 240,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHardwareStat('基准速度:', _cpuStaticInfo!.baseSpeed),
                              _buildHardwareStat('插槽:', _cpuStaticInfo!.sockets.toString()),
                              _buildHardwareStat('内核:', _cpuStaticInfo!.cores.toString()),
                              _buildHardwareStat('逻辑处理器:', _cpuStaticInfo!.threads.toString()),
                              _buildHardwareStat('虚拟化:', _cpuStaticInfo!.virtualization),
                              _buildHardwareStat('L1 缓存:', '${_cpuStaticInfo!.l1dCache} (D)'),
                              _buildHardwareStat('', '${_cpuStaticInfo!.l1iCache} (I)'),
                              _buildHardwareStat('L2 缓存:', _cpuStaticInfo!.l2Cache),
                              _buildHardwareStat('L3 缓存:', _cpuStaticInfo!.l3Cache),
                            ],
                          ),
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
          thumbVisibility: true,
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
                      thumbVisibility: true,
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
  final Color? fillColor;
  final double maxValue;

  SparklinePainter({
    required this.data,
    required this.color,
    this.fillColor,
    required this.maxValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    final finalFillColor = fillColor ?? color.withValues(alpha: 0.3);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [finalFillColor, finalFillColor.withValues(alpha: 0.05)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final fillPath = Path();

    // Helper to calculate Y position.
    // Clamps the result to be slightly inside the canvas to prevent clipping issues,
    // ensuring a line is visible even if at the top or bottom boundary.
    double getY(double value) {
      if (maxValue <= 0) {
        return size.height - 1.0; // Draw near the bottom if maxValue is 0 or less.
      }
      final y = size.height - (value.clamp(0.0, maxValue) / maxValue * size.height);
      // Clamp Y to be just inside the canvas bounds to ensure visibility.
      return y.clamp(0.0, size.height - 1.0);
    }
    
    // If there's only one data point, draw a horizontal line.
    if (data.length < 2) {
      final y = getY(data.first);
      path.moveTo(0, y);
      path.lineTo(size.width, y);
      
      fillPath.moveTo(0, size.height);
      fillPath.lineTo(0, y);
      fillPath.lineTo(size.width, y);
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
    } else {
      // If there are multiple points, draw a path.
      final stepX = size.width / (data.length - 1);

      final firstY = getY(data[0]);
      path.moveTo(0, firstY);

      fillPath.moveTo(0, size.height);
      fillPath.lineTo(0, firstY);

      for (int i = 1; i < data.length; i++) {
        final x = i * stepX;
        final y = getY(data[i]);
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      
      // Complete the fill path to the bottom right corner.
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return oldDelegate.data != data || 
           oldDelegate.color != color || 
           oldDelegate.fillColor != fillColor ||
           oldDelegate.maxValue != maxValue;
  }
}