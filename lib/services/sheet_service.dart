/// The operation layer: the three entry points the UI calls, plus their DTOs
/// and progress events. All heavy work is delegated to the pure `render`
/// functions.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/geometry.dart';
import '../core/naming.dart';
import '../core/sheet_meta.dart';
import '../render/sheet_renderer.dart';

/// Phases reported while analyzing or rendering.
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

  /// Cover-fitted cells, keyed by `path::modeId`.
  ///
  /// [analyze] already decodes every source and cover-fits it to build the
  /// reorder thumbnail, so keeping that cell costs one retained image and
  /// spares [preview] and [render] from re-reading the files. Changing the
  /// memo, reordering frames, switching tabs and exporting then decode nothing
  /// at all; only a new file list or a new mode (where the cells genuinely
  /// differ) pays for decoding again.
  ///
  /// Bounded by the working set: [analyze] prunes it to exactly the frames it
  /// kept under the current mode, so there is no eviction policy to tune. Worst
  /// case is ~17 MB (42 cells of 380x272, or 72 of 218x272).
  final Map<String, ui.Image> _cells = {};

  /// Paths that failed to decode, so a broken file is not re-read on every
  /// preview. Pruned alongside [_cells].
  final Set<String> _undecodable = {};

  Stream<Progress> get progress => _progress.stream;

  void _emit(ProgressPhase phase, int done, int total) {
    if (!_progress.isClosed) _progress.add(Progress(phase, done, total));
  }

  /// Number of cached cells. Test seam — lets a test assert that a second
  /// render decoded nothing.
  int get cachedCellCount => _cells.length;

  void dispose() {
    _clearCells();
    _progress.close();
  }

  void _clearCells() {
    for (final cell in _cells.values) {
      cell.dispose();
    }
    _cells.clear();
    _undecodable.clear();
  }

  static String _cellKey(String path, FilmMode mode) => '$path::${mode.id}';

  /// Drop every cached cell outside [keep] under [mode], disposing it.
  void _pruneCells(List<String> keep, FilmMode mode) {
    final live = {for (final path in keep) _cellKey(path, mode)};
    _cells.removeWhere((key, cell) {
      if (live.contains(key)) return false;
      cell.dispose();
      return true;
    });
    _undecodable.removeWhere((path) => !keep.contains(path));
  }

  /// Cells for [paths] under [mode], reusing whatever is already cached and
  /// decoding only the misses. A null entry means the file could not be
  /// decoded and gets the gray placeholder.
  ///
  /// Cells stay owned by the cache — callers must not dispose them.
  Future<List<ui.Image?>> _cellsFor(
    List<String> paths,
    FilmMode mode,
    ProgressPhase phase,
  ) async {
    final result = List<ui.Image?>.filled(paths.length, null);
    final missing = <int>[];

    for (var i = 0; i < paths.length; i++) {
      final cached = _cells[_cellKey(paths[i], mode)];
      if (cached != null) {
        result[i] = cached;
      } else if (!_undecodable.contains(paths[i])) {
        missing.add(i);
      }
    }

    if (missing.isEmpty) return result;

    final decoded = await _mapBounded<int, ui.Image>(missing, phase, (i) async {
      final source = await _decodeOne(paths[i]);
      if (source == null) return null;
      try {
        return await renderCell(source, mode);
      } finally {
        source.dispose();
      }
    });

    for (var k = 0; k < missing.length; k++) {
      final path = paths[missing[k]];
      final cell = decoded[k];
      if (cell == null) {
        _undecodable.add(path);
      } else {
        result[missing[k]] = cell;
        _cells[_cellKey(path, mode)] = cell;
      }
    }
    return result;
  }

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

    // Build (or reuse) the cells, then drop anything outside this working set —
    // a removed file or the previous mode. Thumbnails are encoded from the very
    // cells the sheet will be composed from, so nothing is fitted twice.
    final cells = await _cellsFor(kept, mode, ProgressPhase.analyze);
    _pruneCells(kept, mode);

    final frames = <Frame>[
      for (var i = 0; i < kept.length; i++)
        Frame(
          path: kept[i],
          fileName: fileNameOf(kept[i]),
          thumb: cells[i] == null
              ? null
              : await encodeJpeg(cells[i]!, thumbQuality),
        ),
    ];

    // Signal completion so the UI clears the progress bar (it only hides on the
    // "done" phase); the per-item "analyze" events never reach it.
    _emit(ProgressPhase.done, kept.length, kept.length);

    return AnalyzeResult(frames: frames, total: total, capacity: mode.capacity);
  }

  /// Compose the sheet from cached cells, decoding only paths not already
  /// cached. The cells belong to the cache, so they are not disposed here.
  Future<ui.Image> _decodeAndCompose(
    List<String> paths,
    FilmMode mode,
    SheetMeta meta,
  ) async {
    final cells = await _cellsFor(paths, mode, ProgressPhase.decode);
    _emit(ProgressPhase.compose, 0, 1);
    return composeSheetFromCells(cells, mode, meta);
  }

  /// Decode the given images (already in final order), composite the index
  /// sheet for [mode] with the [meta] title block, JPEG-encode, and write it
  /// to `<outDir>/<fileName>.jpg`. Returns the written path.
  Future<String> render(
    List<String> paths,
    String outDir,
    String fileName,
    FilmMode mode,
    SheetMeta meta,
  ) async {
    final sheet = await _decodeAndCompose(paths, mode, meta);
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
    SheetMeta meta,
  ) async {
    final sheet = await _decodeAndCompose(paths, mode, meta);
    try {
      return await makePreview(sheet);
    } finally {
      sheet.dispose();
      _emit(ProgressPhase.done, 1, 1);
    }
  }
}
