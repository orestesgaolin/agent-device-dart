// `agent-device install <path>` / `uninstall <bundleId>` /
// `reinstall <bundleId> <path>` — local app management.
//
// iOS: accepts a `.app` directory or `.ipa` archive (single-app
// archives auto-resolve; multi-app archives need an --app hint).
// Android: accepts an APK or AAB path; reinstall preserves the
// package across the uninstall/install cycle.
library;

import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class InstallCommand extends AgentDeviceCommand {
  InstallCommand() {
    argParser.addOption(
      'app',
      help:
          'Bundle id (iOS) or package name (Android) to disambiguate '
          'a multi-app .ipa or to use as a hint when the platform tool '
          'cannot infer it.',
    );
  }

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install an app from a local .app/.ipa (iOS) or .apk/.aab (Android) path.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'install requires <path> to a .app/.ipa (iOS) or .apk/.aab (Android).',
      );
    }
    final path = args.first;
    final hint = argResults?['app'] as String?;
    final device = await openAgentDevice();
    final res = await device.installApp(path: path, app: hint);
    emitResult(
      res.toJson(),
      humanFormat: (_) {
        final id = res.bundleId ?? res.packageName ?? res.appId ?? '<unknown>';
        return 'installed $id'
            '${res.appName != null ? ' (${res.appName})' : ''}'
            ' from $path';
      },
    );
    return 0;
  }
}

class UninstallCommand extends AgentDeviceCommand {
  @override
  String get name => 'uninstall';

  @override
  String get description =>
      'Uninstall an app by bundle id (iOS) or package name (Android).';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'uninstall requires <bundleId|packageName>.',
      );
    }
    final app = args.first;
    final device = await openAgentDevice();
    final res = await device.uninstallApp(app: app);
    emitResult(
      res.toJson(),
      humanFormat: (_) =>
          'uninstalled ${res.bundleId ?? res.packageName ?? res.appId ?? app}',
    );
    return 0;
  }
}

class ReinstallCommand extends AgentDeviceCommand {
  ReinstallCommand() {
    argParser.addFlag(
      'reset-keychain',
      help:
          'Reset the simulator keychain before reinstalling (iOS simulator only). '
          'Clears all stored credentials and tokens.',
      negatable: false,
    );
  }

  @override
  String get name => 'reinstall';

  @override
  String get description =>
      'Uninstall an app then install it from a local path. iOS: '
      '.app/.ipa; Android: .apk/.aab.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.length < 2) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'reinstall requires <bundleId|packageName> <path>.',
      );
    }
    final app = args[0];
    final path = args[1];
    final resetKeychain = argResults?['reset-keychain'] == true;
    final device = await openAgentDevice();
    final res = await device.reinstallApp(
      app: app,
      path: path,
      resetKeychain: resetKeychain,
    );
    emitResult(
      res.toJson(),
      humanFormat: (_) {
        final id = res.bundleId ?? res.packageName ?? res.appId ?? app;
        final kcNote = resetKeychain ? ' (keychain reset)' : '';
        return 'reinstalled $id from $path$kcNote';
      },
    );
    return 0;
  }
}
