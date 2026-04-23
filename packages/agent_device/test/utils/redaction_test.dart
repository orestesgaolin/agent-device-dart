import 'package:agent_device/src/utils/redaction.dart';
import 'package:test/test.dart';

void main() {
  test('redacts sensitive map keys', () {
    final out = redactDiagnosticData({'token': 'abc', 'ok': 'value'}) as Map;
    expect(out['token'], '[REDACTED]');
    expect(out['ok'], 'value');
  });

  test('redacts api-key variants', () {
    final out = redactDiagnosticData({'api_key': 'x', 'Api-Key': 'y'}) as Map;
    expect(out['api_key'], '[REDACTED]');
    expect(out['Api-Key'], '[REDACTED]');
  });

  test('redacts sensitive values by regex', () {
    final out = redactDiagnosticData('Bearer abc.def-123') as String;
    expect(out, '[REDACTED]');
  });

  test('masks URL credentials and query when no sensitive value matches', () {
    final out =
        redactDiagnosticData('https://user:pw@example.com/x?foo=bar') as String;
    expect(out, contains('REDACTED:REDACTED@example.com'));
    expect(out, contains('REDACTED'));
    expect(out, isNot(contains('foo=bar')));
    expect(out, isNot(contains('user:pw')));
  });

  test('sensitive value pattern wins over URL masking', () {
    // `token=123` triggers the value regex, collapsing the whole string.
    final out =
        redactDiagnosticData('https://u:p@example.com/x?token=123') as String;
    expect(out, '[REDACTED]');
  });

  test('leaves bare strings intact', () {
    expect(redactDiagnosticData('hello'), 'hello');
  });

  test('truncates very long strings', () {
    final long = 'a' * 500;
    final out = redactDiagnosticData(long) as String;
    expect(out.endsWith('<truncated>'), isTrue);
    expect(out.length, lessThan(long.length));
  });

  test('handles nested maps and lists', () {
    final input = {
      'outer': [
        {'password': 'x'},
        {'keep': 'y'},
      ],
    };
    final out = redactDiagnosticData(input) as Map;
    final list = out['outer'] as List;
    expect((list[0] as Map)['password'], '[REDACTED]');
    expect((list[1] as Map)['keep'], 'y');
  });

  test('breaks circular references', () {
    final a = <String, Object?>{};
    a['self'] = a;
    final out = redactDiagnosticData(a) as Map;
    expect(out['self'], '[Circular]');
  });
}
