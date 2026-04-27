library;

import 'dart:io';

import 'package:agent_device/src/utils/exec.dart';

class VideoChapter {
  final String title;
  final Duration start;

  const VideoChapter({required this.title, required this.start});
}

/// Inject chapter metadata into an MP4 file using ffmpeg.
/// Returns the output path (same as [mp4Path] — modified in place via
/// a tmp file swap). No-ops gracefully if ffmpeg is not installed.
Future<String> injectMp4Chapters(
  String mp4Path,
  List<VideoChapter> chapters,
) async {
  if (chapters.isEmpty) return mp4Path;
  if (!await _hasFfmpeg()) return mp4Path;

  final metadataFile = File('$mp4Path.chapters.txt');
  try {
    final buf = StringBuffer(';FFMETADATA1\n');
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final startMs = ch.start.inMilliseconds;
      final endMs = i + 1 < chapters.length
          ? chapters[i + 1].start.inMilliseconds
          : null;
      buf.writeln('[CHAPTER]');
      buf.writeln('TIMEBASE=1/1000');
      buf.writeln('START=$startMs');
      if (endMs != null) {
        buf.writeln('END=$endMs');
      }
      buf.writeln('title=${_escapeMetadata(ch.title)}');
    }
    await metadataFile.writeAsString(buf.toString());

    final tmpOut = '$mp4Path.chaptered.mp4';
    final result = await runCmd('ffmpeg', [
      '-i',
      mp4Path,
      '-i',
      metadataFile.path,
      '-map_metadata',
      '1',
      '-codec',
      'copy',
      '-y',
      tmpOut,
    ], const ExecOptions(allowFailure: true));

    if (result.exitCode == 0 && await File(tmpOut).exists()) {
      await File(tmpOut).rename(mp4Path);
    } else {
      final tmp = File(tmpOut);
      if (await tmp.exists()) await tmp.delete();
    }
  } finally {
    if (await metadataFile.exists()) await metadataFile.delete();
  }
  return mp4Path;
}

String _escapeMetadata(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('=', '\\=')
    .replaceAll(';', '\\;')
    .replaceAll('#', '\\#')
    .replaceAll('\n', ' ');

Future<bool> _hasFfmpeg() async {
  try {
    final r = await Process.run('ffmpeg', ['-version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
