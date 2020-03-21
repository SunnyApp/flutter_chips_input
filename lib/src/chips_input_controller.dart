import 'dart:async';

import 'package:collection_diff/collection_diff.dart';
import 'package:collection_diff/list_diff_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';
import 'package:flutter_chips_input_sunny/src/chip_diff.dart';
import 'package:flutter_chips_input_sunny/src/chips_input.dart';
import 'package:logging/logging.dart';
import 'package:observable_collections/observable_collections.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:sunny_dart/sunny_dart.dart';

const defaultDebugLabel = 'chipsInput';
final _log = Logger(defaultDebugLabel);

/// Controls the chips input, allows for fine-grained control of various aspects
class ChipsInputController<T> extends ChangeNotifier with Disposable {
  /// The callback to search for suggestions based on chips or query
  final GenerateSuggestions<T> findSuggestions;

  /// The current state of the query (text the user types in)
  final AsyncValueStream<String> _query;

  /// The current list of chips to display
  final SunnyObservableList<T> chips;

  final SyncStream<ChipSuggestions<T>> _suggestions;
  final SyncStream<Suggestion<T>> _suggestion;
  final StreamController<ChipsDiff<T>> _diffs;

  /// Current status of the whole control
  ControllerStatus _status = ControllerStatus.closed;

  final SyncStream<String> _placeholder;
  bool enabled = true;

  bool get disabled => enabled != true;

  /// Callback to request keyboard - helps keep this control separated from the view
  VoidCallback _requestKeyboard;

  /// Callback to hide keyboard - helps keep this control separated from the view
  VoidCallback _hideKeyboard;

  /// Current textInputConnection
  TextInputConnection connection;

  /// Tokenizes each chip to support full-text searching
  final ChipTokenizer<T> tokenizer;
  OverlayEntry _overlayEntry;

  /// The current build context for this control
  BuildContext _context;

  bool hideSuggestionOverlay;

  final String debugLabel;

  ChipsInputController({
    GenerateSuggestions<T> findSuggestions,
    String debugName,
    bool suggestOnType = true,
    String placeholder,
    String query,
    Iterable<T> chips,
    DiffEquality equality,
    ChipTokenizer<T> tokenizer,
    bool hideSuggestionOverlay,
  }) : this._(
          debugName ?? defaultDebugLabel,
          chips ?? [],
          placeholder,
          query,
          findSuggestions ?? ((_) => const ChipSuggestions.empty()),
          equality ?? const DiffEquality(),
          suggestOnType,
          hideSuggestionOverlay ?? false,
          tokenizer ?? ((t) => ["$t"]),
        );

  ChipsInputController._(
    this.debugLabel,
    Iterable<T> chips,
    String placeholder,
    String query,
    this.findSuggestions,
    DiffEquality equality,
    bool suggestOnType,
    this.hideSuggestionOverlay,
    ChipTokenizer<T> tokenizer,
  )   : assert(findSuggestions != null),
        chips = SunnyObservableList.of(
          [...?chips],
          diffEquality: equality,
          debugLabel: "$debugLabel => chips",
        ),
        _placeholder = SyncStream.controller(
          debugName: "$debugLabel => placeholder",
          initialValue: placeholder,
        ),
        _suggestions = SyncStream.controller(
          debugName: "$debugLabel => suggestions",
          initialValue: const ChipSuggestions.empty(),
        ),
        _diffs = StreamController.broadcast(),
        _suggestion = SyncStream.controller(debugName: "$debugLabel => suggestions"),
        tokenizer = tokenizer ?? ((t) => ["$t"]),
        _query = AsyncValueStream(
          debugName: "$debugLabel => query",
          transform: (input) => input.debounce(300.ms),
          initialValue: query,
        ) {
    if (suggestOnType == true) {
      registerStream(_query.flatten().asyncMapSample((input) async {
        await loadSuggestions(input);
      }));
    }
  }

  Stream<ChipsDiff<T>> get diffStream => _diffs.stream;

  ControllerStatus get status => _status;

  String get placeholder => _placeholder.current;

  String get suggestionToken => _suggestion.current?.highlightText;

  int get size => chips.length;

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  set placeholder(String placeholder) {
    this._placeholder.update(placeholder);
    notifyListeners();
  }

  Future updateChips(Iterable<T> chips, {@required bool resetQuery, @required ChipChangeOperation source}) async {
    /// Notify:false ?  Dunny
    await this.syncChips(chips, notify: true, resetQuery: resetQuery, source: source);
  }

  Future dispose() async {
    _isDisposed = true;
    _status = ControllerStatus.closed;
    await _diffs.close();
    super.dispose();
    chips.dispose();
    _placeholder.disposeAll();
    await _query.dispose();
    await _suggestions.dispose();
  }

  ValueStream<ChipSuggestions<T>> get suggestionsStream => _suggestions;
  ValueStream<Suggestion<T>> get suggestionStream => _suggestion;

  ValueStream<String> get queryStream => _query;

  List<T> get suggestions => List.from(_suggestions.current?.suggestions ?? [], growable: false);

  String get query => _query.current ?? "";

  Suggestion<T> get suggestion => _suggestion.current ?? const Suggestion.empty();

  X checkStatus<X>(X operation()) {
    if (_isDisposed) {
      return null;
    } else {
      return operation();
    }
  }

  void checkStatusVoid(void operation()) {
    if (!_isDisposed) {
      operation();
    }
  }

  set suggestion(Suggestion<T> suggestion) => checkStatusVoid(() {
        suggestion ??= Suggestion<T>.empty();
        if (suggestion.isNotEmpty && suggestion.highlightText == null) {
          /// Should we do this here??
          suggestion = suggestion.copy(
              highlightText: tokenizer(suggestion.item).orEmpty().where((s) {
            return s.toLowerCase().startsWith(query.toLowerCase());
          }).firstOrNull);
        }
        _suggestion.current = suggestion;
        notifyListeners();
      });

