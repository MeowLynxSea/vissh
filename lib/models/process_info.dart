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