import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:flutter_chips_input_sunny/src/chips_input_controller.dart';
import 'package:after_layout/after_layout.dart';

/// Generates a list of suggestions given a query
typedef GenerateSuggestions<T> = FutureOr<ChipSuggestions> Function(String query);

/// Builds a widget for a chip.  Used for autocomplete and chips
typedef BuildChipsWidget<T> = Widget Function(BuildContext context, T data);

/// An action that's executed when the user clicks the keyboard action
typedef PerformTextInputAction<T> = void Function(TextInputAction type);

/// Tokenizes a chip to help provide inline completion
typedef ChipTokenizer<T> = Iterable<String> Function(T input);

/// Generic action performed on a chip
typedef ChipAction<T> = void Function(T chip);

// ignore: must_be_immutable
class ChipsInput<T> extends StatefulWidget {
  ChipsInput({
    Key key,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.enabled = true,
    @required this.chipBuilder,
    this.suggestionBuilder,
    this.findSuggestions,
    this.chipTokenizer,
    this.onChipTapped,
    this.maxChips,
    this.inputConfiguration,
    this.autofocus,
    this.focusNode,
    this.onQueryChanged,
    this.onInputAction,

    /// When an inline suggestion is present and tapped.
    this.onSuggestionTap,
    this.controller,
  })  : assert(maxChips == null || initialValue.length <= maxChips),
        assert(controller == null || findSuggestions == null),
        super(key: key);

  /// Generates tokens for a chip.  If this is provided, then inline suggestions will show up.
  final ChipTokenizer<T> chipTokenizer;

  /// Allows external control of the data within this input
  final ChipsInputController<T> controller;
  final InputDecoration decoration;
  final bool enabled;

  /// Callback to generate suggestions.  This is only used when _not_ providing a [controller]
  final GenerateSuggestions findSuggestions;

  final ValueChanged<String> onQueryChanged;
  final ValueChanged<T> onChipTapped;
  final BuildChipsWidget<T> chipBuilder;
  final BuildChipsWidget<T> suggestionBuilder;
  final List<T> initialValue;
  final int maxChips;
  final bool autofocus;
  final FocusNode focusNode;
  final TextInputConfiguration inputConfiguration;
  final PerformTextInputAction<T> onInputAction;
  final ChipAction<T> onSuggestionTap;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>();
}

class ChipsInputState<T> extends State<ChipsInput<T>> with AfterLayoutMixin<ChipsInput<T>> implements TextInputClient {
  ChipsInputController<T> _controller;
  FocusNode _focusNode;
  TextInputConnection _connection;
  LayerLink _layerLink = LayerLink();

  List<StreamSubscription> _streams = [];

  bool get hasInputConnection => _connection != null && _connection.attached;
  GestureRecognizer _onSuggestionTap;

  // A list of focus nodes we've used that need to be disposed
  List<FocusNode> _focusNodes = [];
  Size size;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ChipsInputController<T>(widget.findSuggestions);
    _controller.enabled = widget.enabled;
    if (widget.initialValue != null) {
      _controller.addAll(widget.initialValue);
    }

    _controller.addListener(_onChanged);
    _streams.add(_controller.queryStream.listen((query) {
      if (!query.userInput) {
        _connection?.setEditingState(textEditingValue(_chipReplacementText + query.text));
      }
    }));

    _streams.add(_controller.chipStream.listen((chips) {
      _connection?.setEditingState(textEditingValue(_chipReplacementText + _controller.query));
    }));

    _initFocusNode();

    if (widget.onSuggestionTap != null) {
      _onSuggestionTap = TapGestureRecognizer()
        ..onTap = () {
          widget.onSuggestionTap(_controller.suggestion);
        };
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _focusNodes.forEach((node) => node.dispose());
    if (widget.controller == null) {
      _controller.dispose();
    }
    _streams.forEach((sub) => sub.cancel());
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  _onChanged() {
    setState(() {
      if (widget.maxChips != null) _initFocusNode();
    });

    requestKeyboard(context);
  }

  int _countReplacements(String value) {
    return value.codeUnits.where((ch) => ch == kObjectReplacementChar).length;
  }

  String get _chipReplacementText => String.fromCharCodes(_chips.expand((_) => [kObjectReplacementChar]));

  TextEditingValue get _textValue => textEditingValue(_chipReplacementText + _query);

  List<T> get _chips => _controller.chips;

  String get _query => _controller.query ?? "";

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
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    print(point);
  }

  /// Implemented from [TextInputClient].  This should never be called directly; instead, use the [_controller] to
  /// set the editing value
  @override
  void updateEditingValue(TextEditingValue value) {
    String newText = value.text;
    final oldCount = _chips.length;
    final newCount = _countReplacements(newText);
    if (newCount < oldCount) {
      _controller.chips = _chips.take(newCount);
    }
    _controller.setQuery(
      String.fromCharCodes(newText.codeUnits.where((c) => c != kObjectReplacementChar)),
      userInput: true,
    );
  }

