import 'package:agent_device/src/utils/diagnostics.dart';
import 'package:test/test.dart';

void main() {
  group('diagnostics', () {
    group('createRequestId', () {
      test('generates 16-character hex string', () {
        final id = createRequestId();
        expect(id.length, 16);
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), true);
      });

      test('generates unique IDs', () {
        final ids = {for (int i = 0; i < 10; i++) createRequestId()};
        expect(ids.length, 10); // All unique
      });
    });

    group('withDiagnosticsScope', () {
      test('executes function within scope', () async {
        var executed = false;
        await withDiagnosticsScope(DiagnosticsScopeOptions(), () async {
          executed = true;
          return 'result';
        });
        expect(executed, true);
      });

      test('makes scope available via getDiagnosticsMeta', () async {
        final meta = await withDiagnosticsScope(
          DiagnosticsScopeOptions(session: 'test-session', command: 'snapshot'),
          () async {
            return getDiagnosticsMeta();
          },
        );
        expect(meta.session, 'test-session');
        expect(meta.command, 'snapshot');
        expect(meta.diagnosticId, isNotNull);
        expect(meta.diagnosticId, isNotEmpty);
      });

      test('returns function result', () async {
        final result = await withDiagnosticsScope(
          DiagnosticsScopeOptions(),
          () async => 42,
        );
        expect(result, 42);
      });

      test('propagates exceptions', () async {
        expect(
          () => withDiagnosticsScope(
            DiagnosticsScopeOptions(),
            () async => throw Exception('test error'),
          ),
          throwsException,
        );
      });
    });

    group('emitDiagnostic', () {
      test('emits event to scope', () async {
        final result = await withDiagnosticsScope(
          DiagnosticsScopeOptions(),
          () async {
            emitDiagnostic(
              EmitDiagnosticOptions(
                phase: 'test_phase',
                level: DiagnosticLevel.info,
                data: {'key': 'value'},
              ),
            );
            // No assertion possible without reflection on internal state
            return true;
          },
        );
        expect(result, true);
      });

      test('is no-op when no scope is active', () {
        // Should not throw
        emitDiagnostic(
          EmitDiagnosticOptions(phase: 'no_scope', data: {'test': 'data'}),
        );
      });
    });

    group('withDiagnosticTimer', () {
      test('completes successful function', () async {
        final result = await withDiagnosticTimer(
          'test_phase',
          () async => 'success',
        );
        expect(result, 'success');
      });

      test('re-throws exception', () async {
        expect(
          () => withDiagnosticTimer(
            'failing_phase',
            () async => throw Exception('test failure'),
          ),
          throwsException,
        );
      });

      test('passes custom data', () async {
        final result = await withDiagnosticTimer(
          'phase_with_data',
          () async => true,
          {'custom': 'data'},
        );
        expect(result, true);
      });
    });

    group('getDiagnosticsMeta', () {
      test('returns empty metadata when no scope', () {
        final meta = getDiagnosticsMeta();
        expect(meta.session, null);
        expect(meta.command, null);
        expect(meta.debug, false);
      });

      test('returns scope fields', () async {
        final meta = await withDiagnosticsScope(
          DiagnosticsScopeOptions(
            session: 'my-session',
            requestId: 'req-123',
            command: 'click',
            debug: true,
          ),
          () async => getDiagnosticsMeta(),
        );
        expect(meta.session, 'my-session');
        expect(meta.requestId, 'req-123');
        expect(meta.command, 'click');
        expect(meta.debug, true);
      });
    });

    group('flushDiagnosticsToSessionFile', () {
      test('returns null when no scope', () {
        final result = flushDiagnosticsToSessionFile();
        expect(result, null);
      });

      test('returns null when debug disabled and force false', () async {
        final result = await withDiagnosticsScope(
          DiagnosticsScopeOptions(debug: false),
          () async {
            emitDiagnostic(EmitDiagnosticOptions(phase: 'test'));
            return flushDiagnosticsToSessionFile(force: false);
          },
        );
        expect(result, null);
      });
    });
  });
}
