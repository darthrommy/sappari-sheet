/// Filename acceptance, sanitization, output-path building, and the
/// numeric-aware ("natural") ordering used to sort frames by filename.
///
/// Port of `negadice/src-tauri/src/naming.rs` — spec §5, tier [EXACT].
library;

import 'dart:convert';

const String fallbackName = 'index_sheet';

const Set<String> _acceptedExtensions = {'jpg', 'jpeg', 'png'};

/// Reserved on Windows filesystems; replaced with `_`.
const Set<int> _reservedCodeUnits = {
  0x3C, // <
  0x3E, // >
  0x3A, // :
  0x22, // "
  0x2F, // /
  0x5C, // \
  0x7C, // |
  0x3F, // ?
  0x2A, // *
};

/// Last path segment of [path], handling both separators. Falls back to the
/// whole string when there is no separator.
String fileNameOf(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  if (cut < 0) return path;
  final name = path.substring(cut + 1);
  return name.isEmpty ? path : name;
}

/// True when [path] ends in a supported image extension (case-insensitive).
/// A name with no extension is rejected.
bool isAccepted(String path) {
  final name = fileNameOf(path);
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return false;
  return _acceptedExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Replace filesystem-reserved and control characters with `_`, strip trailing
/// dots and spaces, and fall back to [fallbackName] when nothing survives.
String sanitizeFileName(String name) {
  final buffer = StringBuffer();
  for (final rune in name.trim().runes) {
    if (_reservedCodeUnits.contains(rune) || rune < 0x20) {
      buffer.write('_');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  var s = buffer.toString();
  while (s.endsWith('.') || s.endsWith(' ')) {
    s = s.substring(0, s.length - 1);
  }
  return s.isEmpty ? fallbackName : s;
}

/// `<folder><sep><sanitized>.jpg`, picking the separator already used by
/// [folder] so Windows and POSIX paths both come out well-formed.
String buildOutputPath(String folder, String fileBase) {
  final sep = folder.contains(r'\') ? r'\' : '/';
  return '$folder$sep${sanitizeFileName(fileBase)}.jpg';
}

List<int> _trimLeadingZeros(List<int> digits) {
  var i = 0;
  while (i + 1 < digits.length && digits[i] == 0x30) {
    i++;
  }
  return digits.sublist(i);
}

bool _isDigit(int b) => b >= 0x30 && b <= 0x39;

int _toAsciiLower(int b) => (b >= 0x41 && b <= 0x5A) ? b + 0x20 : b;

int _compareBytes(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return a.length.compareTo(b.length);
}

/// Compare filenames the way a file manager does: digit runs compare by numeric
/// value, everything else case-insensitively left to right.
///
/// Operates on UTF-8 bytes so the ordering matches the Rust original exactly.
int naturalCmp(String aStr, String bStr) {
  final a = utf8.encode(aStr);
  final b = utf8.encode(bStr);
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (_isDigit(a[i]) && _isDigit(b[j])) {
      final startA = i;
      while (i < a.length && _isDigit(a[i])) {
        i++;
      }
      final startB = j;
      while (j < b.length && _isDigit(b[j])) {
        j++;
      }
      final na = _trimLeadingZeros(a.sublist(startA, i));
      final nb = _trimLeadingZeros(b.sublist(startB, j));
      // Longer digit run (after zero-stripping) is the larger number; equal
      // lengths fall back to lexicographic, which is numeric for equal widths.
      final byLength = na.length.compareTo(nb.length);
      final cmp = byLength != 0 ? byLength : _compareBytes(na, nb);
      if (cmp != 0) return cmp;
    } else {
      final cmp = _toAsciiLower(a[i]).compareTo(_toAsciiLower(b[j]));
      if (cmp != 0) return cmp;
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}
