// Simple action commands: open, close, tap, fill, type, focus, back, home,
// app-switcher, rotate, press-key, clipboard, appstate, apps, settings,
// boot, keyboard, trigger-app-event. Each one constructs an AgentDevice,
// performs a single backend call, and prints a short acknowledgement in
// human mode.
library;

import 'dart:convert';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/backend/device_info.dart';
import 'package:agent_device/src/snapshot/snapshot.dart' show Point;
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

class RotateCommand extends AgentDeviceCommand {
  @override
  String get name => 'rotate';

  @override
  String get description =>
      'Rotate the device (portrait | portrait-upside-down | landscape-left | landscape-right).';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'rotate requires an orientation '
        '(portrait | portrait-upside-down | landscape-left | landscape-right).',
      );
    }
    final raw = args.first;
    final orientation = switch (raw) {
      'portrait' => BackendDeviceOrientation.portrait,
      'portrait-upside-down' ||
      'portraitUpsideDown' => BackendDeviceOrientation.portraitUpsideDown,
      'landscape-left' ||
      'landscapeLeft' => BackendDeviceOrientation.landscapeLeft,
      'landscape-right' ||
      'landscapeRight' => BackendDeviceOrientation.landscapeRight,
      _ => null,
    };
    if (orientation == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Unknown orientation "$raw". Expected portrait | '
        'portrait-upside-down | landscape-left | landscape-right.',
        details: {'orientation': raw},
      );
    }
    final device = await openAgentDevice();
    await device.rotate(orientation);
    emitResult({'rotated': raw}, humanFormat: (_) => 'rotated to $raw');
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

class PinchCommand extends AgentDeviceCommand {
  PinchCommand() {
    argParser
      ..addOption('scale', help: 'Pinch scale. <1 zooms out, >1 zooms in.')
      ..addOption('x', help: 'Optional center-x (default: viewport center).')
      ..addOption('y', help: 'Optional center-y (default: viewport center).');
  }

  @override
  String get name => 'pinch';

  @override
  String get description => 'Pinch to zoom (--scale required).';

  @override
  Future<int> run() async {
    final scaleRaw = argResults?['scale'] as String? ?? positionals.firstOrNull;
    final scale = scaleRaw == null ? null : double.tryParse(scaleRaw);
    if (scale == null || scale <= 0) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'pinch requires --scale <positive-number>.',
      );
    }
    final xs = argResults?['x'] as String?;
    final ys = argResults?['y'] as String?;
    Point? center;
    if (xs != null && ys != null) {
      final x = int.tryParse(xs);
      final y = int.tryParse(ys);
      if (x == null || y == null) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'pinch --x / --y must be integers.',
        );
      }
      center = Point(x: x.toDouble(), y: y.toDouble());
    }
    final device = await openAgentDevice();
    await device.pinch(scale: scale, center: center);
    emitResult({
      'pinched': scale,
      if (center != null) 'center': [center.x, center.y],
    }, humanFormat: (_) => 'pinched scale=$scale');
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

/// `settings [target]` — open platform settings, optionally scoped to a
/// specific settings pane (e.g. `wifi`, `bluetooth`, `privacy`).
class SettingsCommand extends AgentDeviceCommand {
  @override
  String get name => 'settings';

  @override
  String get description =>
      'Open platform settings (optionally scoped to a target pane).';

  @override
  Future<int> run() async {
    final target = positionals.isEmpty ? null : positionals.first;
    final device = await openAgentDevice();
    await device.openSettings(target);
    emitResult(
      {'opened': 'settings', 'target': ?target},
      humanFormat: (_) =>
          target == null ? 'opened settings' : 'opened settings: $target',
    );
    return 0;
  }
}

/// `boot [name]` — boot a device or simulator. When [name] is omitted the
/// device selected by the global `--serial` / `--device` / `--platform`
/// flags is booted.
class BootCommand extends AgentDeviceCommand {
  @override
  String get name => 'boot';

  @override
  String get description =>
      'Boot a device or simulator. Optionally specify a device name.';

  @override
  Future<int> run() async {
    final deviceName = positionals.isEmpty ? null : positionals.first;
    final device = await openAgentDevice();
    final result = await device.bootDevice(name: deviceName);
    emitResult(
      {'booted': true, 'name': ?deviceName, 'result': result},
      humanFormat: (_) =>
          deviceName == null ? 'booted device' : 'booted: $deviceName',
    );
    return 0;
  }
}

/// `keyboard <action>` — control the software keyboard.
/// [action] is one of: `status` | `get` | `dismiss` | `hide`.
class KeyboardCommand extends AgentDeviceCommand {
  @override
  String get name => 'keyboard';

  @override
  String get description =>
      'Control the software keyboard (status | get | dismiss | hide).';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'keyboard requires an action: status | get | dismiss | hide.',
      );
    }
    final action = positionals.first;
    const validActions = {'status', 'get', 'dismiss', 'hide'};
    if (!validActions.contains(action)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Unknown keyboard action "$action". '
        'Expected: status | get | dismiss | hide.',
        details: {'action': action},
      );
    }
    final device = await openAgentDevice();
    final result = await device.setKeyboard(action);
    emitResult(
      result,
      humanFormat: (_) => 'keyboard $action',
    );
    return 0;
  }
}

/// `trigger-app-event <name> [--payload <json>]` — trigger a named event
/// on the running app via the runner bridge.
class TriggerAppEventCommand extends AgentDeviceCommand {
  TriggerAppEventCommand() {
    argParser.addOption(
      'payload',
      help: 'Optional JSON object payload to pass with the event.',
      valueHelp: 'JSON',
    );
  }

  @override
  String get name => 'trigger-app-event';

  @override
  String get description =>
      'Trigger a named event on the running app (via the runner bridge). '
      'Use --payload to pass a JSON object.';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'trigger-app-event requires an event name.',
      );
    }
    final eventName = positionals.first;
    final payloadRaw = argResults?['payload'] as String?;
    Map<String, Object?>? payload;
    if (payloadRaw != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(payloadRaw);
      } on FormatException {
        throw AppError(
          AppErrorCodes.invalidArgs,
          '--payload must be valid JSON.',
        );
      }
      if (decoded is! Map) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          '--payload must be a JSON object.',
        );
      }
      payload = {for (final e in decoded.entries) e.key.toString(): e.value};
    }
    final device = await openAgentDevice();
    final result = await device.triggerAppEvent(eventName, payload: payload);
    emitResult(
      {'event': eventName, 'payload': ?payload, 'result': result},
      humanFormat: (_) => 'triggered app event: $eventName',
    );
    return 0;
  }
}
