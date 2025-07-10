class SSHCredentials {
  final String host;
  final String username;
  final String password;
  final int port;

  SSHCredentials({
    required this.host,
    required this.username,
    required this.password,
    required this.port,
  });
}