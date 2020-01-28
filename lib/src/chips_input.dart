import 'dart:async';
import 'dart:math';

import 'package:after_layout/after_layout.dart';
import 'package:collection_diff/list_diff_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:flutter_chips_input_sunny/src/chips_input_controller.dart';
import 'package:logging/logging.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:sunny_dart/sunny_dart.dart';

/// Generates a list of suggestions given a query
typedef GenerateSuggestions<T> = FutureOr<ChipSuggestions<T>> Function(String query);

/// Builds a widget for a chip.  Used for autocomplete and chips
typedef BuildChipsWidget<T> = Widget Function(
    BuildContext context, ChipsInputController<T> controller, int index, T data);

/// An action that's executed when the user clicks the keyboard action
typedef PerformTextInputAction<T> = void Function(TextInputAction type);

/// Tokenizes a chip to help provide inline completion
typedef ChipTokenizer<T> = Iterable<String> Function(T input);

typedef ChipIdentifier<T> = String Function(T input);

/// Generic action performed on a chip
typedef ChipAction<T> = void Function(T chip);

/// Simple callback for query changing.
typedef QueryChanged<T> = void Function(String query, ChipsInputController<T> controller);

/// Simple callback for query changing.
typedef ChipsChanged<T> = void Function(ChipsInputController<T> controller);

/// Simple callback for query changing.
typedef OnLostFocus<T> = void Function(ChipsInputController<T> controller);

// ignore: must_be_immutable
class ChipsInput<T> extends StatefulWidget {
  ChipsInput({
    Key key,

    /// The chips that should start in the input.  If a controller is also provided, this will perform a sync once the
    /// component loads for the first time
    Iterable<T> initialValue,

    /// Decoration for the input itself
    this.decoration = const InputDecoration(),
    this.enabled = true,

    /// Builds each individual chip
    @required this.chipBuilder,

    /// Builds an individual suggestion tile.
    this.suggestionBuilder,

    /// A callback for locating suggestions based on the state of the input
    this.findSuggestions,

    /// Placeholder text to display.
    this.placeholder,
    this.elevation,

    /// Tokenizes each chip so we can perform full-text lookups
    this.chipTokenizer,

    /// Called when a chip is tapped
    this.onChipTapped,

    /// Callback for when the query text changes
    this.onQueryChanged,

    /// When the input loses focus
    this.onLostFocus,

    /// When the list of chips changes
    this.onChipsChanged,

    /// The max number of chips to allow
    this.maxChips,

    /// Configuration for the text input itself.
    this.inputConfiguration,

    /// Whether to autofocus the input
    this.autofocus,

    /// Used for focusing the input itself
    this.focusNode,

    /// Optional - starting query
    this.query,
    this.onInputAction,

    /// Whether to hide/ignore the suggestions overlay
    this.hideSuggestionsOverlay,

    /// When an inline suggestion is present and tapped.
    this.onSuggestionTap,

    /// A controller used to manually adjust chips, suggestions, etc
    this.controller,

    /// Calculates an identifier for each chip.
    this.chipId,
  })  : initialValue = initialValue?.where((s) => s != null)?.toList(),
        assert(maxChips == null || initialValue.length <= maxChips),
        assert(controller == null || findSuggestions == null),
        super(key: key);

  /// Generates tokens for a chip.  If this is provided, then inline suggestions will show up.
  final ChipTokenizer<T> chipTokenizer;

  /// Allows external control of the data within this input
  final ChipsInputController<T> controller;
  final ChipIdentifier<T> chipId;
  final InputDecoration decoration;
  final bool enabled;
  final String placeholder;
  final QueryChanged<T> onQueryChanged;
  final OnLostFocus<T> onLostFocus;
  final ChipsChanged<T> onChipsChanged;

  final String query;

  /// Callback to generate suggestions.  This is only used when _not_ providing a [controller]
  final GenerateSuggestions<T> findSuggestions;

  final ValueChanged<T> onChipTapped;
  final BuildChipsWidget<T> chipBuilder;
  final BuildChipsWidget<T> suggestionBuilder;
  final List<T> initialValue;
  final int maxChips;
  final double elevation;
  final bool autofocus;
  final FocusNode focusNode;
  final TextInputConfiguration inputConfiguration;
  final PerformTextInputAction<T> onInputAction;
  final ChipAction<T> onSuggestionTap;
  final bool hideSuggestionsOverlay;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>();
}

