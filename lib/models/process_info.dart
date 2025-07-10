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