import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_completion.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';

class SqlEditorDiagnostic {
  const SqlEditorDiagnostic(this.message, this.offset, [this.length = 1]);
  final String message;
  final int offset;
  final int length;
}

class SqlStaticAnalyzer {
  const SqlStaticAnalyzer._();

  static SqlEditorDiagnostic? analyze(String sql) {
    final parentheses = <int>[];
    var quote = '';
    var start = -1;
    var lineComment = false;
    var blockComment = false;
    for (var index = 0; index < sql.length; index++) {
      final char = sql[index];
      final next = index + 1 < sql.length ? sql[index + 1] : '';
      if (lineComment) {
        if (char == '\n') lineComment = false;
        continue;
      }
      if (blockComment) {
        if (char == '*' && next == '/') {
          blockComment = false;
          index++;
        }
        continue;
      }
      if (quote.isNotEmpty) {
        if (char == quote) {
          if (next == quote) {
            index++;
          } else {
            quote = '';
          }
        }
        continue;
      }
      if (char == '-' && next == '-') {
        lineComment = true;
        index++;
      } else if (char == '/' && next == '*') {
        blockComment = true;
        start = index;
        index++;
      } else if (char == "'" || char == '"') {
        quote = char;
        start = index;
      } else if (char == '(') {
        parentheses.add(index);
      } else if (char == ')') {
        if (parentheses.isEmpty) {
          return SqlEditorDiagnostic('Unexpected closing parenthesis', index);
        }
        parentheses.removeLast();
      }
    }
    if (quote.isNotEmpty) {
      return SqlEditorDiagnostic(
        'Unterminated SQL string or identifier',
        start,
        math.max(1, sql.length - start),
      );
    }
    if (blockComment) {
      return SqlEditorDiagnostic(
        'Unterminated block comment',
        start,
        math.max(1, sql.length - start),
      );
    }
    if (parentheses.isNotEmpty) {
      return SqlEditorDiagnostic(
        'Missing closing parenthesis',
        parentheses.last,
      );
    }
    return null;
  }

  static SqlEditorDiagnostic? fromRuntimeError(String? message, String sql) {
    if (message == null ||
        message == 'OK' ||
        !message.toLowerCase().contains('rolled back')) {
      return null;
    }
    final match = RegExp(
      r'(?:near|column|table|index|view|trigger)\s+["\x27]?([^"\x27:\s]+)',
      caseSensitive: false,
    ).firstMatch(message);
    final token = match?.group(1);
    if (token != null) {
      final offset = sql.toLowerCase().indexOf(token.toLowerCase());
      if (offset >= 0) {
        return SqlEditorDiagnostic(message, offset, token.length);
      }
    }
    return SqlEditorDiagnostic(message, math.max(0, sql.length - 1));
  }
}

class SqlHighlightingController extends TextEditingController {
  SqlHighlightingController({super.text});
  TextRange? diagnosticRange;

  static final RegExp _tokens = RegExp(
    r'(--[^\n]*|/\*[\s\S]*?\*/|\x27(?:\x27\x27|[^\x27])*\x27|"(?:\"\"|[^"])*"|\b\d+(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*\b)',
    multiLine: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final colors = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _tokens.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start),
            style: _diagnosticStyle(base, cursor, match.start),
          ),
        );
      }
      final token = match.group(0)!;
      var tokenStyle = base;
      if (token.startsWith('--') || token.startsWith('/*')) {
        tokenStyle = base.copyWith(
          color: colors.onSurface.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        );
      } else if (token.startsWith("'")) {
        tokenStyle = base.copyWith(color: colors.tertiary);
      } else if (RegExp(r'^\d').hasMatch(token)) {
        tokenStyle = base.copyWith(
          color: Color.lerp(colors.primary, colors.tertiary, 0.55),
        );
      } else if (_keywords.contains(token.toUpperCase())) {
        tokenStyle = base.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
        );
      }
      spans.add(
        TextSpan(
          text: token,
          style: _diagnosticStyle(tokenStyle, match.start, match.end),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
          style: _diagnosticStyle(base, cursor, text.length),
        ),
      );
    }
    return TextSpan(style: base, children: spans);
  }

  TextStyle _diagnosticStyle(TextStyle style, int start, int end) {
    final range = diagnosticRange;
    if (range == null || range.end <= start || range.start >= end) return style;
    return style.copyWith(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: Colors.redAccent,
      decorationThickness: 2,
    );
  }
}