class ChipsInputState<T> extends State<ChipsInput<T>>
    with TickerProviderStateMixin, AfterLayoutMixin<ChipsInput<T>>
    implements TextInputClient {
  final Logger log = Logger("chipsInputState");
  ChipsInputController<T> _controller;
  FocusNode _focusNode;
  TextInputConnection _connection;
  LayerLink _layerLink = LayerLink();

  /// Things that need to be cleaned up when we're done
  List<VoidCallback> _disposers = [];

  bool get hasInputConnection => _connection != null && _connection.attached;
  GestureRecognizer _onSuggestionTap;

  Size size;

  String _lastDirectState;

  String _query = "";

  /// A local copy of the chips that gets updated as diffs come in
  List<T> _chips;
  Map<int, List<T>> _deleting;
  Map<int, List<T>> _adding;

  @override
  void initState() {
    super.initState();
    _chips = [];
    _deleting = {};
    _adding = {};
    _query = widget.query ?? "";
    _controller = widget.controller ??
        ChipsInputController<T>(
          findSuggestions: widget.findSuggestions,
          chips: widget.initialValue,
          hideSuggestionOverlay: widget.hideSuggestionsOverlay,
        );
    if (widget.controller != null) {
      if (widget.initialValue != null) {
        widget.controller.chips.sync(widget.initialValue);
      }
    }
    _controller.enabled = widget.enabled;

    _disposers.add(_controller.chips.changeStream
        .flatten()
        .asyncMap((changes) {
          // Handle these
          setState(() {
            changes.whereType<InsertDiff<T>>().forEach((insert) {
              /// Add these to _chips
              _adding.putIfAbsent(insert.index, () => []).addAll(insert.items);
            });
            changes.whereType<ReplaceDiff<T>>().forEach((replace) {
              for (int i = 0; i < replace.size; i++) {
                final curr = _chips.tryGet(replace.index + i);
                if (curr != null) {
                  _deleting.putIfAbsent(replace.index + i, () => []).add(curr);
                  _chips[replace.index] = replace.items[i];
                }
              }
            });
            changes.whereType<DeleteDiff<T>>().forEach((delete) {
              /// Add these to _chips

              for (int i = 0; i < delete.size; i++) {
                final curr = _chips.tryGet(delete.index);
                if (curr != null) {
                  _deleting.putIfAbsent(delete.index + i, () => []).add(curr);
                  _chips.removeAt(delete.index);
                }
              }
            });
          });
        })
        .listen((_) {}, cancelOnError: false)
        .cancel);

    _controller.hideSuggestionOverlay ??= widget.hideSuggestionsOverlay;
    _controller.requestKeyboardCallback = () => _openInputConnection();
    _controller.hideKeyboardCallback = () => _closeInputConnectionIfNeeded();
    _controller.placeholder = widget.placeholder;
    widget.query?.let((String _) => _controller.setQuery(_));

    /// We debounce the query stream that comes back from the controller to iron out any weird competition
    _disposers.add(_controller.queryStream.flatten().debounce(200.ms).listen((query) {
      if (_connection?.attached == true) {
        _lastDirectState = _chipReplacementText + query;
        _connection?.setEditingState(textEditingValue(_lastDirectState));
      }
      widget.onQueryChanged?.call(query, _controller);
    }, cancelOnError: false).cancel);

    _disposers.add(_controller.chips.changeStream.flatten().debounce(100.ms).listen((chips) {
      if (_connection?.attached == true) {
        _lastDirectState = _chipReplacementText + _controller.query;
        _connection?.setEditingState(textEditingValue(_lastDirectState));
      }
      widget.onChipsChanged?.call(_controller);
    }, cancelOnError: false).cancel);

    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);

    if (widget.onSuggestionTap != null) {
      _onSuggestionTap = TapGestureRecognizer()
        ..onTap = () {
          widget.onSuggestionTap(_controller.suggestion.item);
        };
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _disposers.forEach((disp) => disp());
    _closeInputConnectionIfNeeded();
    if (widget.controller == null) {
      _controller.dispose().then((_) {});
    }
    super.dispose();
  }

  int _countReplacements(String value) {
    return value.codeUnits.where((ch) => ch == kObjectReplacementChar).length;
  }

  String get _chipReplacementText => _chipReplacementTextFor(_chips);

  String _chipReplacementTextFor(Iterable<T> chips) =>
      String.fromCharCodes(chips.expand((_) => [kObjectReplacementChar]));

  TextEditingValue get _textValue => textEditingValue(_chipReplacementText + _query);

  /// Implemented from [TextInputClient]
  @override
  void performAction(TextInputAction action) {
    if (widget.onInputAction != null) {
      widget.onInputAction.call(action);
    } else {
      _focusNode.unfocus();
    }
  }

  /// Implemented from [TextInputClient]
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  /// Implemented from [TextInputClient].  This should never be called directly; instead, use the [_controller] to
  /// set the editing value
  @override
  void updateEditingValue(TextEditingValue value) {
    bool isUserInput = _lastDirectState == value.text;
    _lastDirectState = null;
    String newText = value.text;
    final oldCount = _chips.length;
    final newCount = _countReplacements(newText);
    if (isUserInput && newCount < oldCount) {
      _controller.updateChips(_chips.take(newCount));
    }
    final inputValue = String.fromCharCodes(newText.codeUnits.where((c) => c != kObjectReplacementChar));
    setState(() {
      _query = inputValue ?? "";
    });
    if (mounted) {
      _controller.setQuery(inputValue);
    }
  }

  void _openInputConnection() {
    try {
      if (!hasInputConnection) {
        _connection?.close();
        _connection = TextInput.attach(this, widget.inputConfiguration ?? TextInputConfiguration());
        _controller.connection = _connection;
        _connection.setEditingState(_textValue);
      }
      _connection.show();
    } catch (e) {
      print(e);
    }
  }

  void _closeInputConnectionIfNeeded() {
    try {
      if (hasInputConnection) {
        _connection.close();
        _connection = null;
        _controller.connection = null;
      }
    } catch (e) {
      print(e);
    }
  }

  requestKeyboard(BuildContext context) {
    FocusScope.of(context).requestFocus(_focusNode);
  }

  bool get _canFocus => widget.maxChips == null || _chips.length < widget.maxChips;

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _canFocus) {
      _openInputConnection();
      _controller.open();
    } else {
      _closeInputConnectionIfNeeded();
      _controller.close();
      widget.onLostFocus?.call(_controller);
    }
    setState(() {
      /*rebuild so that _TextCursor is hidden.*/
    });
  }

  @override
  void afterFirstLayout(BuildContext context) {
    final inputCtx = context;
    _controller.initialize(context, OverlayEntry(
      builder: (context) {
        return StreamBuilder(
          stream: _controller.suggestionStream.flatten(),
          builder: (BuildContext context, AsyncSnapshot<ChipSuggestions<T>> snapshot) {
            final RenderBox box = inputCtx.findRenderObject() as RenderBox;
            size = box.size;
            if (snapshot.data?.suggestions?.isNotEmpty == true) {
              final _suggestions = snapshot.data.suggestions;
              return Positioned(
                width: size.width,
                child: CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                    elevation: widget.elevation ?? 2.0,
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: snapshot.data?.suggestions?.length ?? 0,
                      itemBuilder: (BuildContext context, int index) {
                        return widget.suggestionBuilder(
                          context,
                          _controller,
                          index,
                          _suggestions[index],
                        );
                      },
                    ),
                  ),
                ),
              );
            } else {
              return Container();
            }
          },
        );
      },
    ));

    if (_controller.enabled && widget.autofocus == true) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  QueryText get _queryText {
    final suggestionToken = _controller.suggestionToken;
    final q = _query;
    if (suggestionToken?.toLowerCase()?.startsWith(_query?.toLowerCase()) == true) {
      return QueryText(q, suggestionToken);
    } else {
      return QueryText(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxIndex = max(_chips.length - 1, max(this._deleting.keys.max(0), this._adding.keys.max(0)));
    var chipsChildren = rangeOf(0, maxIndex)
        .map((index) {
          final data = _chips.tryGet(index);
          return [
            for (final deleting in this._deleting[index].orEmpty())
              ChipsInputItemWidget(
                key: Key("chip-input-${widget.chipId?.call(deleting) ?? "$deleting"}"),
                item: deleting,
                child: widget.chipBuilder(context, _controller, index, deleting),
                status: ChipsInputItemStatus.remove,
                vsync: this,
              ),
            if (data != null)
              ChipsInputItemWidget(
                key: Key("chip-input-${widget.chipId?.call(data) ?? "$data"}"),
                item: data,
                child: widget.chipBuilder(context, _controller, index, data),
                status: ChipsInputItemStatus.ready,
                vsync: this,
              ),
            for (final adding in this._adding[index].orEmpty())
              ChipsInputItemWidget(
                key: Key("chip-input-${widget.chipId?.call(adding) ?? "$adding"}"),
                item: adding,
                child: widget.chipBuilder(context, _controller, index, adding),
                status: ChipsInputItemStatus.add,
                vsync: this,
              ),
          ];
        })
        .flatten()
        .whereNotNull()
        .cast<Widget>()
        .toList();

    // Trigger a migration for any in-transition widgets.  For sure a better way exists to do this;
    if (this._adding.isNotEmpty) {
      Future.delayed(30.ms, () {
        /// On next frame
        this._adding.forEach((idx, items) {
          _chips.insertAll(idx, items);
        });
        this._adding.clear();

        if (mounted) {
          setState(() {});
        }
      });
    }

    if (this._deleting.isNotEmpty) {
      Future.delayed(300.ms, () {
        this._deleting.clear();

        /// On next frame
        if (mounted) {
          setState(() {});
        }
      });
    }
    final theme = Theme.of(context);
    final baseStyle = _defaultTextStyle(widget, theme);

    final queryText = _queryText;
    chipsChildren.add(
      Container(
        height: 28.0,
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(_query ?? "", style: baseStyle.copyWith(color: Colors.transparent)),
                _TextCaret(resumed: _focusNode.hasFocus),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  label: "Action Suggestion",
                  child: Semantics(
                    child: RichText(text: queryText.textSpan(baseStyle, _onSuggestionTap)),
                    label: "${queryText.suggestion}",
                  ),
                ),
              ],
            ),
            if (_controller.enabled &&
                _query.trim().isEmpty &&
                _controller.suggestion.isEmpty &&
                _controller.placeholder.isNotNullOrBlank)
              ChipsInputPlaceholder(baseStyle: baseStyle, placeholder: _controller.placeholder),
          ],
        ),
      ),
    );

    bool _deleting = false;
    bool _accepting = false;
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _controller.enabled ? () => requestKeyboard(context) : null,
        onHorizontalDragEnd: _controller.disabled
            ? null
            : (details) {
                if (_deleting) {
                  _deleting = false;
                  // other way??
                  if (_query.isNotEmpty == true) {
                    _controller.setQuery("");
                  } else if (_controller.size > 0) {
                    _controller.pop();
                  } else {
                    // Close the whole thing?
                    Navigator.pop(context);
                  }
                } else if (_accepting) {
                  // We are trying to select something
                  if (_controller.suggestion.isNotEmpty) {
                    _controller.acceptSuggestion();
                  }
                }
              },
        onHorizontalDragUpdate: _controller.disabled
            ? null
            : (DragUpdateDetails details) {
                if (details.delta.dx > 0) {
                  _deleting = false;
                  _accepting = true;
                } else if (details.delta.dx < 0) {
                  _deleting = true;
                  _accepting = false;
                }
              },
        child: Semantics(
          label: "Action Accept Drag Target",
          child: InputDecorator(
            isHovering: true,
            decoration: widget.decoration,
            isFocused: _focusNode.hasFocus,
            isEmpty: _query?.isNotEmpty != true && _chips.isEmpty,
            textAlignVertical: TextAlignVertical.center,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
//              alignment: WrapAlignment.start,
//              runAlignment: WrapAlignment.center,
              children: chipsChildren,
              spacing: 4.0,
              runSpacing: 4.0,
            ),
          ),
        ),
      ),
    );
  }

  Iterable<ChipsInputItemWidget> _buildChips() {
    final maxIndex = max(_chips.length - 1, max(this._deleting.keys.max(0), this._adding.keys.max(0)));

    return rangeOf(0, maxIndex)
        .map((index) {
          final data = _chips.tryGet(index);
          return [
            for (final deleting in this._deleting[index].orEmpty())
              ChipsInputItemWidget(
                key: Key("chip-input-${widget.chipId?.call(deleting) ?? "$deleting"}"),
                item: deleting,
                child: widget.chipBuilder(context, _controller, index, deleting),
                status: ChipsInputItemStatus.remove,
                vsync: this,
              ),
            if (data != null)
              ChipsInputItemWidget(
                key: Key("chip-input-${widget.chipId?.call(data) ?? "$data"}"),
                item: data,
                child: widget.chipBuilder(context, _controller, index, data),
                status: ChipsInputItemStatus.ready,
                vsync: this,
              ),
            for (final adding in this._adding[index].orEmpty())
              ChipsInputItemWidget(
                key: Key("chip-input-${widget.chipId?.call(adding) ?? "$adding"}"),
                item: adding,
                child: widget.chipBuilder(context, _controller, index, adding),
                status: ChipsInputItemStatus.add,
                vsync: this,
              ),
          ];
        })
        .flatten()
        .whereNotNull();
  }

  @override
  void connectionClosed() {}

  @override
  TextEditingValue get currentTextEditingValue => _textValue;
}

