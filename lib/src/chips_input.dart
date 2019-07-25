import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ChipsInputSuggestions<T> = FutureOr<ChipSuggestions> Function(String query);
typedef ChipSelected<T> = void Function(T data, bool selected);

/// When focus is lost, the component may wish to append any in-flight query automatically.
typedef OnLostFocus<T> = T Function(String);
typedef ChipsBuilder<T> = Widget Function(BuildContext context, ChipsInputState<T> state, T data);

class ChipSuggestions<T> {
  final List<T> suggestions;
  final T match;

  const ChipSuggestions({this.suggestions, this.match});

  static const empty = ChipSuggestions();
}

class ChipsInput<T> extends StatefulWidget {
  ChipsInput({
    Key key,
    this.initialValue = const [],
    this.decoration = const InputDecoration(),
    this.enabled = true,
    @required this.chipBuilder,
    this.suggestionBuilder,
    this.findSuggestions,
    @required this.onChanged,
    this.onChipTapped,
    this.maxChips,
    this.onLostFocus,
    this.inputBuilder,
    this.inputConfiguration,
    this.autofocus,
    this.focusNode,
  })  : assert(maxChips == null || initialValue.length <= maxChips),
        super(key: key);

  final OnLostFocus onLostFocus;
  final InputDecoration decoration;
  final bool enabled;
  final ChipsInputSuggestions findSuggestions;
  final WidgetBuilder inputBuilder;
  final ValueChanged<List<T>> onChanged;
  final ValueChanged<T> onChipTapped;
  final ChipsBuilder<T> chipBuilder;
  final ChipsBuilder<T> suggestionBuilder;
  final List<T> initialValue;
  final int maxChips;
  final bool autofocus;
  final FocusNode focusNode;
  final TextInputConfiguration inputConfiguration;

  @override
  ChipsInputState<T> createState() => ChipsInputState<T>();
}

class ChipsInputState<T> extends State<ChipsInput<T>> implements TextInputClient {
  static const kObjectReplacementChar = 0xFFFC;
  List<T> _chips = List<T>();
  List<T> _suggestions;
  StreamController<List<T>> _suggestionsStreamController;
  int _searchId = 0;
  FocusNode _focusNode;
  TextEditingValue _value = TextEditingValue();
  TextInputConnection _connection;
  _SuggestionsBoxController _suggestionsBoxController;
  LayerLink _layerLink = LayerLink();
  Size size;
  bool _isNew = true;

  String get text => String.fromCharCodes(
        _value.text.codeUnits.where((ch) => ch != kObjectReplacementChar),
      );

  bool get _hasInputConnection => _connection != null && _connection.attached;

  @override
  void initState() {
    super.initState();
    _chips.addAll(widget.initialValue);
    _updateTextInputState();
    _initFocusNode();

    if (widget.onLostFocus != null) {
      _focusNode.addListener(() {
        if (!_focusNode.hasFocus) {
          final result = widget.onLostFocus(this.text);
          if (result != null) {
            selectSuggestion(result);
          }
        }
      });
    }
    this._suggestionsBoxController = _SuggestionsBoxController(context);
    this._suggestionsStreamController = StreamController<List<T>>.broadcast();
  }