const Set<String> _keywords = <String>{
  'SELECT',
  'DISTINCT',
  'FROM',
  'WHERE',
  'JOIN',
  'INNER',
  'LEFT',
  'CROSS',
  'ON',
  'GROUP',
  'BY',
  'HAVING',
  'ORDER',
  'ASC',
  'DESC',
  'LIMIT',
  'OFFSET',
  'INSERT',
  'INTO',
  'VALUES',
  'UPDATE',
  'SET',
  'DELETE',
  'REPLACE',
  'CREATE',
  'ALTER',
  'DROP',
  'TABLE',
  'INDEX',
  'VIEW',
  'TRIGGER',
  'VIRTUAL',
  'USING',
  'WITH',
  'RECURSIVE',
  'AS',
  'UNION',
  'ALL',
  'EXCEPT',
  'INTERSECT',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
  'AND',
  'OR',
  'NOT',
  'NULL',
  'IS',
  'IN',
  'BETWEEN',
  'LIKE',
  'PRIMARY',
  'KEY',
  'FOREIGN',
  'REFERENCES',
  'DEFAULT',
  'CHECK',
  'CONFLICT',
  'DO',
  'BEGIN',
  'COMMIT',
  'ROLLBACK',
  'SAVEPOINT',
  'RELEASE',
  'PRAGMA',
  'ATTACH',
  'DETACH',
  'VACUUM',
  'REINDEX',
  'ANALYZE',
  'EXPLAIN',
};

class SqlCodeEditor extends StatefulWidget {
  const SqlCodeEditor({
    super.key,
    required this.controller,
    required this.schemas,
    required this.onChanged,
    required this.onRun,
    required this.hintText,
    required this.localModelLabel,
    this.externalError,
  });

  final SqlHighlightingController controller;
  final List<TableSchema> schemas;
  final ValueChanged<String> onChanged;
  final VoidCallback? onRun;
  final String hintText;
  final String localModelLabel;
  final String? externalError;

  @override
  State<SqlCodeEditor> createState() => _SqlCodeEditorState();
}

