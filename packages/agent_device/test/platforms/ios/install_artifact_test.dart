@TestOn('mac-os')
library;

// Unit coverage for the iOS install-artifact resolver. Builds real
// `.app` directories + `.ipa` zip archives in tmpdirs and walks them
// through `prepareIosInstallArtifact`. plutil is the only external
// tool we lean on (already a hard dependency for the runner bridge);
// `unzip` ships with macOS so it's available everywhere we run.

import 'dart:io';

import 'package:agent_device/src/platforms/ios/install_artifact.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ad-install-artifact-test-');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('prepareIosInstallArtifact', () {
    test('accepts a .app directory and reads bundle metadata', () async {
      final appDir = await _makeAppBundle(
        parent: tmp,
        name: 'Demo.app',
        bundleId: 'com.example.demo',
        displayName: 'Demo',
      );
      final prepared = await prepareIosInstallArtifact(appDir);
      try {
        expect(prepared.installablePath, equals(appDir));
        expect(prepared.archivePath, isNull);
        expect(prepared.bundleId, equals('com.example.demo'));
        expect(prepared.appName, equals('Demo'));
      } finally {
        await prepared.cleanup();
      }
    });

    test('unzips a single-app .ipa and surfaces the resolved .app', () async {
      final ipa = await _makeIpa(
        parent: tmp,
        archiveName: 'Demo.ipa',
        bundles: [
          _BundleSpec(name: 'Demo.app', bundleId: 'com.example.demo'),
        ],
      );
      final prepared = await prepareIosInstallArtifact(ipa);
      try {
        expect(prepared.archivePath, equals(ipa));
        expect(prepared.bundleId, equals('com.example.demo'));
        expect(prepared.installablePath.endsWith('Demo.app'), isTrue);
        expect(File(p.join(prepared.installablePath, 'Info.plist')).existsSync(), isTrue);
      } finally {
        await prepared.cleanup();
      }
    });

    test('rejects multi-app .ipa without a hint', () async {
      final ipa = await _makeIpa(
        parent: tmp,
        archiveName: 'MultiApp.ipa',
        bundles: [
          _BundleSpec(name: 'Alpha.app', bundleId: 'com.example.alpha'),
          _BundleSpec(name: 'Beta.app', bundleId: 'com.example.beta'),
        ],
      );
      await expectLater(
        () => prepareIosInstallArtifact(ipa),
        throwsA(isA<AppError>().having(
          (e) => e.code,
          'code',
          AppErrorCodes.invalidArgs,
        )),
      );
    });

    test('multi-app .ipa resolves by bundle id hint', () async {
      final ipa = await _makeIpa(
        parent: tmp,
        archiveName: 'MultiApp.ipa',
        bundles: [
          _BundleSpec(name: 'Alpha.app', bundleId: 'com.example.alpha'),
          _BundleSpec(name: 'Beta.app', bundleId: 'com.example.beta'),
        ],
      );
      final prepared = await prepareIosInstallArtifact(
        ipa,
        options: const PrepareIosInstallArtifactOptions(
          appIdentifierHint: 'com.example.beta',
        ),
      );
      try {
        expect(prepared.bundleId, equals('com.example.beta'));
        expect(prepared.installablePath.endsWith('Beta.app'), isTrue);
      } finally {
        await prepared.cleanup();
      }
    });

    test('multi-app .ipa resolves by bundle name hint', () async {
      final ipa = await _makeIpa(
        parent: tmp,
        archiveName: 'MultiApp.ipa',
        bundles: [
          _BundleSpec(name: 'Alpha.app', bundleId: 'com.example.alpha'),
          _BundleSpec(name: 'Beta.app', bundleId: 'com.example.beta'),
        ],
      );
      final prepared = await prepareIosInstallArtifact(
        ipa,
        options: const PrepareIosInstallArtifactOptions(
          appIdentifierHint: 'Alpha',
        ),
      );
      try {
        expect(prepared.bundleId, equals('com.example.alpha'));
      } finally {
        await prepared.cleanup();
      }
    });

    test('rejects .ipa with no .app under Payload', () async {
      final ipa = p.join(tmp.path, 'Empty.ipa');
      // Create an empty Payload directory and zip it.
      final stage = await Directory(p.join(tmp.path, 'stage-empty')).create();
      await Directory(p.join(stage.path, 'Payload')).create();
      await _zip(stage.path, ipa);
      await expectLater(
        () => prepareIosInstallArtifact(ipa),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('expected at least one .app'),
        )),
      );
    });

    test('rejects unknown source extensions', () async {
      final txt = File(p.join(tmp.path, 'not-an-app.txt'));
      await txt.writeAsString('hi');
      await expectLater(
        () => prepareIosInstallArtifact(txt.path),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('Expected an iOS .app directory or .ipa file'),
        )),
      );
    });

    test('rejects missing source path', () async {
      await expectLater(
        () => prepareIosInstallArtifact(
          p.join(tmp.path, 'nope.app'),
        ),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('not found'),
        )),
      );
    });
  });
}

class _BundleSpec {
  final String name; // e.g. "Demo.app"
  final String bundleId;
  _BundleSpec({required this.name, required this.bundleId});
}

/// Build a minimal `.app` directory containing an `Info.plist` with
/// the requested keys. plutil happily reads it.
Future<String> _makeAppBundle({
  required Directory parent,
  required String name,
  required String bundleId,
  String? displayName,
}) async {
  final app = await Directory(p.join(parent.path, name)).create();
  final infoPlist = File(p.join(app.path, 'Info.plist'));
  // Use plutil to author the plist so we exercise the same toolchain
  // that prepareIosInstallArtifact uses to read it.
  await infoPlist.writeAsString('{}');
  await Process.run('plutil', ['-convert', 'xml1', infoPlist.path]);
  await Process.run('plutil', [
    '-insert',
    'CFBundleIdentifier',
    '-string',
    bundleId,
    infoPlist.path,
  ]);
  if (displayName != null) {
    await Process.run('plutil', [
      '-insert',
      'CFBundleDisplayName',
      '-string',
      displayName,
      infoPlist.path,
    ]);
  }
  await Process.run('plutil', ['-convert', 'binary1', infoPlist.path]);
  return app.path;
}

/// Build a `.ipa` archive with a `Payload/` containing the given
/// bundles. Zipped via the `zip` cli (ships with macOS).
Future<String> _makeIpa({
  required Directory parent,
  required String archiveName,
  required List<_BundleSpec> bundles,
}) async {
  final stage = await Directory(
    p.join(parent.path, 'stage-${archiveName.replaceAll('.', '-')}'),
  ).create();
  final payload = await Directory(p.join(stage.path, 'Payload')).create();
  for (final b in bundles) {
    await _makeAppBundle(
      parent: payload,
      name: b.name,
      bundleId: b.bundleId,
    );
  }
  final ipa = p.join(parent.path, archiveName);
  await _zip(stage.path, ipa);
  return ipa;
}

Future<void> _zip(String stageDir, String outIpa) async {
  // `zip -r <out> Payload` from inside stageDir keeps the archive's
  // root entry as `Payload/...`, matching real .ipa structure.
  final r = await Process.run(
    'zip',
    ['-qr', outIpa, '.'],
    workingDirectory: stageDir,
  );
  if (r.exitCode != 0) {
    throw StateError('zip failed: ${r.stderr}');
  }
}
