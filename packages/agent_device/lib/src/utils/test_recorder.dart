library;

import 'package:agent_device/src/runtime/agent_device.dart';

import 'video_chapters.dart';

/// Records video of a test session and injects chapter markers.
///
/// Usage in a test file:
/// ```dart
/// late TestRecorder recorder;
///
/// setUpAll(() async {
///   recorder = TestRecorder(device, '/tmp/test-recording.mp4');
///   await recorder.start();
/// });
///
/// tearDownAll(() async {
///   await recorder.stop();
/// });
///
/// test('my test', () async {
///   recorder.chapter('my test');
///   // ... test body
/// });
/// ```
class TestRecorder {
  final AgentDevice device;
  final String outputPath;
  final List<VideoChapter> _chapters = [];
  DateTime? _startedAt;
  bool _stopped = false;

  TestRecorder(this.device, this.outputPath);

  bool get isRecording => _startedAt != null && !_stopped;

  /// Start recording. Call in `setUpAll`.
  Future<void> start() async {
    _startedAt = DateTime.now();
    await device.startRecording(outputPath);
  }

  /// Mark a chapter at the current timestamp.
  void chapter(String title) {
    if (_startedAt == null || _stopped) return;
    _chapters.add(
      VideoChapter(title: title, start: DateTime.now().difference(_startedAt!)),
    );
  }

  /// Stop recording, finalize the file, and inject chapters.
  /// Call in `tearDownAll`.
  Future<void> stop() async {
    if (_startedAt == null || _stopped) return;
    _stopped = true;
    try {
      await device.stopRecording(outputPath);
      if (_chapters.isNotEmpty) {
        await injectMp4Chapters(outputPath, _chapters);
      }
    } catch (_) {
      // Best-effort — don't fail tests because recording broke.
    }
  }
}
