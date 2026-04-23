// Simple action commands: open, close, tap, fill, type, focus, back, home,
// app-switcher, rotate, press-key, clipboard, appstate, apps. Each one
// constructs an AgentDevice, performs a single backend call, and prints
// a short acknowledgement in human mode.
library;

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class OpenCommand extends AgentDeviceCommand {
  @override
  String get name => 'open';

  @override
  String get description => 'Open an app (package / bundle / URL / alias).';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(AppErrorCodes.invalidArgs, 'open requires a target app.');
    }
    final target = args.first;
    final device = await openAgentDevice();
    await device.openApp(target);
    emitResult({
      'opened': target,
      'deviceSerial': device.device.id,
    }, humanFormat: (_) => 'opened: $target');
    return 0;
  }
}

class CloseCommand extends AgentDeviceCommand {
  @override
  String get name => 'close';

  @override
  String get description => 'Close the current app (or a specified one).';

  @override
  Future<int> run() async {
    final args = positionals;
    final device = await openAgentDevice();
    try {
      await device.closeApp(args.isEmpty ? null : args.first);
      emitResult({'closed': true}, humanFormat: (_) => 'closed.');
      return 0;
    } finally {
      await device.close();
    }
  }
}

class TapCommand extends AgentDeviceCommand {
  @override
  String get name => 'tap';

  @override
  String get description => 'Tap at x y coordinates.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.length < 2) {
      throw AppError(AppErrorCodes.invalidArgs, 'tap requires <x> <y>.');
    }
    final x = int.tryParse(args[0]);
    final y = int.tryParse(args[1]);
    if (x == null || y == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'tap x and y must be integers.',
      );
    }
    final device = await openAgentDevice();
    await device.tap(x, y);
    emitResult({
      'tapped': [x, y],
    }, humanFormat: (_) => 'tapped ($x, $y)');
    return 0;
  }
}

class FillCommand extends AgentDeviceCommand {
  FillCommand() {
    argParser.addOption('delay-ms', help: 'Inter-character delay in ms.');
  }

  @override
  String get name => 'fill';

  @override
  String get description =>
      'Tap at x y, then fill the focused field with text.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.length < 3) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'fill requires <x> <y> <text>.',
      );
    }
    final x = int.tryParse(args[0]);
    final y = int.tryParse(args[1]);
    if (x == null || y == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'fill x and y must be integers.',
      );
    }
    final text = args.sublist(2).join(' ');
    final delayRaw = argResults?['delay-ms'] as String?;
    final delayMs = delayRaw == null ? null : int.tryParse(delayRaw);
    final device = await openAgentDevice();
    await device.fill(x, y, text, delayMs: delayMs);
    emitResult({
      'filled': text,
      'at': [x, y],
    }, humanFormat: (_) => 'filled ($x, $y): ${jsonish(text)}');
    return 0;
  }
}

class TypeCommand extends AgentDeviceCommand {
  TypeCommand() {
    argParser.addOption('delay-ms', help: 'Inter-character delay in ms.');
  }

  @override
  String get name => 'type';

  @override
  String get description => 'Type text into the currently focused field.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(AppErrorCodes.invalidArgs, 'type requires <text>.');
    }
    final text = args.join(' ');
    final delayRaw = argResults?['delay-ms'] as String?;
    final delayMs = delayRaw == null ? null : int.tryParse(delayRaw);
    final device = await openAgentDevice();
    await device.typeText(text, delayMs: delayMs);
    emitResult({'typed': text}, humanFormat: (_) => 'typed: ${jsonish(text)}');
    return 0;
  }
}

class FocusCommand extends AgentDeviceCommand {
  @override
  String get name => 'focus';

  @override
  String get description => 'Focus (tap without triggering) at x y.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.length < 2) {
      throw AppError(AppErrorCodes.invalidArgs, 'focus requires <x> <y>.');
    }
    final x = int.tryParse(args[0]);
    final y = int.tryParse(args[1]);
    if (x == null || y == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'focus x and y must be integers.',
      );
    }
    final device = await openAgentDevice();
    await device.focus(x, y);
    emitResult({
      'focused': [x, y],
    }, humanFormat: (_) => 'focused ($x, $y)');
    return 0;
  }
}

class BackCommand extends AgentDeviceCommand {
  @override
  String get name => 'back';

  @override
  String get description => 'Press the back button.';

  @override
  Future<int> run() async {
    final device = await openAgentDevice();
    await device.pressBack();
    emitResult({'pressed': 'back'}, humanFormat: (_) => 'pressed back');
    return 0;
  }
}

class HomeCommand extends AgentDeviceCommand {
  @override
  String get name => 'home';

  @override
  String get description => 'Press the home button.';

  @override
  Future<int> run() async {
    final device = await openAgentDevice();
    await device.pressHome();
    emitResult({'pressed': 'home'}, humanFormat: (_) => 'pressed home');
    return 0;
  }
}

class AppSwitcherCommand extends AgentDeviceCommand {
  @override
  String get name => 'app-switcher';

  @override
  String get description => 'Open the app switcher.';

  @override
  Future<int> run() async {
    final device = await openAgentDevice();
    await device.openAppSwitcher();
    emitResult({
      'opened': 'app-switcher',
    }, humanFormat: (_) => 'opened app-switcher');
    return 0;
  }
}