  void _openInputConnection() {
    if (!hasInputConnection) {
      _connection = TextInput.attach(this, widget.inputConfiguration ?? TextInputConfiguration());
      _connection.setEditingState(_textValue);
    }
    _connection.show();
  }

  void _closeInputConnectionIfNeeded() {
    if (hasInputConnection) {
      _connection.close();
      _connection = null;
    }
  }

  bool requestKeyboard(BuildContext context) {
    if (_focusNode == null) {
      return false;
    }
    if (_focusNode?.hasFocus == true) {
      _openInputConnection();
      return true;
    } else {
      FocusScope.of(context).requestFocus(_focusNode);
      return false;
    }
  }

  bool _resetFocusNode(FocusNode newFocusNode) {
    if (newFocusNode != _focusNode) {
      if (_focusNode != null) {
        _focusNodes.add(_focusNode);
      }
      _focusNode = newFocusNode;
    }
    return newFocusNode != _focusNode;
  }

  _initFocusNode() {
    if (widget.enabled) {
      if (widget.maxChips == null || _chips.length < widget.maxChips) {
        bool changed = _resetFocusNode(widget.focusNode ?? FocusNode());
        if (changed) {
          _focusNode.addListener(_onFocusChanged);
          debugPrint(this._focusNode.toString());
        }
        _controller.open();
      } else {
        _resetFocusNode(AlwaysDisabledFocusNode());
      }
    } else {
      _resetFocusNode(AlwaysDisabledFocusNode());
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _openInputConnection();
      _controller.open();
    } else {
      _closeInputConnectionIfNeeded();
      _controller.close();
    }
    setState(() {
      /*rebuild so that _TextCursor is hidden.*/
    });
  }

  @override
  void afterFirstLayout(BuildContext context) {
    final RenderBox box = context.findRenderObject();
    size = box.size;
    _controller.initialize(context, OverlayEntry(
      builder: (context) {
        return StreamBuilder(
          stream: _controller.suggestionStream,
          builder: (BuildContext context, AsyncSnapshot<ChipSuggestions<T>> snapshot) {
            if (snapshot.data?.suggestions?.isNotEmpty == true) {
              final _suggestions = snapshot.data.suggestions;
              return Positioned(
                width: size.width,
                child: CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                    elevation: 4.0,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: snapshot.data?.suggestions?.length ?? 0,
                      itemBuilder: (BuildContext context, int index) {
                        return widget.suggestionBuilder(context, _suggestions[index]);
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

    if (widget.autofocus == true) {
      if (!requestKeyboard(context)) {
        requestKeyboard(context);
      }
    }
  }

  TextSpan get _textSpan {
    final suggestionToken = _controller.suggestionToken;
    final q = _query;
    final _recognizer = suggestionToken != null ? _onSuggestionTap : null;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme.subhead.copyWith(height: 1.5);
    return TextSpan(
      children: [
        TextSpan(
          style: textTheme,
          text: q,
          recognizer: _recognizer,
        ),
        if (suggestionToken != null)
          TextSpan(
            recognizer: _recognizer,
            text: suggestionToken.substring(q.length),
            style: textTheme.copyWith(
              color: textTheme.color.withOpacity(0.4),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var chipsChildren = _chips.map((data) => widget.chipBuilder(context, data)).where((data) => data != null).toList();

    final theme = Theme.of(context);
    final textTheme = theme.textTheme.subhead.copyWith(height: 1.5, color: Colors.transparent);
    chipsChildren.add(
      Container(
        height: 32.0,
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_query, style: textTheme),
                _TextCaret(resumed: _focusNode.hasFocus),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RichText(text: _textSpan),
              ],
            ),
          ],
        ),
      ),
    );

    bool _deleting = false;
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => requestKeyboard(context),
        onPanEnd: (details) {
          if (_deleting) {
            _deleting = false;
            // other way??
            if (_controller.query.isNotEmpty == true) {
              _controller.setQuery("");
            } else if (_controller.size > 0) {
              _controller.pop();
            } else {
              // Close the whole thing?
              Navigator.pop(context);
            }
          }
        },
        onPanUpdate: (details) {
          if (details.delta.dx > 0) {
            _deleting = false;
            // We are trying to select something
            if (_controller.suggestion != null) {
              _controller.acceptSuggestion();
            }
          } else if (details.delta.dx < 0) {
            _deleting = true;
          }
        },
        child: InputDecorator(
          decoration: widget.decoration,
          isFocused: _focusNode.hasFocus,
          isEmpty: _query?.isNotEmpty != true && _chips.length == 0,
          child: Wrap(
            children: chipsChildren,
            spacing: 4.0,
            runSpacing: 4.0,
          ),
        ),
      ),
    );
  }
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
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
    _timer.cancel();
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

textEditingValue(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

const kObjectReplacementChar = 0xFFFC;
