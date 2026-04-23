/// Port of agent-device/src/platforms/android/manifest.ts.
///
/// Android manifest parsing — both plaintext XML and binary resource file formats.
/// Extracts package name from AndroidManifest.xml within APK/AAB archives using
/// unzip and binary parsing (ResXML format), with fallback to aapt tool.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/exec.dart';
import 'sdk.dart';

// ResXML binary format constants.
const int _resXmlType = 0x0003;
const int _resStringPoolType = 0x0001;
const int _resXmlStartElementType = 0x0102;
const int _utf8Flag = 0x100;
const int _typeString = 0x03;
const int _noIndex = 0xffffffff;

// aapt binary lookup cache (null = not found, empty string = pending).
String? _aaptPathCache;

/// Resolve package name from an Android APK or AAB archive.
///
/// Tries to extract AndroidManifest.xml directly via unzip and parse it,
/// falling back to base/manifest/AndroidManifest.xml for AAB bundles.
/// If binary XML parsing fails, delegates to aapt dump badging.
///
/// Returns null if the archive is invalid or missing a manifest.
Future<String?> resolveAndroidArchivePackageName(String archivePath) async {
  for (final entry in [
    'AndroidManifest.xml',
    'base/manifest/AndroidManifest.xml',
  ]) {
    final manifest = await _readZipEntry(archivePath, entry);
    if (manifest == null) continue;

    final packageName = _parseAndroidManifestPackageName(manifest);
    if (packageName != null) return packageName;
  }

  // Fallback to aapt.
  return _resolveAndroidArchivePackageNameWithAapt(archivePath);
}

/// Extract a single entry from a ZIP archive via unzip command.
Future<List<int>?> _readZipEntry(String archivePath, String entry) async {
  try {
    final result = await runCmd('unzip', [
      '-p',
      archivePath,
      entry,
    ], const ExecOptions(allowFailure: true, binaryStdout: true));

    if (result.exitCode != 0 ||
        result.stdoutBuffer == null ||
        result.stdoutBuffer!.isEmpty) {
      return null;
    }

    return result.stdoutBuffer;
  } catch (_) {
    return null;
  }
}

/// Parse package name from manifest bytes (may be binary or plaintext XML).
String? _parseAndroidManifestPackageName(List<int> manifest) {
  // Check first 128 bytes to detect plaintext XML.
  final candidate = utf8
      .decode(
        manifest.sublist(0, manifest.length < 128 ? manifest.length : 128),
        allowMalformed: true,
      )
      .trimLeft();

  if (candidate.startsWith('<')) {
    return _parseTextManifestPackageName(
      utf8.decode(manifest, allowMalformed: true),
    );
  }

  return _parseBinaryManifestPackageName(manifest);
}

/// Parse plaintext XML manifest for package attribute.
String? _parseTextManifestPackageName(String text) {
  // Match: <manifest ... package="..." or package='...'
  final doubleQuoteMatch = RegExp(
    r'<manifest\b[^>]*\bpackage\s*=\s*"([^"]+)"',
    caseSensitive: false,
  ).firstMatch(text);
  if (doubleQuoteMatch != null) return doubleQuoteMatch.group(1);

  final singleQuoteMatch = RegExp(
    r"<manifest\b[^>]*\bpackage\s*=\s*'([^']+)'",
    caseSensitive: false,
  ).firstMatch(text);
  return singleQuoteMatch?.group(1);
}

/// Parse binary ResXML manifest for package name.
///
/// ResXML is a binary format with chunks: string pool, XML elements, etc.
/// We scan for the manifest element and extract the package attribute.
String? _parseBinaryManifestPackageName(List<int> buffer) {
  if (buffer.length < 8 || _readUint16LE(buffer, 0) != _resXmlType) {
    return null;
  }

  String? strings;
  int offset = _readUint16LE(buffer, 2);

  while (offset + 8 <= buffer.length) {
    final type = _readUint16LE(buffer, offset);
    final headerSize = _readUint16LE(buffer, offset + 2);
    final chunkSize = _readUint32LE(buffer, offset + 4);

    if (chunkSize <= 0 || offset + chunkSize > buffer.length) {
      return null;
    }

    if (type == _resStringPoolType) {
      strings = _parseStringPool(buffer, offset, chunkSize);
    } else if (type == _resXmlStartElementType && strings != null) {
      final packageName = _parseStartElementPackageName(
        buffer,
        offset,
        headerSize,
        strings,
      );
      if (packageName != null) return packageName;
    }

    offset += chunkSize;
  }

  return null;
}

/// Parse a string pool chunk from ResXML.
String? _parseStringPool(List<int> buffer, int chunkOffset, int chunkSize) {
  final chunk = buffer.sublist(chunkOffset, chunkOffset + chunkSize);
  if (chunk.length < 28) return null;

  final stringCount = _readUint32LE(chunk, 8);
  final flags = _readUint32LE(chunk, 16);
  final stringsStart = _readUint32LE(chunk, 20);
  final isUtf8 = (flags & _utf8Flag) != 0;

  const offsetsStart = 28;
  final strings = <String>[];

  for (int index = 0; index < stringCount; index += 1) {
    final offsetPosition = offsetsStart + index * 4;
    if (offsetPosition + 4 > chunk.length) break;

    final stringOffset = _readUint32LE(chunk, offsetPosition);
    final absoluteOffset = stringsStart + stringOffset;

    final str = isUtf8
        ? _readUtf8String(chunk, absoluteOffset)
        : _readUtf16String(chunk, absoluteOffset);

    strings.add(str);
  }

  return stringCount > 0 ? strings.join('::') : null; // Join for later lookup.
}

