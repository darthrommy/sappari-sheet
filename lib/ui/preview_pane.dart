/// Right pane: progress bar, the drag-to-reorder grid, and the debounced
/// full-sheet preview. Spec §7.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/geometry.dart';
import '../core/sheet_meta.dart';
import '../services/sheet_service.dart';
import 'theme.dart';

const Duration previewDebounce = Duration(milliseconds: 350);

const Map<ProgressPhase, String> phaseLabel = {
  ProgressPhase.analyze: '読み込み中',
  ProgressPhase.decode: '書き出し中',
  ProgressPhase.compose: '合成中',
  ProgressPhase.done: '完了',
};

class PreviewPane extends StatefulWidget {
  const PreviewPane({
    super.key,
    required this.frames,
    required this.mode,
    required this.meta,
    required this.isDraggingOver,
    required this.onPickFiles,
    required this.onReorder,
    required this.progress,
    required this.service,
  });

  final List<Frame> frames;
  final FilmMode mode;
  final SheetMeta meta;
  final bool isDraggingOver;
  final VoidCallback onPickFiles;
  final void Function(int from, int to) onReorder;
  final Progress? progress;
  final SheetService service;

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Palette.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PREVIEW - ${mode.label}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Palette.textFaint,
                  letterSpacing: 1.2,
                ),
              ),
              const Text(
                'JPEG - $sheetWidth'
                'x'
                '$sheetHeight',
                style: TextStyle(
                  fontSize: 11,
                  color: Palette.textFaint,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        if (widget.progress != null) _ProgressBar(progress: widget.progress!),
        if (widget.frames.isEmpty)
          Expanded(
            child: _EmptyState(
              mode: mode,
              isDraggingOver: widget.isDraggingOver,
              onTap: widget.onPickFiles,
            ),
          )
        else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Palette.border)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 260,
                      child: TabBar(
                        controller: _tabs,
                        indicatorColor: Palette.textPrimary,
                        labelColor: Palette.textPrimary,
                        unselectedLabelColor: Palette.textMuted,
                        labelStyle: const TextStyle(fontSize: 12),
                        tabs: const [
                          Tab(
                            icon: Icon(Icons.grid_view, size: 15),
                            text: '並べ替え',
                            height: 46,
                          ),
                          Tab(
                            icon: Icon(Icons.image_outlined, size: 15),
                            text: 'プレビュー',
                            height: 46,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ReorderGrid(
                          frames: widget.frames,
                          mode: mode,
                          isDraggingOver: widget.isDraggingOver,
                          onReorder: widget.onReorder,
                        ),
                      ),
                      Container(
                        color: Palette.previewBackdrop,
                        padding: const EdgeInsets.all(24),
                        child: SheetPreview(
                          frames: widget.frames,
                          mode: mode,
                          meta: widget.meta,
                          service: widget.service,
                          tabs: _tabs,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final indeterminate = progress.phase == ProgressPhase.compose;
    final pct = progress.total > 0 ? progress.done / progress.total : 0.0;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Text(
            indeterminate
                ? phaseLabel[progress.phase]!
                : '${phaseLabel[progress.phase]!} ${progress.done}/${progress.total}',
            style: const TextStyle(
              fontSize: 11,
              color: Palette.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: indeterminate ? 1.0 : pct,
                minHeight: 4,
                backgroundColor: Palette.border,
                valueColor: const AlwaysStoppedAnimation(Color(0xB3FFFFFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.mode,
    required this.isDraggingOver,
    required this.onTap,
  });

  final FilmMode mode;
  final bool isDraggingOver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDraggingOver ? const Color(0x0DFFFFFF) : null,
              border: Border.all(
                color: isDraggingOver
                    ? const Color(0x66FFFFFF)
                    : Palette.controlBorder,
                width: 2,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.upload_outlined,
                    size: 40,
                    color: Palette.textFainter,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '写真をドラッグ&ドロップ、またはクリックして選択',
                    style: TextStyle(fontSize: 13, color: Palette.textFainter),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'JPEG / PNG - 最大${mode.capacity}枚 · ドラッグで並べ替え',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Palette.textFaintest,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag-to-reorder grid at the mode's column count.
class ReorderGrid extends StatelessWidget {
  const ReorderGrid({
    super.key,
    required this.frames,
    required this.mode,
    required this.isDraggingOver,
    required this.onReorder,
  });

  final List<Frame> frames;
  final FilmMode mode;
  final bool isDraggingOver;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDraggingOver ? 0.5 : 1.0,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: frames.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: mode.cols,
          childAspectRatio: mode.cellAspect,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemBuilder: (context, index) => _ReorderCell(
          key: ValueKey(frames[index].path),
          frame: frames[index],
          index: index,
          onReorder: onReorder,
        ),
      ),
    );
  }
}

class _ReorderCell extends StatelessWidget {
  const _ReorderCell({
    super.key,
    required this.frame,
    required this.index,
    required this.onReorder,
  });

  final Frame frame;
  final int index;
  final void Function(int from, int to) onReorder;

  Widget _content(BuildContext context, {bool ghost = false}) {
    final thumb = frame.thumb;
    return Opacity(
      opacity: ghost ? 0.4 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
            else
              const ColoredBox(color: Palette.thumbPlaceholder),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                color: const Color(0xE6FFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.6,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          feedback: SizedBox(
            width: 120,
            height: 120 / (context.size?.aspectRatio ?? 1.5),
            child: Opacity(opacity: 0.85, child: _content(context)),
          ),
          childWhenDragging: DecoratedBox(
            decoration: BoxDecoration(
              color: Palette.thumbEmpty,
              borderRadius: BorderRadius.circular(2),
            ),
            child: _content(context, ghost: true),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: highlighted
                  ? Border.all(color: const Color(0x99FFFFFF), width: 2)
                  : null,
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: _content(context),
            ),
          ),
        );
      },
    );
  }
}

/// The real composed sheet, debounced so typing in the roll name does not kick
/// off a render on every keystroke.
class SheetPreview extends StatefulWidget {
  const SheetPreview({
    super.key,
    required this.frames,
    required this.mode,
    required this.meta,
    required this.service,
    required this.tabs,
  });

  final List<Frame> frames;
  final FilmMode mode;
  final SheetMeta meta;
  final SheetService service;
  final TabController tabs;

  @override
  State<SheetPreview> createState() => _SheetPreviewState();
}

/// Everything a composed preview depends on.
///
/// Deliberately a record rather than an interpolated string: [SheetMeta] is a
/// value object with real `==`, so structural equality does the comparison and
/// a field added to it participates automatically. Stringifying the meta hid a
/// bug where the key never changed, because the default `toString` is a
/// constant.
typedef PreviewKey = ({String paths, FilmMode mode, SheetMeta meta});

PreviewKey previewKey(List<Frame> frames, FilmMode mode, SheetMeta meta) =>
    (paths: frames.map((f) => f.path).join('|'), mode: mode, meta: meta);

class _SheetPreviewState extends State<SheetPreview> {
  Timer? _debounce;
  Uint8List? _preview;
  PreviewKey? _previewKey;
  bool _loading = false;
  String? _error;

  PreviewKey get _key => previewKey(widget.frames, widget.mode, widget.meta);

  @override
  void initState() {
    super.initState();
    widget.tabs.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(SheetPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_schedule);
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    final active = widget.tabs.index == 1;
    if (!active || widget.frames.isEmpty || _loading || _previewKey == _key) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(previewDebounce, _run);
  }

  Future<void> _run() async {
    final key = _key;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.service.preview(
        widget.frames.map((f) => f.path).toList(),
        widget.mode,
        widget.meta,
      );
      if (!mounted) return;
      setState(() {
        _preview = bytes;
        _previewKey = key;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final preview = _preview;
    if (error != null) {
      return Center(
        child: Text(
          'プレビューの生成に失敗しました: $error',
          style: const TextStyle(fontSize: 13, color: Palette.error),
        ),
      );
    }
    if (preview != null) {
      return Center(
        child: Opacity(
          opacity: _loading ? 0.4 : 1.0,
          child: Image.memory(
            preview,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    return Center(
      child: Text(
        _loading ? 'プレビューを生成中...' : 'プレビューを準備中...',
        style: TextStyle(
          fontSize: 13,
          color: _loading ? Palette.textMuted : Palette.textFaint,
        ),
      ),
    );
  }
}
