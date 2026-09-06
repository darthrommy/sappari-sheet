/// Two-pane shell: sidebar plus preview, owning all app state. Spec §7.
library;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/geometry.dart';
import '../services/sheet_service.dart';
import 'preview_pane.dart';
import 'sidebar.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final SheetService _service = SheetService();
  final TextEditingController _memo = TextEditingController();
  final TextEditingController _fileName = TextEditingController(
    text: 'index_sheet',
  );

  StreamSubscription<Progress>? _progressSub;

  FilmMode _mode = FilmMode.full35;
  List<Frame> _frames = const [];
  bool _isAnalyzing = false;
  bool _isGenerating = false;
  bool _isDraggingOver = false;
  Progress? _progress;

  @override
  void initState() {
    super.initState();
    _progressSub = _service.progress.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p.phase == ProgressPhase.done ? null : p);
    });
    _memo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _service.dispose();
    _memo.dispose();
    _fileName.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFF3A1F1F) : Palette.control,
          behavior: SnackBarBehavior.floating,
          width: 420,
        ),
      );
  }

  Future<void> _analyze(
    List<String> paths,
    FilmMode mode, {
    required bool sort,
  }) async {
    setState(() => _isAnalyzing = true);
    try {
      final result = await _service.analyze(paths, mode, sort: sort);
      if (!mounted) return;
      setState(() => _frames = result.frames);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _pickFiles() async {
    const group = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png'],
    );
    final files = await openFiles(acceptedTypeGroups: const [group]);
    if (files.isEmpty) return;
    await _analyze(files.map((f) => f.path).toList(), _mode, sort: true);
  }

  Future<void> _handleDropped(List<String> paths) =>
      _analyze(paths, _mode, sort: true);

  Future<void> _changeMode(FilmMode next) async {
    setState(() => _mode = next);
    if (_frames.isEmpty) return;
    // Re-thumbnail for the new cell size, preserving the user's arrangement.
    await _analyze(_frames.map((f) => f.path).toList(), next, sort: false);
  }

  void _reorder(int from, int to) {
    if (from == to) return;
    setState(() {
      final next = [..._frames];
      final moved = next.removeAt(from);
      next.insert(to, moved);
      _frames = next;
    });
  }

  Future<void> _export() async {
    if (_frames.isEmpty) {
      _toast('書き出す画像がありません', error: true);
      return;
    }
    final outDir = await getDirectoryPath(confirmButtonText: '保存先フォルダを選択');
    if (outDir == null) return;

    setState(() => _isGenerating = true);
    try {
      await _service.render(
        _frames.map((f) => f.path).toList(),
        outDir,
        _fileName.text,
        _mode,
        _memo.text,
      );
      _toast('書き出しが完了しました');
      setState(() => _frames = const []);
      _memo.clear();
    } on Object catch (err) {
      _toast('書き出しに失敗しました: $err', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.shell,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingOver = true),
        onDragExited: (_) => setState(() => _isDraggingOver = false),
        onDragDone: (details) {
          setState(() => _isDraggingOver = false);
          unawaited(_handleDropped(details.files.map((f) => f.path).toList()));
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSidebar(
              imagesCount: _frames.length,
              mode: _mode,
              onModeChange: (m) => unawaited(_changeMode(m)),
              memoController: _memo,
              fileNameController: _fileName,
              onPickFiles: () => unawaited(_pickFiles()),
              onExport: () => unawaited(_export()),
              canExport: !_isGenerating && !_isAnalyzing && _frames.isNotEmpty,
              isGenerating: _isGenerating,
              isAnalyzing: _isAnalyzing,
            ),
            Expanded(
              child: PreviewPane(
                frames: _frames,
                mode: _mode,
                memo: _memo.text,
                isDraggingOver: _isDraggingOver,
                onPickFiles: () => unawaited(_pickFiles()),
                onReorder: _reorder,
                progress: _progress,
                service: _service,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