/// Read a UTF-8 string from the given offset in a buffer.
String _readUtf8String(List<int> chunk, int offset) {
  final (length, lengthBytes) = _readLength8(chunk, offset);
  final (byteLength, byteLengthBytes) = _readLength8(
    chunk,
    offset + lengthBytes,
  );
  final start = offset + lengthBytes + byteLengthBytes;
  return utf8.decode(
    chunk.sublist(start, start + byteLength),
    allowMalformed: true,
  );
}

/// Read a UTF-16LE string from the given offset in a buffer.
String _readUtf16String(List<int> chunk, int offset) {
  final (charLength, lengthBytes) = _readLength16(chunk, offset);
  final start = offset + lengthBytes;
  final end = start + charLength * 2;
  return utf8.decode(chunk.sublist(start, end), allowMalformed: true);
}

/// Read a variable-length integer (UTF-8 format) from buffer.
(int, int) _readLength8(List<int> chunk, int offset) {
  final first = chunk[offset];
  if ((first & 0x80) == 0) return (first, 1);
  final second = chunk[offset + 1];
  return (((first & 0x7f) << 8) | second, 2);
}

/// Read a variable-length short (UTF-16 format) from buffer.
(int, int) _readLength16(List<int> chunk, int offset) {
  final first = _readUint16LE(chunk, offset);
  if ((first & 0x8000) == 0) return (first, 2);
  final second = _readUint16LE(chunk, offset + 2);
  return (((first & 0x7fff) << 16) | second, 4);
}

/// Parse start element (manifest) and extract package attribute.
String? _parseStartElementPackageName(
  List<int> buffer,
  int chunkOffset,
  int headerSize,
  String strings,
) {
  if (headerSize < 36 || chunkOffset + headerSize > buffer.length) {
    return null;
  }

  final nameIndex = _readUint32LE(buffer, chunkOffset + 20);
  final stringList = strings.split('::');
  if (nameIndex >= stringList.length || stringList[nameIndex] != 'manifest') {
    return null;
  }

  final attributeStart = _readUint16LE(buffer, chunkOffset + 24);
  final attributeSize = _readUint16LE(buffer, chunkOffset + 26);
  final attributeCount = _readUint16LE(buffer, chunkOffset + 28);
  final firstAttributeOffset = chunkOffset + attributeStart;

  for (int index = 0; index < attributeCount; index += 1) {
    final attributeOffset = firstAttributeOffset + index * attributeSize;
    if (attributeOffset + 20 > buffer.length) return null;

    final attrNameIndex = _readUint32LE(buffer, attributeOffset + 4);
    final attributeName = attrNameIndex < stringList.length
        ? stringList[attrNameIndex]
        : null;

    if (attributeName != 'package') continue;

    final rawValueIndex = _readUint32LE(buffer, attributeOffset + 8);
    if (rawValueIndex != _noIndex) {
      return rawValueIndex < stringList.length
          ? stringList[rawValueIndex]
          : null;
    }

    final dataType = buffer[attributeOffset + 15];
    final data = _readUint32LE(buffer, attributeOffset + 16);
    if (dataType == _typeString) {
      return data < stringList.length ? stringList[data] : null;
    }

    return null;
  }

  return null;
}

/// Read unsigned 16-bit little-endian integer from buffer at offset.
int _readUint16LE(List<int> buffer, int offset) {
  return buffer[offset] | (buffer[offset + 1] << 8);
}

/// Read unsigned 32-bit little-endian integer from buffer at offset.
int _readUint32LE(List<int> buffer, int offset) {
  return buffer[offset] |
      (buffer[offset + 1] << 8) |
      (buffer[offset + 2] << 16) |
      (buffer[offset + 3] << 24);
}

/// Resolve package name via aapt dump badging command.
Future<String?> _resolveAndroidArchivePackageNameWithAapt(
  String archivePath,
) async {
  final aaptPath = await _resolveAaptPath();
  if (aaptPath == null) return null;

  final result = await runCmd(aaptPath, [
    'dump',
    'badging',
    archivePath,
  ], const ExecOptions(allowFailure: true));

  if (result.exitCode != 0) return null;

  final match = RegExp(r"package:\s+name='([^']+)'").firstMatch(result.stdout);
  return match?.group(1);
}

/// Locate aapt binary in Android SDK build-tools.
///
/// Searches build-tools/ directories sorted by version (descending) and
/// returns the first executable aapt found. Caches the result.
Future<String?> _resolveAaptPath() async {
  if (_aaptPathCache != null) {
    return _aaptPathCache == '' ? null : _aaptPathCache;
  }

  try {
    for (final sdkRoot in resolveAndroidSdkRoots()) {
      final buildToolsDir = p.join(sdkRoot, 'build-tools');
      try {
        final versions = await Directory(buildToolsDir).list().toList();
        final dirNames = versions
            .whereType<Directory>()
            .map((e) => p.basename(e.path))
            .toList();

        // Sort versions in descending order.
        dirNames.sort((a, b) => b.compareTo(a));

        for (final version in dirNames) {
          final candidate = p.join(buildToolsDir, version, 'aapt');
          if (p.isAbsolute(candidate) && await _isExecutableFile(candidate)) {
            _aaptPathCache = candidate;
            return candidate;
          }
        }
      } catch (_) {
        // Ignore missing build-tools for this SDK root.
      }
    }
  } catch (_) {
    // Ignore SDK lookup failures.
  }

  _aaptPathCache = '';
  return null;
}

/// Check if a file exists and is executable.
Future<bool> _isExecutableFile(String path) async {
  try {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.file) return false;
    // On Unix, check execute bit; on Windows, assume .exe is executable.
    return !Platform.isWindows;
  } catch (_) {
    return false;
  }
}
