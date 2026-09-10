import 'dart:io';

import 'package:path/path.dart' as p;

Directory careerShopperHomeDirectory() {
  final home = _requiredEnvironment(
    Platform.isWindows ? 'USERPROFILE' : 'HOME',
  );
  if (!p.isAbsolute(home)) {
    throw StateError('The user home directory must be an absolute path.');
  }
  return Directory(p.normalize(home));
}

Directory careerShopperDataDirectory() {
  final override = Platform.environment['CAREERSHOPPER_DATA_DIR'];
  if (override != null && override.trim().isNotEmpty) {
    return Directory(p.normalize(p.absolute(override)));
  }

  if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return Directory(p.join(xdg, 'careershopper'));
    }
    return Directory(
      p.join(_requiredEnvironment('HOME'), '.local', 'share', 'careershopper'),
    );
  }

  if (Platform.isMacOS) {
    return Directory(
      p.join(
        _requiredEnvironment('HOME'),
        'Library',
        'Application Support',
        'CareerShopper',
      ),
    );
  }

  if (Platform.isWindows) {
    return Directory(
      p.join(_requiredEnvironment('LOCALAPPDATA'), 'CareerShopper'),
    );
  }

  throw UnsupportedError('CareerShopper supports Linux, macOS, and Windows.');
}

String _requiredEnvironment(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw StateError('The $key environment variable is required.');
  }
  return value;
}