class ChipsInputRow<T> extends StatelessWidget {
  final FocusNode focusNode;
  final TextStyle baseStyle;
  final QueryText queryText;

  final ChipsInputController<T> controller;
  final GestureRecognizer onSuggestionTap;

  const ChipsInputRow({
    Key key,
    @required this.queryText,
    @required this.focusNode,
    @required this.baseStyle,
    @required this.onSuggestionTap,
    @required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28.0,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(queryText.query, style: baseStyle.copyWith(color: Colors.transparent)),
              _TextCaret(resumed: focusNode.hasFocus),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: "Action Suggestion",
                child: Semantics(
                  child: RichText(text: queryText.textSpan(baseStyle, onSuggestionTap)),
                  label: "${queryText.suggestion}",
                ),
              ),
            ],
          ),
          if (controller.enabled &&
              queryText.query.trim().isEmpty &&
              controller.suggestion.isEmpty &&
              controller.placeholder.isNotNullOrBlank)
            ChipsInputPlaceholder(baseStyle: baseStyle, placeholder: controller.placeholder),
        ],
      ),
    );
  }
}

class _TextCaret extends StatefulWidget {
  const _TextCaret({
    Key key,
    this.duration = const Duration(milliseconds: 500),
    this.resumed = false,
  }) : super(key: key);