class _SqlCodeEditorState extends State<SqlCodeEditor> {
  static const _engine = SqlCompletionEngine();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _verticalScroll = ScrollController();
  final Map<String, int> _accepted = <String, int>{};
  List<SqlCompletion> _suggestions = const <SqlCompletion>[];
  SqlEditorDiagnostic? _diagnostic;
  int _selected = 0;
  bool _explicitSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant SqlCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.externalError != widget.externalError ||
        oldWidget.schemas != widget.schemas) {
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    _explicitSuggestions = false;
    _refresh();
    widget.onChanged(widget.controller.text);
  }

  void _refresh() {
    final selection = widget.controller.selection;
    final cursor = selection.isValid ? selection.extentOffset : 0;
    _diagnostic =
        SqlStaticAnalyzer.analyze(widget.controller.text) ??
        SqlStaticAnalyzer.fromRuntimeError(
          widget.externalError,
          widget.controller.text,
        );
    widget.controller.diagnosticRange = _diagnostic == null
        ? null
        : TextRange(
            start: _diagnostic!.offset,
            end: math.min(
              widget.controller.text.length,
              _diagnostic!.offset + _diagnostic!.length,
            ),
          );
    _suggestions = _engine.suggest(
      sql: widget.controller.text,
      cursorOffset: cursor,
      schemas: widget.schemas,
      acceptedSelections: _accepted,
      explicitlyRequested: _explicitSuggestions,
    );
    if (_selected >= _suggestions.length) _selected = 0;
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onRun?.call();
      return KeyEventResult.handled;
    }
    if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.space) {
      _explicitSuggestions = true;
      _refresh();
      return KeyEventResult.handled;
    }
    if (_suggestions.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % _suggestions.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected =
            (_selected - 1 + _suggestions.length) % _suggestions.length,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _accept(_suggestions[_selected]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _suggestions = const <SqlCompletion>[]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _accept(SqlCompletion item) {
    final selection = widget.controller.selection;
    final cursor = selection.isValid
        ? selection.extentOffset
        : widget.controller.text.length;
    final range = _engine.tokenAt(widget.controller.text, cursor);
    final text = widget.controller.text.replaceRange(
      range.start,
      range.end,
      item.insertText,
    );
    _accepted.update(
      item.insertText.toLowerCase(),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: range.start + item.insertText.length,
      ),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.4,
    );
    final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
    final selection = widget.controller.selection;
    final cursor = (selection.isValid ? selection.extentOffset : 0).clamp(
      0,
      widget.controller.text.length,
    );
    final before = widget.controller.text.substring(0, cursor);
    final line = '\n'.allMatches(before).length + 1;
    final column = cursor - before.lastIndexOf('\n');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.34),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 38,
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _verticalScroll,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          0,
                          _verticalScroll.hasClients
                              ? -_verticalScroll.offset
                              : 0,
                        ),
                        child: child,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12, right: 7),
                        child: Text(
                          List<String>.generate(
                            lineCount,
                            (index) => '${index + 1}',
                          ).join('\n'),
                          textAlign: TextAlign.right,
                          style: codeStyle.copyWith(
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.62,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colors.outlineVariant,
                ),
                Expanded(
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      key: const ValueKey<String>('custom-sql-input'),
                      controller: widget.controller,
                      focusNode: _focusNode,
                      scrollController: _verticalScroll,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      style: codeStyle.copyWith(color: colors.onSurface),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.all(12),
                        hintText: widget.hintText,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty && _focusNode.hasFocus)
            Container(
              key: const ValueKey<String>('sql-completion-popup'),
              height: math.min(108, _suggestions.length * 36).toDouble(),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                itemExtent: 36,
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  return InkWell(
                    key: ValueKey<String>('sql-completion-${item.label}'),
                    onTap: () => _accept(item),
                    child: ColoredBox(
                      color: index == _selected
                          ? colors.primaryContainer
                          : Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: Row(
                          children: [
                            Icon(
                              _iconFor(item.kind),
                              size: 15,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: codeStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              item.detail,
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _diagnostic == null
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.5)
                  : colors.errorContainer.withValues(alpha: 0.72),
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(
                  _diagnostic == null
                      ? Icons.auto_awesome_rounded
                      : Icons.error_outline_rounded,
                  size: 13,
                  color: _diagnostic == null
                      ? colors.primary
                      : colors.onErrorContainer,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _diagnostic?.message ??
                        '${widget.localModelLabel} · Ctrl/⌘ Space · Tab',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: _diagnostic == null
                          ? colors.onSurfaceVariant
                          : colors.onErrorContainer,
                    ),
                  ),
                ),
                Text(
                  'Ln $line, Col $column',
                  style: TextStyle(
                    fontSize: 10,
                    color: _diagnostic == null
                        ? colors.onSurfaceVariant
                        : colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(SqlCompletionKind kind) => switch (kind) {
    SqlCompletionKind.keyword => Icons.key_rounded,
    SqlCompletionKind.snippet => Icons.data_object_rounded,
    SqlCompletionKind.table => Icons.table_chart_outlined,
    SqlCompletionKind.column => Icons.view_column_outlined,
  };
}
