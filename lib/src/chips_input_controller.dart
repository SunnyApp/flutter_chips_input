import 'dart:async';

import 'package:collection_diff/collection_diff.dart';
import 'package:collection_diff/list_diff_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:flutter_chips_input_sunny/src/chips_input.dart';
import 'package:logging/logging.dart';
import 'package:sunny_dart/sunny_dart.dart';

final _log = Logger("chips_input");

class ChipsInputController<T> extends ChangeNotifier {
  final GenerateSuggestions<T> findSuggestions;
  String _query;
  final List<T> _chips = List<T>();
  List<T> _suggestions;
  ControllerStatus _status = ControllerStatus.closed;
  Suggestion<T> _suggestion = Suggestion.empty();
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
  final StreamController<ListDiffs<T>> _changeStream;
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
        _changeStream = StreamController.broadcast(sync: sync),
        _queryStream = StreamController.broadcast(sync: sync);

  List<T> get chips => List.from(_chips, growable: false);

  String get suggestionToken => _suggestion.highlightText;

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
  Stream<ListDiffs<T>> get changes => _changeStream.stream;

  Stream<ChipInput> get queryStream => _queryStream.stream;

  Stream<ChipList<T>> get chipStream => _chipStream.stream;

  List<T> get suggestions => List.from(_suggestions ?? [], growable: false);

  String get query => _query ?? "";

  Suggestion<T> get suggestion => _suggestion;

  set suggestion(Suggestion<T> suggestion) {
    suggestion = suggestion ?? Suggestion.empty();
    if (suggestion.isNotEmpty && suggestion.highlightText == null) {
      /// Should we do this here??
      suggestion = suggestion.copy(
          highlightText: tokenizer(suggestion.item).orEmpty().where((s) {
        return s.toLowerCase().startsWith(query.toLowerCase());
      }).firstOrNull);
    }
    _suggestion = suggestion;
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
      suggestion = Suggestion.empty();
    } else {
      /// Provides us indexed access
      final suggestions = [...?_suggestions];
      final List<Map<String, String>> allTokens = _suggestions.map((chip) {
        final itemTokens = tokenizer(chip).where((token) {
          return token != null;
        }).keyed((_) => _.toLowerCase());
        return itemTokens;
      }).toList();
      _log.info("allTokens: ${allTokens.length}");

      final matchingItem = allTokens.whereIndexed(
        (entry) {
          return entry.keys.any((s) => s.startsWith(query.toLowerCase()));
        },
      ).firstOrNull;

      if (matchingItem != null) {
        _suggestion = Suggestion.highlighted(
            item: suggestions[matchingItem.index],

            /// Probably the longest suggestion token would be best... this gives the most recognizability (remember that
            /// all these tokens come from the same item anyway)
            highlightText: matchingItem.value
                .whereKeys((key) => key.startsWith(query.toLowerCase()))
                .entries
                .sorted((a, b) => a.key.length.compareTo(b.key.length))
                .last
                .value);

        _log.info("Found suggestion: $_suggestion");
      } else {
        _suggestion = Suggestion.empty();
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  setInlineSuggestion(T suggestion, {String suggestionToken, bool notify = false}) {
    _suggestion = Suggestion.highlighted(
        item: suggestion, highlightText: suggestionToken ?? suggestionToken ?? tokenizer(suggestion).first);
    if (notify) {
      notifyListeners();
    }
  }

  ChipList<T> _currentChips(bool userInput) => ChipList<T>(List.from(_chips, growable: false), userInput: userInput);

  void removeAt(int index) {
    _applyDiff(() {
      _chips.remove(index);
    });
  }

  void deleteChip(T data) {
    _applyDiff(() {
      _chips.remove(data);
    });
  }

  void acceptSuggestion({T suggestion}) {
    if (suggestionToken != null) {
      final _toAdd = suggestion ?? this._suggestion.item;
      _suggestion = Suggestion.empty();
      if (_toAdd != null) {
        addChip(_toAdd, resetQuery: true);
      }
    }
  }

  bool _applyDiff(void mutation(), {bool notify = true}) {
    if (!enabled) return false;

    final orig = [..._chips];
    mutation();
    final diffs = orig.differences([..._chips]);
    if (diffs.isNotEmpty) {
      _changeStream.add(diffs);
      _chipStream.add(_currentChips(false));
      if (notify) notifyListeners();
    }
    return diffs.isNotEmpty;
  }

  void addChip(T data, {bool resetQuery = false}) {
    _applyDiff(() {
      _chips.add(data);
    });

    if (resetQuery) {
      resetSuggestions();
    }
  }

  bool syncChips(Iterable<T> newChips) {
    final changed = _applyDiff(() {
      _chips.clear();
      _chips.addAll(newChips);
    });

    return changed;
  }

  void addAll(Iterable<T> values) {
    _applyDiff(() {
      values?.forEach((v) => _chips.add(v));
    });
  }

  void resetSuggestions() {
    _suggestion = const Suggestion.empty();
    _query = null;
    _suggestions = [];
    _suggestionsStream.add(const ChipSuggestions.empty());
    _queryStream.add(ChipInput("", userInput: false));
    notifyListeners();
  }

  void pop() {
    _applyDiff(() {
      _chips.removeLast();
    });
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
