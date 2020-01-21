import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:flutter_chips_input_sunny/src/chips_input.dart';
import 'package:logging/logging.dart';

final _log = Logger("chips_input");

class ChipsInputController<T> extends ChangeNotifier {
  final GenerateSuggestions<T> findSuggestions;
  String _query;
  final List<T> _chips = List<T>();
  List<T> _suggestions;
  T _suggestion;
  ControllerStatus _status = ControllerStatus.closed;
  String _suggestionToken;
  String _placeholder;
  bool enabled = true;
  bool get disabled => enabled != true;

  VoidCallback _requestKeyboard;
  VoidCallback _hideKeyboard;

  TextInputConnection connection;

  requestKeyboard() {
    _requestKeyboard?.call();
  }

  hideKeyboard() {
    _hideKeyboard?.call();
  }

  set requestKeyboardCallback(VoidCallback callback) => this._requestKeyboard = callback;
  set hideKeyboardCallback(VoidCallback callback) => this._hideKeyboard = callback;

  final StreamController<ChipSuggestions<T>> _suggestionsStream;
  final StreamController<ChipInput> _queryStream;
  final StreamController<ChipList<T>> _chipStream;
  final ChipTokenizer<T> tokenizer;
  OverlayEntry _overlayEntry;
  BuildContext _context;

  bool hideSuggestionOverlay;

  ControllerStatus get status => _status;

  String get placeholder => _placeholder;

  ChipsInputController(
    this.findSuggestions, {
    bool sync = false,
    ChipTokenizer<T> tokenizer,
    this.hideSuggestionOverlay = false,
  })  : assert(findSuggestions != null),
        tokenizer = tokenizer ?? ((t) => ["$t"]),
        _suggestionsStream = StreamController.broadcast(sync: sync),
        _chipStream = StreamController.broadcast(sync: sync),
        _queryStream = StreamController.broadcast(sync: sync);

  List<T> get chips => List.from(_chips, growable: false);

  String get suggestionToken => _suggestionToken;

  int get size => _chips.length;

  set placeholder(String placeholder) {
    this._placeholder = placeholder;
    notifyListeners();
  }

  updateChips(Iterable<T> chips, {@required bool userInput}) {
    _chips.clear();
    _chips.addAll(chips);
    _chipStream.add(_currentChips(userInput));
    notifyListeners();
  }

  dispose() {
    super.dispose();
    _suggestionsStream.close();
    _queryStream.close();
    _chipStream.close();
  }

  Stream<ChipSuggestions<T>> get suggestionStream => _suggestionsStream.stream;

  Stream<ChipInput> get queryStream => _queryStream.stream;

  Stream<ChipList<T>> get chipStream => _chipStream.stream;

  List<T> get suggestions => List.from(_suggestions ?? [], growable: false);

  String get query => _query ?? "";

  T get suggestion => _suggestion;

  set suggestion(T suggestion) {
    _suggestion = suggestion;
    if (suggestion != null) {
      _suggestionToken = tokenizer(suggestion)?.firstWhere(
        (s) => s.toLowerCase().startsWith(query.toLowerCase()),
        orElse: () => null,
      );
    }
    notifyListeners();
  }

  set suggestions(Iterable<T> suggestions) {
    _suggestions = suggestions;

    calculateInlineSuggestion(_suggestions);
    _suggestionsStream.add(ChipSuggestions(suggestions: suggestions));
    notifyListeners();
  }

  setQuery(String query, {bool userInput = false}) {
    if (query != _query) {
      _query = query;
      _queryStream.add(ChipInput(query, userInput: userInput));
      notifyListeners();
//      Future.microtask(() => _loadSuggestions());
    }
  }

  _loadSuggestions() async {
    final ChipSuggestions<T> results = await findSuggestions(_query);
    _suggestions = results.suggestions?.where((suggestion) => !_chips.contains(suggestion))?.toList(growable: false);
    if (results.match != null) {
      _suggestion = results.match;
    } else {
      calculateInlineSuggestion(_suggestions);
    }
    _suggestionsStream.add(results);
    notifyListeners();
  }

  calculateInlineSuggestion(Iterable<T> _suggestions, {bool notify = false}) {
    // Looks for the first suggestion that actually matches what the user is typing so we
    // can add an inline suggestion
    if (query.isEmpty) {
      _suggestion = null;
      _suggestionToken = null;
    } else {
      final allTokens = _suggestions.expand((chip) {
        return tokenizer(chip)
            .where((token) {
              return token != null;
            })
            .toSet()
            .map((token) {
              return MapEntry(chip, token);
            });
      }).toList();
      _log.info("allTokens: ${allTokens.length}");
      final matchingToken = allTokens.firstWhere((entry) {
        return entry.value.toLowerCase().startsWith(query.toLowerCase());
      }, orElse: () => null);

      _suggestion = matchingToken?.key;
      _suggestionToken = matchingToken?.value;
    }
    if (notify) {
      notifyListeners();
    }
  }

