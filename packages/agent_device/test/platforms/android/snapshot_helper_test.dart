// Port of agent-device/src/platforms/android/__tests__/snapshot-helper.test.ts

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/platforms/android/snapshot_helper_artifact.dart';
import 'package:agent_device/src/platforms/android/snapshot_helper_capture.dart';
import 'package:agent_device/src/platforms/android/snapshot_helper_install.dart';
import 'package:agent_device/src/platforms/android/snapshot_helper_types.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _manifest = AndroidSnapshotHelperManifest(
  name: 'android-snapshot-helper',
  version: '0.13.3',
  apkUrl: null,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', // 64 'a's
  packageName: 'com.callstack.agentdevice.snapshothelper',
  versionCode: 13003,
  instrumentationRunner:
      'com.callstack.agentdevice.snapshothelper/.SnapshotInstrumentation',
  minSdk: 23,
  targetSdk: 36,
  outputFormat: 'uiautomator-xml',
  statusProtocol: 'android-snapshot-helper-v1',
  installArgs: ['install', '-r', '-t'],
);

void main() {
  // ---------------------------------------------------------------------------
  // parseAndroidSnapshotHelperOutput
  // ---------------------------------------------------------------------------

  group('parseAndroidSnapshotHelperOutput', () {
    test('reconstructs XML chunks and metadata', () {
      const xml =
          '<?xml version="1.0"?><hierarchy><node text="first&#10;second" /></hierarchy>';
      final output = _helperOutput(
        chunks: [
          '<?xml version="1.0"?><hierarchy>',
          '<node text="first&#10;second" /></hierarchy>',
        ],
        result: {
          'ok': 'true',
          'helperApiVersion': '1',
          'outputFormat': 'uiautomator-xml',
          'waitForIdleTimeoutMs': '25',
          'timeoutMs': '8000',
          'maxDepth': '128',
          'maxNodes': '5000',
          'rootPresent': 'true',
          'captureMode': 'interactive-windows',
          'windowCount': '2',
          'nodeCount': '1',
          'truncated': 'false',
          'elapsedMs': '42',
        },
      );

      final parsed = parseAndroidSnapshotHelperOutput(output);

      expect(parsed.xml, equals(xml));
      expect(parsed.metadata.helperApiVersion, equals('1'));
      expect(parsed.metadata.outputFormat, equals('uiautomator-xml'));
      expect(parsed.metadata.waitForIdleTimeoutMs, equals(25));
      expect(parsed.metadata.timeoutMs, equals(8000));
      expect(parsed.metadata.maxDepth, equals(128));
      expect(parsed.metadata.maxNodes, equals(5000));
      expect(parsed.metadata.rootPresent, isTrue);
      expect(parsed.metadata.captureMode, equals('interactive-windows'));
      expect(parsed.metadata.windowCount, equals(2));
      expect(parsed.metadata.nodeCount, equals(1));
      expect(parsed.metadata.truncated, isFalse);
      expect(parsed.metadata.elapsedMs, equals(42));
    });

    test('decodes UTF-8 across byte chunk boundaries', () {
      const xml = '<hierarchy><node text="Save 👍" /></hierarchy>';
      final bytes = utf8.encode(xml);
      // Find the 4-byte emoji sequence (0xF0 start byte) and split mid-sequence.
      final splitAt = bytes.indexOf(0xF0) + 2;
      final output = [
        _statusRecord({
          'chunkIndex': '0',
          'chunkCount': '2',
          'payloadBase64': base64.encode(bytes.sublist(0, splitAt)),
        }),
        _statusRecord({
          'chunkIndex': '1',
          'chunkCount': '2',
          'payloadBase64': base64.encode(bytes.sublist(splitAt)),
        }),
        _resultRecord({'ok': 'true', 'outputFormat': 'uiautomator-xml'}),
        'INSTRUMENTATION_CODE: 0',
      ].join('\n');

      final parsed = parseAndroidSnapshotHelperOutput(output);

      expect(parsed.xml, equals(xml));
    });

    test('rejects incomplete chunks', () {
      final output = [
        _statusRecord({
          'chunkIndex': '0',
          'chunkCount': '2',
          'payloadBase64': _encodeChunk('<hierarchy>'),
        }),
        _resultRecord({'ok': 'true', 'outputFormat': 'uiautomator-xml'}),
        'INSTRUMENTATION_CODE: 0',
      ].join('\n');

      expect(
        () => parseAndroidSnapshotHelperOutput(output),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('incomplete XML chunks'),
          ),
        ),
      );
    });

    test('treats empty chunk payload as present (but invalid XML)', () {
      final output = [
        _statusRecord({
          'chunkIndex': '0',
          'chunkCount': '1',
          'payloadBase64': '',
        }),
        _resultRecord({'ok': 'true', 'outputFormat': 'uiautomator-xml'}),
        'INSTRUMENTATION_CODE: 0',
      ].join('\n');

      expect(
        () => parseAndroidSnapshotHelperOutput(output),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('did not contain XML'),
          ),
        ),
      );
    });

    test('rejects duplicate chunks', () {
      final output = [
        _statusRecord({
          'chunkIndex': '0',
          'chunkCount': '2',
          'payloadBase64': _encodeChunk('<hierarchy>'),
        }),
        _statusRecord({
          'chunkIndex': '0',
          'chunkCount': '2',
          'payloadBase64': _encodeChunk('</hierarchy>'),
        }),
        _resultRecord({'ok': 'true', 'outputFormat': 'uiautomator-xml'}),
        'INSTRUMENTATION_CODE: 0',
      ].join('\n');

      expect(
        () => parseAndroidSnapshotHelperOutput(output),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('duplicate XML chunks'),
          ),
        ),
      );
    });

    test('falls back to error type for null helper messages', () {
      final output = [
        _statusRecord({
          'chunkIndex': '0',
          'chunkCount': '1',
          'payloadBase64': _encodeChunk('<hierarchy />'),
        }),
        _resultRecord({
          'ok': 'false',
          'outputFormat': 'uiautomator-xml',
          'errorType': 'java.lang.IllegalStateException',
          'message': 'null',
        }),
        'INSTRUMENTATION_CODE: 1',
      ].join('\n');

      expect(
        () => parseAndroidSnapshotHelperOutput(output),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            equals('java.lang.IllegalStateException'),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // parseAndroidSnapshotHelperXml
  // ---------------------------------------------------------------------------

  group('parseAndroidSnapshotHelperXml', () {
    test('returns shaped nodes from captured helper output', () {
      final parsed = parseAndroidSnapshotHelperXml(
        '<hierarchy><node text="Continue" class="android.widget.Button" bounds="[1,2][21,42]" clickable="true" /><node text="Keyboard suggestion" class="android.widget.TextView" bounds="[1,44][121,84]" /></hierarchy>',
        metadata: const AndroidSnapshotHelperMetadata(
          outputFormat: 'uiautomator-xml',
          captureMode: 'interactive-windows',
          windowCount: 2,
          nodeCount: 2,
        ),
      );

      expect(parsed.nodes[0].label, equals('Continue'));
      expect(parsed.nodes[0].hittable, isTrue);
      expect(parsed.nodes[0].rect?.x, equals(1));
      expect(parsed.nodes[0].rect?.y, equals(2));
      expect(parsed.nodes[0].rect?.width, equals(20));
      expect(parsed.nodes[0].rect?.height, equals(40));
      expect(parsed.nodes[1].label, equals('Keyboard suggestion'));
      expect(parsed.metadata.captureMode, equals('interactive-windows'));
      expect(parsed.metadata.windowCount, equals(2));
      expect(parsed.metadata.nodeCount, equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // ensureAndroidSnapshotHelper
  // ---------------------------------------------------------------------------

  group('ensureAndroidSnapshotHelper', () {
    test('installs when missing and skips current version', () async {
      final tmpDir =
          await Directory.systemTemp.createTemp('snapshot-helper-install-');
      final apkPath = '${tmpDir.path}/helper.apk';
      await File(apkPath).writeAsString('helper-apk');
      final localManifest = AndroidSnapshotHelperManifest(
        name: _manifest.name,
        version: _manifest.version,
        apkUrl: _manifest.apkUrl,
        sha256: _sha256Text('helper-apk'),
        packageName: _manifest.packageName,
        versionCode: _manifest.versionCode,
        instrumentationRunner: _manifest.instrumentationRunner,
        minSdk: _manifest.minSdk,
        targetSdk: _manifest.targetSdk,
        outputFormat: _manifest.outputFormat,
        statusProtocol: _manifest.statusProtocol,
        installArgs: _manifest.installArgs,
      );

      final calls = <List<String>>[];
      Future<AdbResult> adb(
        List<String> args, {
        bool allowFailure = false,
        int? timeoutMs,
      }) async {
        calls.add(args);
        if (args.contains('--show-versioncode')) {
          return const AdbResult(exitCode: 1, stdout: '', stderr: 'not found');
        }
        return const AdbResult(exitCode: 0, stdout: '', stderr: '');
      }

      final installed = await ensureAndroidSnapshotHelper(
        adb: adb,
        artifact: AndroidSnapshotHelperArtifact(
          apkPath: apkPath,
          manifest: localManifest,
        ),
      );

      expect(installed.installed, isTrue);
      expect(installed.reason, equals('missing'));
      expect(calls[1], equals(['install', '-r', '-t', apkPath]));

      final skipped = await ensureAndroidSnapshotHelper(
        adb: (args, {bool allowFailure = false, int? timeoutMs}) async {
          return const AdbResult(
            exitCode: 0,
            stdout:
                'package:com.callstack.agentdevice.snapshothelper versionCode:13003',
            stderr: '',
          );
        },
        artifact: AndroidSnapshotHelperArtifact(
          apkPath: '/tmp/helper.apk',
          manifest: _manifest,
        ),
      );

      expect(skipped.installed, isFalse);
      expect(skipped.reason, equals('current'));

      await tmpDir.delete(recursive: true);
    });

    test('never policy does not probe device', () async {
      var called = false;
      final result = await ensureAndroidSnapshotHelper(
        adb: (args, {bool allowFailure = false, int? timeoutMs}) async {
          called = true;
          return const AdbResult(exitCode: 0, stdout: '', stderr: '');
        },
        artifact: const AndroidSnapshotHelperArtifact(
          apkPath: '/tmp/helper.apk',
          manifest: _manifest,
        ),
        installPolicy: AndroidSnapshotHelperInstallPolicy.never,
      );

      expect(called, isFalse);
      expect(result.installed, isFalse);
      expect(result.reason, equals('skipped'));
    });

    test('uninstalls and retries when signatures differ', () async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'snapshot-helper-reinstall-',
      );
      final apkPath = '${tmpDir.path}/helper.apk';
      await File(apkPath).writeAsString('helper-apk');
      final calls = <List<String>>[];
      var installAttempts = 0;

      final result = await ensureAndroidSnapshotHelper(
        adb: (args, {bool allowFailure = false, int? timeoutMs}) async {
          calls.add(args);
          if (args.contains('--show-versioncode')) {
            return const AdbResult(
              exitCode: 0,
              stdout:
                  'package:com.callstack.agentdevice.snapshothelper versionCode:1',
              stderr: '',
            );
          }
          if (args[0] == 'install') {
            installAttempts += 1;
            if (installAttempts == 1) {
              return const AdbResult(
                exitCode: 1,
                stdout: '',
                stderr: 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]',
              );
            }
          }
          return const AdbResult(exitCode: 0, stdout: '', stderr: '');
        },
        artifact: AndroidSnapshotHelperArtifact(
          apkPath: apkPath,
          manifest: AndroidSnapshotHelperManifest(
            name: _manifest.name,
            version: _manifest.version,
            apkUrl: _manifest.apkUrl,
            sha256: _sha256Text('helper-apk'),
            packageName: _manifest.packageName,
            versionCode: _manifest.versionCode,
            instrumentationRunner: _manifest.instrumentationRunner,
            minSdk: _manifest.minSdk,
            targetSdk: _manifest.targetSdk,
            outputFormat: _manifest.outputFormat,
            statusProtocol: _manifest.statusProtocol,
            installArgs: _manifest.installArgs,
          ),
        ),
      );

      expect(result.installed, isTrue);
      expect(result.reason, equals('outdated'));
      expect(calls[1], equals(['install', '-r', '-t', apkPath]));
      expect(
        calls[2],
        equals(['uninstall', 'com.callstack.agentdevice.snapshothelper']),
      );
      expect(calls[3], equals(['install', '-r', '-t', apkPath]));

      await tmpDir.delete(recursive: true);
    });
  });

  // ---------------------------------------------------------------------------
  // verifyAndroidSnapshotHelperArtifact
  // ---------------------------------------------------------------------------

  group('verifyAndroidSnapshotHelperArtifact', () {
    test('rejects checksum mismatch', () async {
      final tmpDir = await Directory.systemTemp.createTemp('snapshot-helper-sha-');
      final apkPath = '${tmpDir.path}/helper.apk';
      await File(apkPath).writeAsString('actual');

      await expectLater(
        verifyAndroidSnapshotHelperArtifact(
          AndroidSnapshotHelperArtifact(
            apkPath: apkPath,
            manifest: AndroidSnapshotHelperManifest(
              name: _manifest.name,
              version: _manifest.version,
              apkUrl: _manifest.apkUrl,
              sha256: _sha256Text('expected'),
              packageName: _manifest.packageName,
              versionCode: _manifest.versionCode,
              instrumentationRunner: _manifest.instrumentationRunner,
              minSdk: _manifest.minSdk,
              targetSdk: _manifest.targetSdk,
              outputFormat: _manifest.outputFormat,
              statusProtocol: _manifest.statusProtocol,
              installArgs: _manifest.installArgs,
            ),
          ),
        ),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('checksum mismatch'),
          ),
        ),
      );

      await tmpDir.delete(recursive: true);
    });
  });

  // ---------------------------------------------------------------------------
  // captureAndroidSnapshotWithHelper
  // ---------------------------------------------------------------------------

  group('captureAndroidSnapshotWithHelper', () {
    test('uses injected adb executor', () async {
      List<String>? capturedArgs;
      int? capturedTimeoutMs;

      final result = await captureAndroidSnapshotWithHelper(
        AndroidSnapshotHelperCaptureOptions(
          adb: (args, {bool allowFailure = false, int? timeoutMs}) async {
            capturedArgs = args;
            capturedTimeoutMs = timeoutMs;
            return AdbResult(
              exitCode: 0,
              stdout: _helperOutput(
                chunks: ['<hierarchy><node index="0" /></hierarchy>'],
                result: {
                  'ok': 'true',
                  'outputFormat': 'uiautomator-xml',
                  'waitForIdleTimeoutMs': '10',
                  'timeoutMs': '9000',
                  'maxDepth': '64',
                  'maxNodes': '100',
                },
              ),
              stderr: '',
            );
          },
          waitForIdleTimeoutMs: 10,
          timeoutMs: 9000,
          maxDepth: 64,
          maxNodes: 100,
        ),
      );

      expect(capturedArgs, equals([
        'shell', 'am', 'instrument', '-w',
        '-e', 'waitForIdleTimeoutMs', '10',
        '-e', 'timeoutMs', '9000',
        '-e', 'maxDepth', '64',
        '-e', 'maxNodes', '100',
        'com.callstack.agentdevice.snapshothelper/.SnapshotInstrumentation',
      ]));
      expect(capturedTimeoutMs, equals(14000)); // 9000 + 5000 overhead
      expect(result.xml, equals('<hierarchy><node index="0" /></hierarchy>'));
      expect(result.metadata.maxNodes, equals(100));
    });

    test('gives adb command overhead beyond helper timeout', () async {
      int? commandTimeoutMs;

      await captureAndroidSnapshotWithHelper(
        AndroidSnapshotHelperCaptureOptions(
          adb: (args, {bool allowFailure = false, int? timeoutMs}) async {
            commandTimeoutMs = timeoutMs;
            return AdbResult(
              exitCode: 0,
              stdout: _helperOutput(
                chunks: ['<hierarchy><node index="0" /></hierarchy>'],
                result: {
                  'ok': 'true',
                  'outputFormat': 'uiautomator-xml',
                  'timeoutMs': '8000',
                },
              ),
              stderr: '',
            );
          },
          timeoutMs: 8000,
        ),
      );

      expect(commandTimeoutMs, equals(13000)); // 8000 + 5000
    });

    test('wraps unparseable failed output with adb details', () async {
      await expectLater(
        captureAndroidSnapshotWithHelper(
          AndroidSnapshotHelperCaptureOptions(
            adb: (args, {bool allowFailure = false, int? timeoutMs}) async {
              return const AdbResult(
                exitCode: 1,
                stdout: '',
                stderr: 'instrumentation failed',
              );
            },
          ),
        ),
        throwsA(
          isA<AppError>()
              .having(
                (e) => e.message,
                'message',
                equals(
                  'Android snapshot helper failed before returning parseable output',
                ),
              )
              .having(
                (e) => e.details?['exitCode'],
                'exitCode',
                equals(1),
              )
              .having(
                (e) => e.details?['stderr'],
                'stderr',
                equals('instrumentation failed'),
              ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // parseAndroidSnapshotHelperManifest
  // ---------------------------------------------------------------------------

  group('parseAndroidSnapshotHelperManifest', () {
    test('validates manifest shape', () {
      final base = <String, Object?>{
        'name': 'android-snapshot-helper',
        'version': '0.13.3',
        'apkUrl': null,
        'sha256': 'a' * 64,
        'packageName': 'com.callstack.agentdevice.snapshothelper',
        'versionCode': 13003,
        'instrumentationRunner':
            'com.callstack.agentdevice.snapshothelper/.SnapshotInstrumentation',
        'minSdk': 23,
        'targetSdk': 36,
        'outputFormat': 'uiautomator-xml',
        'statusProtocol': 'android-snapshot-helper-v1',
        'installArgs': ['install', '-r', '-t'],
      };

      expect(
        () => parseAndroidSnapshotHelperManifest({...base, 'outputFormat': 'json'}),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('outputFormat must be "uiautomator-xml"'),
          ),
        ),
      );

      expect(
        () =>
            parseAndroidSnapshotHelperManifest({...base, 'installArgs': ['shell']}),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('must start with "install"'),
          ),
        ),
      );

      expect(
        () => parseAndroidSnapshotHelperManifest({
          ...base,
          'installArgs': ['install', '--user'],
        }),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('unsupported install flag "--user"'),
          ),
        ),
      );

      expect(
        () => parseAndroidSnapshotHelperManifest({...base, 'sha256': 'not-a-sha'}),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('sha256 must be a 64-character hex string'),
          ),
        ),
      );

      // SHA-256 should be trimmed and lowercased.
      final validSha256 = _sha256Text('helper-apk');
      final parsed = parseAndroidSnapshotHelperManifest({
        ...base,
        'sha256': ' ${validSha256.toUpperCase()} ',
      });
      expect(parsed.sha256, equals(validSha256));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

String _helperOutput({
  required List<String> chunks,
  required Map<String, String> result,
}) {
  return [
    for (var i = 0; i < chunks.length; i++)
      _statusRecord({
        'chunkIndex': '$i',
        'chunkCount': '${chunks.length}',
        'payloadBase64': _encodeChunk(chunks[i]),
      }),
    _resultRecord(result),
    'INSTRUMENTATION_CODE: 0',
  ].join('\n');
}

String _statusRecord(Map<String, String> values) {
  return [
    'INSTRUMENTATION_STATUS: agentDeviceProtocol=android-snapshot-helper-v1',
    'INSTRUMENTATION_STATUS: helperApiVersion=1',
    'INSTRUMENTATION_STATUS: outputFormat=uiautomator-xml',
    for (final entry in values.entries)
      'INSTRUMENTATION_STATUS: ${entry.key}=${entry.value}',
    'INSTRUMENTATION_STATUS_CODE: 1',
  ].join('\n');
}

String _encodeChunk(String value) => base64.encode(utf8.encode(value));

String _resultRecord(Map<String, String> values) {
  return [
    'INSTRUMENTATION_RESULT: agentDeviceProtocol=android-snapshot-helper-v1',
    'INSTRUMENTATION_RESULT: helperApiVersion=1',
    for (final entry in values.entries)
      'INSTRUMENTATION_RESULT: ${entry.key}=${entry.value}',
  ].join('\n');
}

String _sha256Text(String value) {
  final bytes = utf8.encode(value);
  final digest = sha256.convert(bytes);
  return digest.toString();
}