class SwipeCommand extends AgentDeviceCommand {
  SwipeCommand() {
    argParser.addOption('duration-ms', help: 'Swipe duration in ms.');
  }

  @override
  String get name => 'swipe';

  @override
  String get description => 'Swipe from (x1 y1) to (x2 y2).';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.length < 4) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'swipe requires <x1> <y1> <x2> <y2>.',
      );
    }
    final xs = args.map(int.tryParse).toList();
    if (xs.any((e) => e == null)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'swipe coords must be integers.',
      );
    }
    final dms = argResults?['duration-ms'] as String?;
    final durationMs = dms == null ? null : int.tryParse(dms);
    final device = await openAgentDevice();
    await device.swipe(xs[0]!, xs[1]!, xs[2]!, xs[3]!, durationMs: durationMs);
    emitResult(
      {'swiped': xs},
      humanFormat: (_) => 'swiped (${xs[0]}, ${xs[1]}) → (${xs[2]}, ${xs[3]})',
    );
    return 0;
  }
}

class ScrollCommand extends AgentDeviceCommand {
  ScrollCommand() {
    argParser
      ..addOption('amount', help: 'Scroll amount (viewport multiples).')
      ..addOption('pixels', help: 'Scroll by an exact pixel count.');
  }

  @override
  String get name => 'scroll';

  @override
  String get description => 'Scroll (up|down|left|right).';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'scroll requires a direction (up|down|left|right).',
      );
    }
    final direction = args.first;
    final amountRaw = argResults?['amount'] as String?;
    final pixelsRaw = argResults?['pixels'] as String?;
    final device = await openAgentDevice();
    final result = await device.scroll(
      direction,
      amount: amountRaw == null ? null : int.tryParse(amountRaw),
      pixels: pixelsRaw == null ? null : int.tryParse(pixelsRaw),
    );
    emitResult({
      'direction': direction,
      'result': result,
    }, humanFormat: (_) => 'scrolled $direction');
    return 0;
  }
}

class LongPressCommand extends AgentDeviceCommand {
  LongPressCommand() {
    argParser.addOption('duration-ms', help: 'Hold duration in ms.');
  }

  @override
  String get name => 'longpress';

  @override
  String get description => 'Long-press at x y.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.length < 2) {
      throw AppError(AppErrorCodes.invalidArgs, 'longpress requires <x> <y>.');
    }
    final x = int.tryParse(args[0]);
    final y = int.tryParse(args[1]);
    if (x == null || y == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'longpress x and y must be integers.',
      );
    }
    final dms = argResults?['duration-ms'] as String?;
    final durationMs = dms == null ? null : int.tryParse(dms);
    final device = await openAgentDevice();
    await device.longPress(x, y, durationMs: durationMs);
    emitResult({
      'longPressed': [x, y],
    }, humanFormat: (_) => 'long-pressed ($x, $y)');
    return 0;
  }
}

class AppStateCommand extends AgentDeviceCommand {
  @override
  String get name => 'appstate';

  @override
  String get description => 'Report the current foreground app state.';

  @override
  Future<int> run() async {
    final args = positionals;
    final device = await openAgentDevice();
    final state = await device.getAppState(args.isEmpty ? null : args.first);
    emitResult(
      state.toJson(),
      humanFormat: (_) =>
          'package=${state.packageName ?? '(unknown)'} '
          'activity=${state.activity ?? '(none)'}',
    );
    return 0;
  }
}

class AppsCommand extends AgentDeviceCommand {
  AppsCommand() {
    argParser.addOption(
      'filter',
      help: 'Filter apps: all | user-installed.',
      allowed: ['all', 'user-installed'],
      defaultsTo: 'all',
    );
  }

  @override
  String get name => 'apps';

  @override
  String get description => 'List installed apps.';

  @override
  Future<int> run() async {
    final filterRaw = argResults?['filter'] as String?;
    final filter = filterRaw == 'user-installed'
        ? BackendAppListFilter.userInstalled
        : BackendAppListFilter.all;
    final device = await openAgentDevice();
    final apps = await device.listApps(filter: filter);
    emitResult(
      apps.map((a) => a.toJson()).toList(),
      humanFormat: (_) {
        if (apps.isEmpty) return '(no apps)';
        final buf = StringBuffer();
        for (final a in apps) {
          buf.writeln('${a.id}${a.name == null ? '' : '  (${a.name})'}');
        }
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}

class ClipboardCommand extends AgentDeviceCommand {
  ClipboardCommand() {
    argParser.addOption('set', help: 'Set the clipboard to this text.');
  }

  @override
  String get name => 'clipboard';

  @override
  String get description => 'Read or set the device clipboard.';

  @override
  Future<int> run() async {
    final setVal = argResults?['set'] as String?;
    final device = await openAgentDevice();
    if (setVal != null) {
      await device.setClipboard(setVal);
      emitResult({'set': setVal}, humanFormat: (_) => 'clipboard set');
      return 0;
    }
    final text = await device.getClipboard();
    emitResult({'clipboard': text}, humanFormat: (_) => text);
    return 0;
  }
}

/// Quote a string for human-mode output so escapes are visible.
String jsonish(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
