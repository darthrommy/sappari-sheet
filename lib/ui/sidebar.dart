/// Left control column: source picker, sheet settings, export. Spec §7.
///
/// Japanese strings are copied verbatim from the Tauri original.
library;

import 'package:flutter/material.dart';

import '../core/geometry.dart';
import 'theme.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.imagesCount,
    required this.mode,
    required this.onModeChange,
    required this.memoController,
    required this.fileNameController,
    required this.onPickFiles,
    required this.onExport,
    required this.canExport,
    required this.isGenerating,
    required this.isAnalyzing,
  });

  final int imagesCount;
  final FilmMode mode;
  final ValueChanged<FilmMode> onModeChange;
  final TextEditingController memoController;
  final TextEditingController fileNameController;
  final VoidCallback onPickFiles;
  final VoidCallback onExport;
  final bool canExport;
  final bool isGenerating;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: Palette.sidebar,
        border: Border(right: BorderSide(color: Palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Opacity(
                  opacity: 0.8,
                  child: Icon(
                    Icons.movie_outlined,
                    size: 20,
                    color: Palette.textPrimary,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'negadice',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Palette.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('ソースファイル'),
                  const SizedBox(height: 12),
                  _OutlineButton(
                    icon: Icons.upload_outlined,
                    label: isAnalyzing ? '読み込み中...' : '写真を選択',
                    onPressed: isAnalyzing ? null : onPickFiles,
                  ),
                  if (imagesCount > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '$imagesCount / ${mode.capacity} frames',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Palette.border),
                  const SizedBox(height: 20),
                  const _SectionLabel('シート設定'),
                  const SizedBox(height: 16),
                  const _FieldLabel('フィルム'),
                  const SizedBox(height: 6),
                  _ModeSelect(mode: mode, onChanged: onModeChange),
                  const SizedBox(height: 16),
                  const _FieldLabel('メモ（シート上部に印字）'),
                  const SizedBox(height: 6),
                  _TextField(
                    controller: memoController,
                    hint: 'ロール名・日付・現像所など',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('ファイル名'),
                  const SizedBox(height: 6),
                  _TextField(
                    controller: fileNameController,
                    hint: 'index_sheet',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '拡張子 .jpg は自動で追加されます',
                    style: TextStyle(fontSize: 11, color: Palette.textFaint),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: FilledButton.icon(
              onPressed: canExport ? onExport : null,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text(isGenerating ? '生成中...' : '書き出す'),
              style: FilledButton.styleFrom(
                backgroundColor: Palette.textPrimary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Palette.controlBorder,
                disabledForegroundColor: Palette.textFaint,
                minimumSize: const Size.fromHeight(38),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      color: Palette.textMuted,
      letterSpacing: 1.6,
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 12, color: Palette.textSecondary),
  );
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      backgroundColor: Palette.control,
      foregroundColor: Palette.textPrimary,
      disabledForegroundColor: Palette.textFaint,
      side: const BorderSide(color: Palette.controlBorder),
      minimumSize: const Size.fromHeight(38),
      textStyle: const TextStyle(fontSize: 13),
    ),
  );
}

class _ModeSelect extends StatelessWidget {
  const _ModeSelect({required this.mode, required this.onChanged});

  final FilmMode mode;
  final ValueChanged<FilmMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<FilmMode>(
      initialValue: mode,
      dropdownColor: Palette.control,
      isDense: true,
      style: const TextStyle(fontSize: 13, color: Palette.textPrimary),
      decoration: _inputDecoration(),
      items: [
        for (final m in FilmMode.values)
          DropdownMenuItem(
            value: m,
            child: Text('${m.label}（最大${m.capacity}枚）'),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLines: maxLines,
    style: const TextStyle(fontSize: 12, color: Palette.textPrimary),
    cursorColor: Palette.textPrimary,
    decoration: _inputDecoration().copyWith(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: Palette.textFaint),
    ),
  );
}

InputDecoration _inputDecoration() => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: Palette.control,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: Palette.controlBorder),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: Palette.controlBorder),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: Palette.focusBorder),
  ),
);
