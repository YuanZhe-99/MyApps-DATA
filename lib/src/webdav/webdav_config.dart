/// Purpose: Persisted WebDAV configuration shared by MyAnime / MyDay / MyDevice.
/// Inputs: None (library declaration only).
/// Returns: N/A.
/// Side effects: None.
/// Notes: Behavior-identical to the three apps' `WebDAVConfig` (feature-matrix
/// §A1-A4) except that `remotePath` defaults to `''` instead of a per-app
/// constant.  The per-app default (`/MyAnime`, `/MyDay`, `/MyDevice`) is
/// injected by the sync engine (knob `defaultRemotePath`, feature-matrix §O)
/// or the app facade at P3 integration time.
library;

/// Persisted WebDAV configuration.
///
/// Fields and wire format are identical across all three apps
/// (feature-matrix §A1): `serverUrl`, `username`, `password`, `remotePath`,
/// `autoSync`.  The `.nextcloud()` factory (§A3) and `isConfigured`/`copyWith`/
/// `toJson`/`fromJson` round-trip (§A4) are also identical.
class WebDAVConfig {
  /// WebDAV server base URL (e.g. `https://cloud.example.com/remote.php/dav/files/user`).
  final String serverUrl;

  /// WebDAV username (HTTP Basic auth).
  final String username;

  /// WebDAV password (HTTP Basic auth).
  final String password;

  /// Remote collection path (e.g. `/MyAnime`).  Defaults to `''` in the
  /// package; the app-specific default is applied by the engine/facade.
  final String remotePath;

  /// Whether auto-sync is enabled for this configuration.
  final bool autoSync;

  /// Purpose: Create a WebDAV config instance.
  /// Inputs: [serverUrl], [username], [password] are required; [remotePath]
  /// defaults to `''`; [autoSync] defaults to `false`.
  /// Returns: A new [WebDAVConfig] instance.
  /// Side effects: None.
  /// Notes: None.
  const WebDAVConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.remotePath = '',
    this.autoSync = false,
  });

  /// Purpose: Return whether the minimum credentials are present.
  /// Inputs: None.
  /// Returns: `true` when `serverUrl`, `username`, and `password` are all
  /// non-empty.
  /// Side effects: None.
  /// Notes: feature-matrix §A4.  `remotePath` is not checked (an empty path
  /// is still "configured" from a credentials standpoint; the engine applies
  /// the app default).
  bool get isConfigured =>
      serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  /// Purpose: Create a copy with [autoSync] replaced.
  /// Inputs: [autoSync] optional new value.
  /// Returns: A new [WebDAVConfig] with the updated field.
  /// Side effects: None.
  /// Notes: feature-matrix §A4.  Only `autoSync` is overridable (matching the
  /// apps' `copyWith`).
  WebDAVConfig copyWith({bool? autoSync}) => WebDAVConfig(
    serverUrl: serverUrl,
    username: username,
    password: password,
    remotePath: remotePath,
    autoSync: autoSync ?? this.autoSync,
  );

  /// Purpose: Serialize this config to a JSON-compatible map.
  /// Inputs: None.
  /// Returns: `Map<String, dynamic>` with all five fields.
  /// Side effects: None.
  /// Notes: feature-matrix §A4.  Key order matches the apps' output.
  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
    'remotePath': remotePath,
    'autoSync': autoSync,
  };

  /// Purpose: Create an instance from a JSON-compatible map.
  /// Inputs: [json] decoded map (typically from `webdav_config.json`).
  /// Returns: A new [WebDAVConfig].
  /// Side effects: None.
  /// Notes: feature-matrix §A4.  Missing fields default to `''`/`false`.
  /// `remotePath` defaults to `''` (not a per-app constant); the engine
  /// applies the app default when loading.
  factory WebDAVConfig.fromJson(Map<String, dynamic> json) => WebDAVConfig(
    serverUrl: json['serverUrl'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    remotePath: json['remotePath'] as String? ?? '',
    autoSync: json['autoSync'] as bool? ?? false,
  );

  /// Purpose: Create a Nextcloud-style WebDAV config from a bare host.
  /// Inputs: [host] server hostname; [username], [password] credentials.
  /// Returns: A new [WebDAVConfig] with `serverUrl` set to
  /// `https://$host/remote.php/dav/files/$username`.
  /// Side effects: None.
  /// Notes: feature-matrix §A3.  Identical across all three apps.  `remotePath`
  /// defaults to `''` (the apps' per-app default is applied by the facade).
  factory WebDAVConfig.nextcloud(
    String host,
    String username,
    String password,
  ) => WebDAVConfig(
    serverUrl: 'https://$host/remote.php/dav/files/$username',
    username: username,
    password: password,
  );
}
