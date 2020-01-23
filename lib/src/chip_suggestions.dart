import 'package:flutter/foundation.dart';
import 'package:sunny_dart/helpers.dart';
import 'package:sunny_dart/sunny_dart.dart';

class ChipSuggestions<T> {
  final List<T> suggestions;
  final Suggestion<T> match;

  const ChipSuggestions({this.suggestions, this.match});
  const ChipSuggestions.empty()
      : suggestions = const [],
        match = null;
}

class Suggestion<T> {
  final T item;
  final String highlightText;

  const Suggestion.highlighted({
    @required this.item,
    @required this.highlightText,
  });

  const Suggestion._({
    @required this.item,
    @required this.highlightText,
  });

  const Suggestion({
    @required this.item,
  }) : highlightText = null;

  const Suggestion.empty()
      : item = null,
        highlightText = null;

  bool get isNotEmpty => item != null;
  bool get isEmpty => item == null;

  Suggestion copy({
    T suggestion,
    String highlightText,
  }) {
    return Suggestion._(
      item: suggestion ?? this.item,
      highlightText: highlightText ?? this.highlightText,
    );
  }

  @override
  String toString() {
    if (isEmpty) {
      return 'Suggestion{ empty }';
    } else {
      return buildString((str) {
        str += "Suggestion{ item: $item";
        if (highlightText.isNotNullOrBlank) str += ", highlight: $highlightText";
        str += " }";
      });
    }
  }
}
