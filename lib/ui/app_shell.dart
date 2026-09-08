/// Two-pane shell: sidebar plus preview, owning all app state. Spec §7.
library;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/geometry.dart';
import '../core/sheet_meta.dart';
import '../services/settings_store.dart';
import '../services/sheet_service.dart';
import 'preview_pane.dart';
import 'sidebar.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.initialSettings,
  });

  final SettingsStore store;

  /// What the last run left behind, or null when the user has not opted in —
  /// loaded before the first frame so the fields never populate late.
  final AppSettings? initialSettings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final SheetService _service = SheetService();
  final TextEditingController _rollName = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _author = TextEditingController();
  final TextEditingController _date = TextEditingController(
    text: SheetMeta.today(),
  );
  final TextEditingController _fileName = TextEditingController();

  /// What the sheet's title block prints, read straight off the fields.
  SheetMeta get _meta => SheetMeta(
    name: _rollName.text,
    description: _description.text,
    author: _author.text,
    date: _date.text,
  );

  StreamSubscription<Progress>? _progressSub;

  /// The author field has a listener firing on every keystroke, so writes are
  /// coalesced rather than hitting the disk per character.
  Timer? _saveTimer;
  static const Duration _saveDebounce = Duration(milliseconds: 500);

  late bool _remember;
  late FilmMode _mode;
  List<Frame> _frames = const [];
  bool _isAnalyzing = false;
  bool _isGenerating = false;
  bool _isDraggingOver = false;
  Progress? _progress;

  @override
  void initState() {
    super.initState();
    // A missing file means the box was never checked; its defaults are the
    // same values the fields would have started with anyway.
    final restored = widget.initialSettings ?? AppSettings.defaults;
    _remember = widget.initialSettings != null;
    _author.text = restored.author;
    _fileName.text = restored.fileName;
    _mode = restored.mode;

    _progressSub = _service.progress.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p.phase == ProgressPhase.done ? null : p);
    });
    _rollName.addListener(() => setState(() {}));
    _description.addListener(() => setState(() {}));
    _author.addListener(() {
      setState(() {});
      _scheduleSave();
    });
    _date.addListener(() => setState(() {}));
    // Not part of the sheet, so it needs no rebuild — only a save.
    _fileName.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _progressSub?.cancel();
    _service.dispose();
    _rollName.dispose();
    _description.dispose();
    _author.dispose();
    _date.dispose();
    _fileName.dispose();
    super.dispose();
  }

  AppSettings get _settings => AppSettings(
    author: _author.text,
    fileName: _fileName.text,
    mode: _mode,
  );

  void _scheduleSave() {
    if (!_remember) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(_saveNow()));
  }

  /// Writes now, cancelling anything already queued. A failure here costs a
  /// remembered value and nothing else, so it stays quiet rather than
  /// interrupting an export with a toast.
  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await widget.store.save(_settings);
    } on Object {
      // Ignored deliberately: convenience, not data.
    }
  }

  Future<void> _setRemember(bool value) async {
    setState(() => _remember = value);
    if (value) {
      await _saveNow();
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      // Unchecking leaves nothing on disk — the absent file is what tells the
      // next run not to restore anything.
      await widget.store.clear();
    } on Object {
      // Ignored deliberately.
    }
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
    _scheduleSave();
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

    // Flush before the long operation: an export is the point at which the
    // current values have clearly proven themselves worth keeping.
    if (_remember) await _saveNow();

    setState(() => _isGenerating = true);
    try {
      await _service.render(
        _frames.map((f) => f.path).toList(),
        outDir,
        _fileName.text,
        _mode,
        _meta,
      );
      _toast('書き出しが完了しました');
      setState(() => _frames = const []);
      // Roll name and description are per-roll; photographer and date carry over.
      _rollName.clear();
      _description.clear();
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
              rollNameController: _rollName,
              descriptionController: _description,
              authorController: _author,
              dateController: _date,
              fileNameController: _fileName,
              remember: _remember,
              onRememberChanged: (v) => unawaited(_setRemember(v)),
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
                meta: _meta,
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