  set suggestions(Iterable<T> suggestions) => checkStatusVoid(() {
        final suggest = ChipSuggestions<T>(suggestions: [...?suggestions]);
        calculateInlineSuggestion(suggest);
        _suggestions.current = suggest;
        notifyListeners();
      });

  setQuery(String query, {bool isInput}) async {
    if (_isDisposed) return;
    await _query.syncUpdate(query);
  }

  notifyListeners() {
    if (_isDisposed) return;
    if (_status != ControllerStatus.open) return;
    super.notifyListeners();
  }

  loadSuggestions(String query) async {
    if (_isDisposed) return;
    final ChipSuggestions<T> results = (await findSuggestions(query)).removeAll(chips);
    if (results.match != null) {
      suggestion = results.match;
    } else {
      calculateInlineSuggestion(_suggestions.current);
    }
    _suggestions.current = results;
    notifyListeners();
  }

  calculateInlineSuggestion(ChipSuggestions<T> _chipSuggest, {bool notify = false}) {
    if (_isDisposed) return;
    // Looks for the first suggestion that actually matches what the user is typing so we
    // can add an inline suggestion
    if (query.isEmpty) {
      suggestion = Suggestion.empty();
    } else {
      /// Provides us indexed access
      final suggestions = [...?_chipSuggest?.suggestions];
      final List<Map<String, String>> allTokens = suggestions.map((chip) {
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
        suggestion = Suggestion.highlighted(
            item: suggestions[matchingItem.index],

            /// Probably the longest suggestion token would be best... this gives the most recognizability (remember that
            /// all these tokens come from the same item anyway)
            highlightText: matchingItem.value
                .whereKeys((key) => key.startsWith(query.toLowerCase()))
                .entries
                .sortedBy((a, b) => a.key.length.compareTo(b.key.length))
                .last
                .value);

        _log.info("Found suggestion: $_suggestion");
      } else {
        suggestion = Suggestion.empty();
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  setInlineSuggestion(T suggestion, {String suggestionToken, bool notify = false}) {
    if (_isDisposed) return;
    this.suggestion = Suggestion.highlighted(
        item: suggestion, highlightText: suggestionToken ?? suggestionToken ?? tokenizer(suggestion).first);
    if (notify) {
      notifyListeners();
    }
  }

  Future<ListDiffs<T>> removeAt(int index, {@required bool resetQuery}) async {
    return await _applyDiff((_chips) {
      _chips.removeAt(index);
    }, source: ChipChangeOperation.deleteChip, resetQuery: resetQuery);
  }

  Future<ListDiffs<T>> deleteChip(T data, {@required bool resetQuery}) async {
    return await _applyDiff((_chips) {
      _chips.remove(data);
    }, resetQuery: resetQuery, source: ChipChangeOperation.deleteChip);
  }

  Future acceptSuggestion({T suggestion}) async {
    if (suggestionToken != null) {
      final _currentSuggestion = suggestion ?? this.suggestion.item;
      this.suggestion = Suggestion.empty();
      if (_currentSuggestion != null) {
        await addChip(_currentSuggestion, resetQuery: true);
      }
    }
  }

  Future<ListDiffs<T>> _applyDiff(void mutation(List<T> copy),
      {@required ChipChangeOperation source, bool notify = true, @required bool resetQuery}) async {
    resetQuery ??= false;
    if (!enabled) return ListDiffs.empty();

    final copy = [...this.chips];
    mutation(copy);
    final diffs = await this.chips.sync(copy);
    _log.info("Chip diffs: ${diffs.summary}");
    if (diffs.isNotEmpty || resetQuery) {
      /// Reset query if we've changed chips, right?
      await resetSuggestions();
      if (notify) notifyListeners();
    }
    _diffs.add(ChipsDiff(diffs, source));
    return diffs;
  }

  Future<ListDiffs<T>> addChip(T data, {@required bool resetQuery}) async {
    resetQuery ??= false;
    final result = await _applyDiff((_chips) {
      _chips.add(data);
    }, source: ChipChangeOperation.addChip, resetQuery: resetQuery);

    return result;
  }

  Future<ListDiffs<T>> syncChips(Iterable<T> newChips,
      {bool notify = true, bool resetQuery, @required ChipChangeOperation source}) async {
    final changed = await _applyDiff((_chips) {
      _chips.clear();
      _chips.addAll(newChips);
    }, resetQuery: resetQuery, source: source, notify: notify);

    return changed;
  }

  Future<ListDiffs<T>> addAll(Iterable<T> values, bool resetQuery, {@required ChipChangeOperation source}) async {
    return await _applyDiff((_chips) {
      values?.forEach((v) => _chips.add(v));
    }, source: source, resetQuery: resetQuery);
  }

  resetSuggestions() async {
    suggestion = const Suggestion.empty();
    await _query.update(() => "");
    _suggestions.current = ChipSuggestions.empty();
    notifyListeners();
  }

  Future<ListDiffs<T>> pop({@required ChipChangeOperation source, @required bool resetQuery}) {
    return _applyDiff((_chips) {
      _chips.removeLast();
    }, resetQuery: resetQuery, source: source);
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

  requestKeyboard() => _requestKeyboard?.call();

  hideKeyboard() => _hideKeyboard?.call();

  set requestKeyboardCallback(VoidCallback callback) => this._requestKeyboard = callback;

  set hideKeyboardCallback(VoidCallback callback) => this._hideKeyboard = callback;
}

enum ControllerStatus { open, closed, opening }