  @override
  void didChangeDependencies() {
    if (_isNew) {
      _isNew = false;
      if (widget.autofocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          requestKeyboard();
        });
      }
    }
    super.didChangeDependencies();
  }

  _resetFocusNode(FocusNode newFocusNode) {
    if (newFocusNode != _focusNode) {
      _focusNode?.dispose();
      _focusNode = newFocusNode;
    }
  }

  _initFocusNode() {
    setState(() {
      debugPrint("Initializing focus node");
      if (widget.enabled) {
        if (widget.maxChips == null || _chips.length < widget.maxChips) {
          _resetFocusNode(widget.focusNode ?? FocusNode());
          (() async {
            await this._initOverlayEntry();
            this._focusNode.addListener(_onFocusChanged);

            // in case we already missed the focus event
            if (this._focusNode.hasFocus) {
              this._suggestionsBoxController.open();
            }
          })();
        } else
          _resetFocusNode(AlwaysDisabledFocusNode());
      } else
        _resetFocusNode(AlwaysDisabledFocusNode());
    });
    debugPrint(this._focusNode.toString());
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _openInputConnection();
      // if()
      this._suggestionsBoxController.open();
    } else {
      _closeInputConnectionIfNeeded();
      this._suggestionsBoxController.close();
    }
    setState(() {
      /*rebuild so that _TextCursor is hidden.*/
    });
  }

  Future<void> _initOverlayEntry() async {
    RenderBox renderBox = context.findRenderObject();
    // TODO: See if after_layout mixin (https://pub.dartlang.org/packages/after_layout) works instead of keep checking if rendered

    while (renderBox == null) {
      await Future.delayed(Duration(milliseconds: 10));

      renderBox = context.findRenderObject();
    }

    while (!renderBox.hasSize) {
      await Future.delayed(Duration(milliseconds: 10));
    }

    size = renderBox.size;

    this._suggestionsBoxController._overlayEntry = OverlayEntry(
      builder: (context) {
        return StreamBuilder(
          stream: _suggestionsStreamController.stream,
          builder: (BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (snapshot.data != null && snapshot.data?.length != 0)
              return Positioned(
                width: size.width,
                child: CompositedTransformFollower(
                  link: this._layerLink,
                  showWhenUnlinked: false,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                    elevation: 4.0,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: snapshot.data?.length ?? 0,
                      itemBuilder: (BuildContext context, int index) {
                        return widget.suggestionBuilder(context, this, _suggestions[index]);
                      },
                    ),
                  ),
                ),
              );
            else
              return Container();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    _closeInputConnectionIfNeeded();
    _suggestionsStreamController.close();
    super.dispose();
  }

  void requestKeyboard() {
    if (_focusNode == null) {
      return;
    }
    if (_focusNode?.hasFocus == true) {
      _openInputConnection();
    } else {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  void selectSuggestion(T data) {
    setState(() {
      _chips.add(data);
      if (widget.maxChips != null) _initFocusNode();
      _updateTextInputState();
      _suggestions = null;
      _suggestionsStreamController.add(_suggestions);
    });
    widget.onChanged(_chips.toList(growable: false));
  }

  void deleteChip(T data) {
    if (widget.enabled) {
      setState(() {
        _chips.remove(data);
        _updateTextInputState();
      });
      if (widget.maxChips != null) _initFocusNode();
      widget.onChanged(_chips.toList(growable: false));
    }
  }

  void addChip(T data) {
    if (widget.enabled) {
      setState(() {
        _chips.add(data);
        _updateTextInputState();
      });
      if (widget.maxChips != null) _initFocusNode();
      widget.onChanged(_chips.toList(growable: false));
    }
  }

  void _openInputConnection() {
    if (!_hasInputConnection) {
      _connection = TextInput.attach(this, widget.inputConfiguration ?? TextInputConfiguration());
      _connection.setEditingState(_value);
    }
    _connection.show();
  }

  void _closeInputConnectionIfNeeded() {
    if (_hasInputConnection) {
      _connection.close();
      _connection = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    var chipsChildren =
        _chips.map((data) => widget.chipBuilder(context, this, data)).where((data) => data != null).toList();

    final theme = Theme.of(context);

    chipsChildren.add(
      Container(
        height: 32.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              text,
              style: theme.textTheme.subhead.copyWith(
                height: 1.5,
              ),
            ),
            _TextCaret(
              resumed: _focusNode.hasFocus,
            ),
          ],
        ),
      ),
    );

    return CompositedTransformTarget(
      link: this._layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: requestKeyboard,
        child: InputDecorator(
          decoration: widget.decoration,
          isFocused: _focusNode.hasFocus,
          isEmpty: _value.text.length == 0 && _chips.length == 0,
          child: Wrap(
            children: chipsChildren,
            spacing: 4.0,
            runSpacing: 4.0,
          ),
        ),
      ),
    );
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    final oldCount = _countReplacements(_value);
    final newCount = _countReplacements(value);
    setState(() {
      if (newCount < oldCount) {
        _chips = List.from(_chips.take(newCount));
        widget.onChanged(_chips.toList(growable: false));
      }
      _value = value;
    });
    _onSearchChanged(text);
  }

  int _countReplacements(TextEditingValue value) {
    return value.text.codeUnits.where((ch) => ch == kObjectReplacementChar).length;
  }

  @override
  void performAction(TextInputAction action) {
    _focusNode.unfocus();
  }

  void _updateTextInputState() {
    final text = String.fromCharCodes(_chips.expand((_) => [kObjectReplacementChar]));
    _value = TextEditingValue(
      text: "$text",
    );
    if (_connection == null)
      _connection = TextInput.attach(this, widget.inputConfiguration ?? TextInputConfiguration());
    _connection.setEditingState(_value);
    requestKeyboard();
  }

  void _onSearchChanged(String value) async {
    final localId = ++_searchId;
    final ChipSuggestions results = await widget.findSuggestions(value);
    if (_searchId == localId && mounted) {
      if (results.match != null) {
        selectSuggestion(results.match);
      }
      if (results.suggestions != null) {
        setState(() =>
            _suggestions = results.suggestions.where((profile) => !_chips.contains(profile))?.toList(growable: false));
      }
    }
    _suggestionsStreamController.add(_suggestions);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    print(point);
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

class _SuggestionsBoxController {
  final BuildContext context;

  OverlayEntry _overlayEntry;

  bool _isOpened = false;

  _SuggestionsBoxController(this.context);

  open() {
    if (this._isOpened) return;
    assert(this._overlayEntry != null);
    Overlay.of(context).insert(this._overlayEntry);
    this._isOpened = true;
  }

  close() {
    if (!this._isOpened) return;
//    assert(this._overlayEntry != null);
    this._overlayEntry?.remove();
    this._isOpened = false;
  }

  toggle() {
    if (this._isOpened) {
      this.close();
    } else {
      this.open();
    }
  }
}
