import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:flutter_chips_input_sunny/src/chips_input.dart';

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
  final StreamController<ChipSuggestions<T>> _suggestionsStreamController = StreamController.broadcast();
  final StreamController<ChipInput> _queryStreamController = StreamController.broadcast();
  final StreamController<Iterable<T>> _chipStream = StreamController.broadcast();
  final ChipTokenizer<T> tokenizer;
  OverlayEntry _overlayEntry;
  BuildContext _context;

  ControllerStatus get status => _status;
  String get placeholder => _placeholder;

  ChipsInputController(this.findSuggestions, {ChipTokenizer<T> tokenizer})
      : assert(findSuggestions != null),
        tokenizer = tokenizer ?? ((t) => ["$t"]);

  List<T> get chips => List.from(_chips, growable: false);

  get suggestionToken => (query.isNotEmpty && _suggestionToken != null && query.length < _suggestionToken?.length)
      ? _suggestionToken
      : null;

  int get size => _chips.length;

  set placeholder(String placeholder) {
    this._placeholder = placeholder;
    notifyListeners();
  }

  set chips(Iterable<T> chips) {
    _chips.clear();
    _chips.addAll(chips);
    _chipStream.add(List.from(_chips, growable: false));
    notifyListeners();
  }

  dispose() {
    super.dispose();
    _suggestionsStreamController.close();
    _queryStreamController.close();
    _chipStream.close();
  }

  Stream<ChipSuggestions<T>> get suggestionStream => _suggestionsStreamController.stream;

  Stream<ChipInput> get queryStream => _queryStreamController.stream;

  Stream<Iterable<T>> get chipStream => _chipStream.stream;

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
    _suggestionsStreamController.add(ChipSuggestions(suggestions: suggestions));
    notifyListeners();
  }

  setQuery(String query, {bool userInput = false}) {
    if (query != _query) {
      _query = query;
      _queryStreamController.add(ChipInput(query, userInput: userInput));
      notifyListeners();
      Future.microtask(() => _loadSuggestions());
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
    _suggestionsStreamController.add(results);
    notifyListeners();
  }

  calculateInlineSuggestion(Iterable<T> _suggestions, {bool notify = false}) {
    // Looks for the first suggestion that actually matches what the user is typing so we
    // can add an inline suggestion
    final allTokens = _suggestions.expand((chip) {
      return tokenizer(chip).where((token) => token != null).toSet().map((token) => MapEntry(chip, token));
    });
    final matchingToken = allTokens.firstWhere((entry) {
      return entry.value.toLowerCase().startsWith(query.toLowerCase());
    }, orElse: () => null);

    _suggestion = matchingToken?.key;
    _suggestionToken = matchingToken?.value;
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

  void removeAt(int index) {
    _chips.removeAt(index);
    _chipStream.add(List.from(_chips, growable: false));
    notifyListeners();
  }

  void deleteChip(T data) {
    if (enabled) {
      _chips.remove(data);
      _chipStream.add(List.from(_chips, growable: false));
      notifyListeners();
    }
  }

  void acceptSuggestion({T suggestion}) {
    if (suggestionToken != null && query?.isNotEmpty == true) {
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
      _chipStream.add(List.from(_chips, growable: false));
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
        for (var i = 0; i < newChips.length; i++) {
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

        for (var i = newChips.length; i < currSize; i++) {
          _chips.removeAt(i);
          changed = true;
        }
      } catch (e) {
        print("Error updating list state: $e");
        throw e;
      }
    }
    if (changed) {
      _chipStream.add(List.from(_chips, growable: false));
      notifyListeners();
    }
    return changed;
  }

  void addAll(Iterable<T> values) {
    values?.forEach((v) => _chips.add(v));
    _chipStream.add(List.from(_chips, growable: false));
    notifyListeners();
  }

  void resetSuggestions() {
    _suggestion = null;
    _query = null;
    _suggestions = [];
    _suggestionsStreamController.add(ChipSuggestions.empty<T>());
    _queryStreamController.add(ChipInput("", userInput: false));
    notifyListeners();
  }

  void pop() {
    _chips.removeLast();
    _chipStream.add(List.from(_chips, growable: false));
    notifyListeners();
  }

  initialize(BuildContext context, OverlayEntry entry) {
    _overlayEntry = entry;
    _context = context;
    if (_status == ControllerStatus.opening) {
      _status = ControllerStatus.closed;
      open();
    }
  }

  bool open() {
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
    if (_status != ControllerStatus.open) return;
    this._overlayEntry?.remove();
    this._status = ControllerStatus.closed;
  }

  toggle(BuildContext context) {
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
