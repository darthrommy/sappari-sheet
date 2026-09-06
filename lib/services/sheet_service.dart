/// The operation layer: the three entry points the UI calls, plus their DTOs
/// and progress events.
///
/// Port of `negadice/src-tauri/src/commands.rs` — spec §6. All heavy work is
/// delegated to the pure `render` functions.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/geometry.dart';
import '../core/naming.dart';
import '../render/sheet_renderer.dart';

/// Phases reported while analyzing or rendering. Mirrors the Rust `phase`
/// string so the UI labels stay identical.
enum ProgressPhase { analyze, decode, compose, done }

class Progress {
  const Progress(this.phase, this.done, this.total);

  final ProgressPhase phase;
  final int done;
  final int total;
}

/// One accepted source image, with its reorder-grid thumbnail.
class Frame {
  const Frame({required this.path, required this.fileName, this.thumb});

  final String path;
  final String fileName;

  /// JPEG bytes for the preview cell, or null if the file could not be decoded.
  final Uint8List? thumb;
}

class AnalyzeResult {
  const AnalyzeResult({
    required this.frames,
    required this.total,
    required this.capacity,
  });

  final List<Frame> frames;

  /// Count of accepted files *before* truncation to the mode's capacity.
  final int total;
  final int capacity;
}

/// How many images to decode at once.
///
/// Replaces rayon's thread pool. Flutter's image codec already decodes off the
/// UI isolate, so bounded async concurrency — not Dart isolates — is the right
/// shape here; `ui.Image` handles cannot cross isolate boundaries anyway.
/// See `docs/DEVIATIONS.md`.
const int _decodeConcurrency = 4;

class SheetService {
  final StreamController<Progress> _progress =
      StreamController<Progress>.broadcast();

  Stream<Progress> get progress => _progress.stream;

  void _emit(ProgressPhase phase, int done, int total) {
    if (!_progress.isClosed) _progress.add(Progress(phase, done, total));
  }

  void dispose() => _progress.close();

  /// Decode a single file, returning null when it cannot be read or decoded.
  /// Decode failures are non-fatal: the slot becomes a gray placeholder.
  Future<ui.Image?> _decodeOne(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      return null;
    }
  }

  /// Run [task] over [items] with at most [_decodeConcurrency] in flight,
  /// preserving order and reporting progress under [phase].
  Future<List<R?>> _mapBounded<T, R>(
    List<T> items,
    ProgressPhase phase,
    Future<R?> Function(T) task,
  ) async {
    final results = List<R?>.filled(items.length, null);
    var done = 0;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        results[i] = await task(items[i]);
        done++;
        _emit(phase, done, items.length);
      }
    }

    final workers = List.generate(
      items.length < _decodeConcurrency ? items.length : _decodeConcurrency,
      (_) => worker(),
    );
    await Future.wait(workers);
    return results;
  }

  /// Decode every path (null for unreadable/undecodable files), emitting
  /// `decode` progress. Shared by [render] and [preview] so the on-screen
  /// preview can never drift from the exported file.
  Future<List<ui.Image?>> _decodeAll(List<String> paths) =>
      _mapBounded(paths, ProgressPhase.decode, _decodeOne);

  /// Filter to supported images, order them (natural filename order when
  /// [sort]; input order preserved otherwise, e.g. after a manual reorder or a
  /// mode switch), cap to the mode's capacity, and build preview thumbnails.
  Future<AnalyzeResult> analyze(
    List<String> paths,
    FilmMode mode, {
    required bool sort,
  }) async {
    final accepted = paths.where(isAccepted).toList();
    final total = accepted.length;
    if (sort) {
      accepted.sort((a, b) => naturalCmp(fileNameOf(a), fileNameOf(b)));
    }
    final kept = accepted.take(mode.capacity).toList();

    final thumbs = await _mapBounded<String, Uint8List>(
      kept,
      ProgressPhase.analyze,
      (path) async {
        final image = await _decodeOne(path);
        if (image == null) return null;
        try {
          return await makeThumb(image, mode);
        } finally {
          image.dispose();
        }
      },
    );

    final frames = <Frame>[
      for (var i = 0; i < kept.length; i++)
        Frame(path: kept[i], fileName: fileNameOf(kept[i]), thumb: thumbs[i]),
    ];

    // Signal completion so the UI clears the progress bar (it only hides on the
    // "done" phase); the per-item "analyze" events never reach it.
    _emit(ProgressPhase.done, kept.length, kept.length);

    return AnalyzeResult(frames: frames, total: total, capacity: mode.capacity);
  }

  Future<ui.Image> _decodeAndCompose(
    List<String> paths,
    FilmMode mode,
    String memo,
  ) async {
    final images = await _decodeAll(paths);
    _emit(ProgressPhase.compose, 0, 1);
    try {
      return await composeSheet(images, mode, memo);
    } finally {
      for (final image in images) {
        image?.dispose();
      }
    }
  }

  /// Decode the given images (already in final order), composite the index
  /// sheet for [mode] with an optional [memo] header, JPEG-encode, and write it
  /// to `<outDir>/<fileName>.jpg`. Returns the written path.
  Future<String> render(
    List<String> paths,
    String outDir,
    String fileName,
    FilmMode mode,
    String memo,
  ) async {
    final sheet = await _decodeAndCompose(paths, mode, memo);
    final Uint8List jpeg;
    try {
      jpeg = await encodeSheet(sheet);
    } finally {
      sheet.dispose();
    }

    final outPath = buildOutputPath(outDir, fileName);
    final parent = File(outPath).parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    await File(outPath).writeAsBytes(jpeg);
    _emit(ProgressPhase.done, 1, 1);
    return outPath;
  }

  /// Compose the index sheet exactly as [render] would, but instead of writing
  /// to disk return downscaled JPEG bytes for the on-screen "final output"
  /// preview.
  Future<Uint8List> preview(
    List<String> paths,
    FilmMode mode,
    String memo,
  ) async {
    final sheet = await _decodeAndCompose(paths, mode, memo);
    try {
      return await makePreview(sheet);
    } finally {
      sheet.dispose();
      _emit(ProgressPhase.done, 1, 1);
    }
  }
}
