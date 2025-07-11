class ProcessInfo {
  final String pid;
  final String user;
  final double cpuUsage;
  final double memUsage;
  final String command;
  final double memInMB;

  final int diskReadBytes;
  final int diskWriteBytes;
  final double diskSpeed;
  final double diskUsagePercentage;

  ProcessInfo({
    required this.pid,
    required this.user,
    required this.cpuUsage,
    required this.memUsage,
    required this.command,
    required this.memInMB,
    required this.diskReadBytes,
    required this.diskWriteBytes,
    required this.diskSpeed,
    required this.diskUsagePercentage,
  });
}

class CpuStaticInfo {
  final String modelName;
  final String architecture;
  final String baseSpeed;
  final int sockets;
  final int cores;
  final int threads;
  final String virtualization;
  final String l1dCache;
  final String l1iCache;
  final String l2Cache;
  final String l3Cache;

  CpuStaticInfo({
    required this.modelName,
    required this.architecture,
    required this.baseSpeed,
    required this.sockets,
    required this.cores,
    required this.threads,
    required this.virtualization,
    required this.l1dCache,
    required this.l1iCache,
    required this.l2Cache,
    required this.l3Cache,
  });
}

class CpuDynamicInfo {
  final double currentSpeed;
  final double utilization;
  final int processes;
  final int threads;
  final int handles;
  final String uptime;

  CpuDynamicInfo({
    required this.currentSpeed,
    required this.utilization,
    required this.processes,
    required this.threads,
    required this.handles,
    required this.uptime,
  });

  factory CpuDynamicInfo.initial() {
    return CpuDynamicInfo(
      currentSpeed: 0.0,
      utilization: 0.0,
      processes: 0,
      threads: 0,
      handles: 0,
      uptime: '00:00:00:00',
    );
  }
}

class MemoryInfo {
  final int total;
  final int free;
  final int available;
  final int buffers;
  final int cached;
  final int swapTotal;
  final int swapFree;
  final int active;
  final int inactive;
  final int pagedPool;
  final int nonPagedPool;
  final int hardwareReserved;
  final double usedPercentage;
  final List<double> usageHistory;
  final MemoryHardwareInfo hardwareInfo;

  MemoryInfo({
    required this.total,
    required this.free,
    required this.available,
    required this.buffers,
    required this.cached,
    required this.swapTotal,
    required this.swapFree,
    required this.active,
    required this.inactive,
    required this.pagedPool,
    required this.nonPagedPool,
    required this.hardwareReserved,
    required this.usedPercentage,
    required this.usageHistory,
    required this.hardwareInfo,
  });

  factory MemoryInfo.initial() {
    return MemoryInfo(
      total: 0,
      free: 0,
      available: 0,
      buffers: 0,
      cached: 0,
      swapTotal: 0,
      swapFree: 0,
      active: 0,
      inactive: 0,
      pagedPool: 0,
      nonPagedPool: 0,
      hardwareReserved: 0,
      usedPercentage: 0.0,
      usageHistory: List.generate(60, (_) => 0.0),
      hardwareInfo: MemoryHardwareInfo(speed: '未知', slotsUsed: '未知', formFactor: '未知'),
    );
  }

  int get used => total - available;
  int get swapUsed => swapTotal - swapFree;
  
  MemoryInfo copyWith({
    int? total,
    int? free,
    int? available,
    int? buffers,
    int? cached,
    int? swapTotal,
    int? swapFree,
    int? active,
    int? inactive,
    int? pagedPool,
    int? nonPagedPool,
    int? hardwareReserved,
    double? usedPercentage,
    List<double>? usageHistory,
    MemoryHardwareInfo? hardwareInfo,
  }) {
    return MemoryInfo(
      total: total ?? this.total,
      free: free ?? this.free,
      available: available ?? this.available,
      buffers: buffers ?? this.buffers,
      cached: cached ?? this.cached,
      swapTotal: swapTotal ?? this.swapTotal,
      swapFree: swapFree ?? this.swapFree,
      active: active ?? this.active,
      inactive: inactive ?? this.inactive,
      pagedPool: pagedPool ?? this.pagedPool,
      nonPagedPool: nonPagedPool ?? this.nonPagedPool,
      hardwareReserved: hardwareReserved ?? this.hardwareReserved,
      usedPercentage: usedPercentage ?? this.usedPercentage,
      usageHistory: usageHistory ?? this.usageHistory,
      hardwareInfo: hardwareInfo ?? this.hardwareInfo,
    );
  }
}

class MemoryHardwareInfo {
  final String speed;
  final String slotsUsed;
  final String formFactor;

  MemoryHardwareInfo({
    required this.speed,
    required this.slotsUsed,
    required this.formFactor,
  });
}