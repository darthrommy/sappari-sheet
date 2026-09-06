/// Left control column: source picker, sheet settings, export.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/date_text.dart';
import '../core/geometry.dart';
import 'theme.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.imagesCount,
    required this.mode,
    required this.onModeChange,
    required this.rollNameController,
    required this.descriptionController,
    required this.authorController,
    required this.dateController,
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
  final TextEditingController rollNameController;
  final TextEditingController descriptionController;
  final TextEditingController authorController;
  final TextEditingController dateController;
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
                  'Sappari Sheet',
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
                  // Format leads: it sets the capacity every later step is
                  // measured against, and the sheet's whole shape follows from
                  // it. Pick the film, then the photos, then describe them.
                  const _SectionLabel('フィルム'),
                  const SizedBox(height: 12),
                  _ModeSelect(mode: mode, onChanged: onModeChange),
                  const SizedBox(height: 12),
                  Text(
                    '最大 ${mode.capacity} 枚',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Palette.border),
                  const SizedBox(height: 20),
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
                  const _FieldLabel('ロール名（シート表題に印字）'),
                  const SizedBox(height: 6),
                  _TextField(
                    controller: rollNameController,
                    hint: 'Kodak Gold 200 など',
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('説明（表題の下に印字）'),
                  const SizedBox(height: 6),
                  _TextField(controller: descriptionController, hint: 'ひとことメモ'),
                  const SizedBox(height: 16),
                  const _FieldLabel('撮影者'),
                  const SizedBox(height: 6),
                  _TextField(controller: authorController, hint: 'あなたの名前'),
                  const SizedBox(height: 16),
                  const _FieldLabel('日付'),
                  const SizedBox(height: 6),
                  _DateField(controller: dateController),
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

/// Film mode picker.
///
/// Uses [DropdownMenu] rather than `DropdownButtonFormField` because only the
/// former exposes `menuStyle`: the popup needs the same fill, 1px border and
/// 6px radius as the trigger, and `DropdownButton`'s menu offers no control
/// over its border or elevation, so it always reads as a different object.
///
/// `requestFocusOnTap: false` keeps it a picker rather than a combo box — no
/// caret, no typing.
class _ModeSelect extends StatelessWidget {
  const _ModeSelect({required this.mode, required this.onChanged});

  final FilmMode mode;
  final ValueChanged<FilmMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<FilmMode>(
      initialSelection: mode,
      requestFocusOnTap: false,
      expandedInsets: EdgeInsets.zero,
      textStyle: const TextStyle(fontSize: 13, color: Palette.textPrimary),
      inputDecorationTheme: _fieldDecorationTheme(),
      trailingIcon: const Icon(
        Icons.keyboard_arrow_down,
        size: 18,
        color: Palette.textMuted,
      ),
      selectedTrailingIcon: const Icon(
        Icons.keyboard_arrow_up,
        size: 18,
        color: Palette.textMuted,
      ),
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Palette.control),
        // Material 3 tints elevated surfaces toward the seed colour; the shell
        // is a fixed neutral palette, so suppress it.
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
            side: const BorderSide(color: Palette.controlBorder),
          ),
        ),
      ),
      dropdownMenuEntries: [
        for (final m in FilmMode.values)
          DropdownMenuEntry<FilmMode>(
            value: m,
            label: '${m.label}（最大${m.capacity}枚）',
            style: ButtonStyle(
              foregroundColor: const WidgetStatePropertyAll(
                Palette.textPrimary,
              ),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 13, color: Palette.textPrimary),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused) ||
                        states.contains(WidgetState.pressed)
                    ? Palette.controlHover
                    : Colors.transparent,
              ),
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(34)),
            ),
          ),
      ],
      onSelected: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.suffix,
    this.inputFormatters,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    maxLines: 1,
    inputFormatters: inputFormatters,
    keyboardType: keyboardType,
    style: const TextStyle(fontSize: 12, color: Palette.textPrimary),
    cursorColor: Palette.textPrimary,
    decoration: _inputDecoration().copyWith(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: Palette.textFaint),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 28),
    ),
  );
}

/// Coerces every edit toward `YYYY-MM-DD`.
///
/// The caret always lands at the end. That is fine for a ten-character field
/// filled left to right, and avoids the caret arithmetic a mid-string edit
/// would otherwise need.
class _DateInputFormatter extends TextInputFormatter {
  const _DateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = maskDate(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// The 日付 field: masked typing plus a calendar button.
///
/// The mask guarantees the *shape*; it cannot rule out `2026-02-30`, so an
/// unparseable value reverts to the last valid one when the field loses focus.
/// The sheet therefore never prints a date that does not exist.
class _DateField extends StatefulWidget {
  const _DateField({required this.controller});

  final TextEditingController controller;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);
  late String _lastValid = parseIsoDate(widget.controller.text) != null
      ? widget.controller.text
      : formatIsoDate(DateTime.now());

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    final text = widget.controller.text;
    if (parseIsoDate(text) != null) {
      _lastValid = text;
    } else if (text != _lastValid) {
      widget.controller.text = _lastValid;
    }
  }

  Future<void> _pick() async {
    final current = parseIsoDate(widget.controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    _lastValid = formatIsoDate(picked);
    widget.controller.text = _lastValid;
  }

  @override
  Widget build(BuildContext context) => _TextField(
    controller: widget.controller,
    focusNode: _focus,
    hint: '2026-01-01',
    keyboardType: TextInputType.number,
    inputFormatters: const [_DateInputFormatter()],
    suffix: IconButton(
      onPressed: () => unawaited(_pick()),
      icon: const Icon(
        Icons.calendar_today_outlined,
        size: 14,
        color: Palette.textMuted,
      ),
      splashRadius: 14,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: 'カレンダーから選択',
    ),
  );
}

/// Corner radius shared by every field and by the dropdown's popup, so the
/// menu reads as the same object as the control that opened it.
const double fieldRadius = 6;

const EdgeInsets _fieldPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 8,
);

OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(fieldRadius),
  borderSide: BorderSide(color: color),
);

InputDecoration _inputDecoration() => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: Palette.control,
  contentPadding: _fieldPadding,
  border: _fieldBorder(Palette.controlBorder),
  enabledBorder: _fieldBorder(Palette.controlBorder),
  focusedBorder: _fieldBorder(Palette.focusBorder),
);

/// The same decoration as [_inputDecoration], in the theme form [DropdownMenu]
/// takes for its trigger.
InputDecorationTheme _fieldDecorationTheme() => InputDecorationTheme(
  isDense: true,
  filled: true,
  fillColor: Palette.control,
  contentPadding: _fieldPadding,
  border: _fieldBorder(Palette.controlBorder),
  enabledBorder: _fieldBorder(Palette.controlBorder),
  focusedBorder: _fieldBorder(Palette.focusBorder),
);