  setInlineSuggestion(T suggestion, {String suggestionToken, bool notify = false}) {
    _suggestion = suggestion;
    _suggestionToken = suggestionToken ?? tokenizer(suggestion).first;
    if (notify) {
      notifyListeners();
    }
  }

  ChipList<T> _currentChips(bool userInput) => ChipList<T>(List.from(_chips, growable: false), userInput: userInput);

  void removeAt(int index) {
    _chips.removeAt(index);
    _chipStream.add(_currentChips(false));
    notifyListeners();
  }

  void deleteChip(T data) {
    if (enabled) {
      _chips.remove(data);
      _chipStream.add(_currentChips(false));
      notifyListeners();
    }
  }

  void acceptSuggestion({T suggestion}) {
    if (suggestionToken != null) {
      final _toAdd = suggestion ?? this._suggestion;
      _suggestion = null;
      _suggestionToken = null;
      if (_toAdd != null) {
        addChip(_toAdd, resetQuery: true);
      }
    }
  }

  void addChip(T data, {bool resetQuery = false}) {
    if (enabled) {
      _chips.add(data);
      _chipStream.add(_currentChips(false));
      notifyListeners();
    }
    if (resetQuery) {
      resetSuggestions();
    }
  }

  bool syncChips(Iterable<T> newChips) {
    bool changed = false;

    if (enabled) {
      try {
        final currSize = this._chips.length;
        final newList = newChips.toList();
        var i = 0;
        for (; i < newChips.length; i++) {
          final newItem = newList[i];
          if (_chips.length > i) {
            if (_chips[i] != newItem) {
              changed = true;
              _chips.removeAt(i);
              _chips.insert(i, newItem);
            }
          } else {
            changed = true;
            _chips.add(newItem);
          }
        }

        final trimSize = currSize - i;
        if (trimSize > 0) {
          Iterable.generate(trimSize).forEach((_) => _chips.removeLast());
          changed = true;
        }
      } catch (e) {
        print("Error updating list state: $e");
        throw e;
      }
    }
    if (changed) {
      _chipStream.add(_currentChips(false));
      notifyListeners();
    }
    return changed;
  }

  void addAll(Iterable<T> values) {
    values?.forEach((v) => _chips.add(v));
    _chipStream.add(_currentChips(false));
    notifyListeners();
  }

  void resetSuggestions() {
    _suggestion = null;
    _query = null;
    _suggestions = [];
    _suggestionsStream.add(ChipSuggestions.empty<T>());
    _queryStream.add(ChipInput("", userInput: false));
    notifyListeners();
  }

  void pop() {
    _chips.removeLast();
    _chipStream.add(_currentChips(false));
    notifyListeners();
  }

  initialize(BuildContext context, OverlayEntry entry) {
    if (!hideSuggestionOverlay) {
      _overlayEntry = entry;
    }
    _context = context;
    if (_status == ControllerStatus.opening) {
      _status = ControllerStatus.closed;
      open();
    }
  }

  bool open() {
    if (hideSuggestionOverlay) {
      return false;
    }
    switch (_status) {
      case ControllerStatus.open:
        return true;
      case ControllerStatus.closed:
        if (_overlayEntry != null) {
          Overlay.of(_context).insert(_overlayEntry);
          _status = ControllerStatus.open;
          return true;
        } else {
          _status = ControllerStatus.opening;
          return false;
        }
        break;
      case ControllerStatus.opening:
        return true;
      default:
        return false;
    }
  }

  close() {
    if (hideSuggestionOverlay) {
      return;
    }
    if (_status != ControllerStatus.open) return;
    this._overlayEntry?.remove();
    this._status = ControllerStatus.closed;
  }

  toggle(BuildContext context) {
    if (hideSuggestionOverlay) {
      return;
    }
    if (_status != ControllerStatus.closed) {
      this.close();
    } else {
      this.open();
    }
  }
}

enum ControllerStatus { open, closed, opening }

/// Helps to detect input that came from the user's keyboard so we don't infinitely update the text box
class ChipInput {
  final String text;
  final bool userInput;

  ChipInput(this.text, {this.userInput});
}

class ChipList<T> {
  final Iterable<T> chips;
  final bool userInput;

  ChipList(this.chips, {@required this.userInput});
}
