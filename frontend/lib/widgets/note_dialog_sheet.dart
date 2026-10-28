import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

class NoteDialogSheet extends StatefulWidget {
  final String initialText;
  final bool isEditing;
  final String? title;
  final String? subtitle;
  final String? hintText;

  const NoteDialogSheet({
    super.key,
    required this.initialText,
    required this.isEditing,
    this.title,
    this.subtitle,
    this.hintText,
  });

  @override
  State<NoteDialogSheet> createState() => _NoteDialogSheetState();
}

class _NoteDialogSheetState extends State<NoteDialogSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final charCount = text.length;
    final wordCount =
        text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

    final dialogTitle = widget.title ??
        (widget.isEditing ? 'Edit Note' : 'New Note');
    final dialogSubtitle = widget.subtitle ??
        (widget.isEditing
            ? 'Update your captured thoughts'
            : 'First line will be used as note title');
    final dialogHint = widget.hintText ??
        'Start typing your note here...\n\nExample:\nWeekly Sync Action Items\n1. Finalize mobile UI\n2. Review test cases';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ResponsiveSheetContainer(
            maxWidth: Responsive.maxSheetWidth,
            backgroundColor: AppTheme.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            padding: EdgeInsets.fromLTRB(
              Responsive.value(context, mobile: 24.0, narrow: 14.0),
              16,
              Responsive.value(context, mobile: 24.0, narrow: 14.0),
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.isEditing
                            ? Icons.edit_note_rounded
                            : Icons.note_add_rounded,
                        color: AppTheme.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dialogTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dialogSubtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.dividerColor.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        minLines: 4,
                        maxLines: 8,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: dialogHint,
                          hintStyle: TextStyle(
                            color: AppTheme.textSecondary
                                .withValues(alpha: 0.5),
                            fontSize: 14,
                            height: 1.5,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '$wordCount ${wordCount == 1 ? 'word' : 'words'} · $charCount chars',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (_controller.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() {});
                              },
                              child: Text(
                                'Clear',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final trimmed = _controller.text.trim();
                      Navigator.pop(context, trimmed);
                    },
                    icon: Icon(
                      widget.isEditing
                          ? Icons.check_circle_rounded
                          : Icons.save_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: Text(
                      widget.isEditing ? 'Update Note' : 'Save Note',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
