/// Purpose: Define the app-supplied storage boundary used by shared engines.
/// Inputs: Implementations supplied by MyAnime, MyDay, and MyDevice.
/// Returns: App-directory and storage-config access through an app-neutral API.
/// Side effects: Implementations may perform local file-system I/O.
/// Notes: The package never imports an app storage hub directly. Each app
/// delegates this interface to AnimeStorage, TodoStorage, or DeviceStorage.
library;

import 'dart:io';

/// App-supplied storage root and storage-config persistence.
abstract class StorageAdapter {
  /// Purpose: Resolve the active application data directory.
  /// Inputs: None.
  /// Returns: The directory containing data files, images, and engine metadata.
  /// Side effects: Implementations may create or resolve platform directories.
  /// Notes: Custom app storage paths must be honored by the implementation.
  Future<Directory> getAppDir();

  /// Purpose: Read the app's `storage_config.json` values.
  /// Inputs: None.
  /// Returns: A mutable JSON-compatible settings map.
  /// Side effects: Performs app-defined storage I/O.
  /// Notes: P2.6 does not use this for `webdav_config.json`; later backup and
  /// storage engines use it for shared storage settings.
  Future<Map<String, dynamic>> readConfig();

  /// Purpose: Persist the app's `storage_config.json` values.
  /// Inputs: [config] complete JSON-compatible settings map.
  /// Returns: A future completing after persistence.
  /// Side effects: Performs app-defined storage I/O.
  /// Notes: Implementations preserve app-owned keys not modeled by the package.
  Future<void> writeConfig(Map<String, dynamic> config);
}