  final Duration duration;
  final bool resumed;

  @override
  _TextCursorState createState() => _TextCursorState();
}

class _TextCursorState extends State<_TextCaret> with SingleTickerProviderStateMixin {
  bool _displayed = false;
  Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.duration, _onTimer);
  }

  void _onTimer(Timer timer) {
    setState(() => _displayed = !_displayed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Opacity(
        opacity: _displayed && widget.resumed ? 1.0 : 0.0,
        child: Container(
          width: 2.0,
          color: theme.primaryColor,
        ),
      ),
    );
  }
}

class ChipsInputPlaceholder extends StatelessWidget {
  final String placeholder;
  final TextStyle baseStyle;

  const ChipsInputPlaceholder({Key key, @required this.placeholder, @required this.baseStyle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          placeholder,
          style: baseStyle.copyWith(color: baseStyle.color.withOpacity(0.4)),
        ),
      ],
    );
  }
}

TextEditingValue textEditingValue(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

const kObjectReplacementChar = 0xFFFC;

TextStyle _defaultTextStyle(ChipsInput widget, ThemeData theme) {
  final defaultStyle = widget.decoration?.labelStyle ?? theme.textTheme.subhead;
  return defaultStyle.copyWith(fontSize: 15);
}

/// Holds query text and suggestions
class QueryText {
  final String query;
  final String suggestion;

  QueryText(this.query, [this.suggestion]);

  bool get hasSuggestion => suggestion?.isNotEmpty == true;

  bool get hasQuery => query?.isNotEmpty == true;

  TextSpan textSpan(TextStyle baseStyle, GestureRecognizer recognizer) {
    final q = query;
    if (!hasSuggestion) recognizer = null;

    if (suggestion?.isNotEmpty != true) recognizer = null;
    return TextSpan(
      children: [
        if (hasQuery) TextSpan(style: baseStyle, text: q, recognizer: recognizer),
        if (hasSuggestion)
          TextSpan(
            recognizer: recognizer,
            text: suggestion.substring(q.length),
            style: baseStyle.copyWith(
              color: baseStyle.color.withOpacity(0.4),
            ),
          ),
      ],
    );
  }
}

enum ChipsInputItemStatus { add, ready, remove }

class ChipsInputItemWidget<T> extends StatelessWidget {
  final T item;
  final Widget child;
  final ChipsInputItemStatus status;
  final TickerProvider vsync;

  ChipsInputItemWidget({
    @required Key key,
    @required this.item,
    @required this.child,
    @required this.vsync,
    this.status,
  })  : assert(child != null),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: status == ChipsInputItemStatus.ready ? null : 0,
        child: Opacity(opacity: status == ChipsInputItemStatus.remove ? 0.0 : 1.0, child: child),
      ),
      vsync: vsync,
      duration: 100.ms,
    );
  }
}
