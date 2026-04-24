// Port of agent-device/src/daemon/__tests__/network-log.test.ts.
library;

import 'dart:io';

import 'package:agent_device/src/diagnostics/network_log.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ad-network-log-');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File writeLog(String content) {
    final f = File(p.join(tmp.path, 'app.log'));
    f.writeAsStringSync(content);
    return f;
  }

  test('parses latest HTTP entries from session log', () {
    final log = writeLog(
      [
        '2026-02-24T10:00:00Z GET https://api.example.com/v1/profile status=200',
        '2026-02-24T10:00:02Z {"method":"POST","url":"https://api.example.com/v1/login","statusCode":401,"headers":{"x-id":"abc"},"requestBody":{"email":"u@example.com"},"responseBody":{"error":"denied"}}',
        'non-network-line',
      ].join('\n'),
    );

    final dump = readRecentNetworkTraffic(
      log.path,
      backend: NetworkLogBackend.iosSimulator,
      maxEntries: 5,
      include: NetworkIncludeMode.all,
      maxPayloadChars: 2048,
      maxScanLines: 100,
    );

    expect(dump.exists, isTrue);
    expect(dump.entries, hasLength(2));
    // Newest first (reverse-scan).
    expect(dump.entries[0].method, 'POST');
    expect(dump.entries[0].url, 'https://api.example.com/v1/login');
    expect(dump.entries[0].status, 401);
    expect(dump.entries[0].timestamp, '2026-02-24T10:00:02Z');
    expect(dump.entries[0].headers, isA<String>());
    expect(dump.entries[0].requestBody, isA<String>());
    expect(dump.entries[0].responseBody, isA<String>());
    expect(dump.entries[1].method, 'GET');
    expect(dump.entries[1].status, 200);
    expect(dump.entries[1].timestamp, '2026-02-24T10:00:00Z');
  });

  test('enriches Android GIBSDK URL lines with timing metadata across lines', () {
    final log = writeLog(
      [
        '03-31 17:43:32.564 V/GIBSDK  (17434): [NetworkAgent]: packet id 23911610 added, queue size: 1',
        '03-31 17:43:33.031 D/GIBSDK  (17434): [NetworkAgent] packet id 23911610 total elapsed request/response time, ms: 377; response code: 200;',
        '03-31 17:43:33.031 D/GIBSDK  (17434): URL: https://www.expensify.com/api/fl?as=2.0.2816300925',
        '03-31 17:43:33.032 V/GIBSDK  (17434): [NetworkAgent]: packet id 23911610 sent successfully, 0 left in queue',
      ].join('\n'),
    );

    final dump = readRecentNetworkTraffic(
      log.path,
      backend: NetworkLogBackend.android,
      maxEntries: 5,
      include: NetworkIncludeMode.summary,
      maxPayloadChars: 2048,
      maxScanLines: 100,
    );

    expect(dump.entries, hasLength(1));
    expect(
      dump.entries[0].url,
      'https://www.expensify.com/api/fl?as=2.0.2816300925',
    );
    expect(dump.entries[0].timestamp, '03-31 17:43:33.031');
    expect(dump.entries[0].status, 200);
    expect(dump.entries[0].durationMs, 377);
    expect(dump.entries[0].packetId, '23911610');
  });

  test('tolerates interleaved Android lines within the packet scan window', () {
    final log = writeLog(
      [
        '03-31 17:43:32.564 V/GIBSDK  (17434): [NetworkAgent]: packet id 23911610 added, queue size: 1',
        '03-31 17:43:32.700 V/OtherTag (17434): unrelated line 1',
        '03-31 17:43:32.800 V/OtherTag (17434): unrelated line 2',
        '03-31 17:43:32.900 V/OtherTag (17434): unrelated line 3',
        '03-31 17:43:33.000 V/OtherTag (17434): unrelated line 4',
        '03-31 17:43:33.031 D/GIBSDK  (17434): [NetworkAgent] packet id 23911610 total elapsed request/response time, ms: 377; response code: 200;',
        '03-31 17:43:33.032 D/GIBSDK  (17434): URL: https://www.expensify.com/api/fl?as=2.0.2816300925',
      ].join('\n'),
    );

    final dump = readRecentNetworkTraffic(
      log.path,
      backend: NetworkLogBackend.android,
      maxEntries: 5,
      include: NetworkIncludeMode.summary,
      maxPayloadChars: 2048,
      maxScanLines: 100,
    );

    expect(dump.entries, hasLength(1));
    expect(dump.entries[0].status, 200);
    expect(dump.entries[0].durationMs, 377);
    expect(dump.entries[0].packetId, '23911610');
  });

  test('keeps Android packet enrichment disabled for Apple backends', () {
    final log = writeLog(
      [
        '2026-03-31 17:43:33.031 response code: 200',
        '2026-03-31 17:43:33.032 URL: https://www.expensify.com/api/fl?as=2.0.2816300925',
      ].join('\n'),
    );

    final dump = readRecentNetworkTraffic(
      log.path,
      backend: NetworkLogBackend.macos,
      maxEntries: 5,
      include: NetworkIncludeMode.summary,
      maxPayloadChars: 2048,
      maxScanLines: 100,
    );

    expect(dump.entries, hasLength(1));
    expect(
      dump.entries[0].url,
      'https://www.expensify.com/api/fl?as=2.0.2816300925',
    );
    expect(dump.entries[0].timestamp, '2026-03-31 17:43:33.032');
    expect(dump.entries[0].status, isNull);
    expect(dump.entries[0].durationMs, isNull);
  });

  test('ignores plain documentation URLs in non-network log messages', () {
    final log = writeLog(
      '2026-04-02 08:14:44.371 E New Expensify Dev[32193:8c7e18d] Airship '
      'config warning. See '
      'https://docs.airship.com/platform/mobile/setup/sdk/ios/#url-allow-list '
      'for more information.\n',
    );

    final dump = readRecentNetworkTraffic(
      log.path,
      backend: NetworkLogBackend.iosSimulator,
      maxEntries: 5,
      include: NetworkIncludeMode.summary,
      maxPayloadChars: 2048,
      maxScanLines: 100,
    );
    expect(dump.entries, isEmpty);
  });

  test('returns empty result when log file is missing', () {
    final missing = p.join(tmp.path, 'does-not-exist', 'app.log');
    final dump = readRecentNetworkTraffic(
      missing,
      backend: NetworkLogBackend.android,
      maxEntries: 10,
    );
    expect(dump.exists, isFalse);
    expect(dump.entries, isEmpty);
  });

  test('mergeNetworkDumps dedups on timestamp|method|url|status|raw', () {
    final t = '2026-02-24T10:00:00Z';
    final e1 = NetworkEntry(
      url: 'https://a.example/one',
      raw: 'raw1',
      line: 1,
      method: 'GET',
      status: 200,
      timestamp: t,
    );
    final e2 = NetworkEntry(
      url: 'https://a.example/two',
      raw: 'raw2',
      line: 2,
      method: 'POST',
      status: 201,
      timestamp: t,
    );
    final primary = NetworkDump(
      path: '<test>',
      exists: true,
      scannedLines: 2,
      matchedLines: 2,
      entries: [e1, e2],
      include: NetworkIncludeMode.summary,
      limits: const NetworkDumpLimits(
        maxEntries: 25,
        maxPayloadChars: 2048,
        maxScanLines: 4000,
      ),
    );
    // Duplicate e1 + a new e3.
    final e3 = NetworkEntry(
      url: 'https://a.example/three',
      raw: 'raw3',
      line: 3,
      method: 'DELETE',
      status: 204,
      timestamp: t,
    );
    final secondary = NetworkDump(
      path: '<test>',
      exists: true,
      scannedLines: 2,
      matchedLines: 2,
      entries: [e1, e3],
      include: NetworkIncludeMode.summary,
      limits: primary.limits,
    );

    final merged = mergeNetworkDumps(primary, secondary);
    expect(merged.entries.map((e) => e.url).toList(), [
      'https://a.example/one',
      'https://a.example/two',
      'https://a.example/three',
    ]);
  });
}
