class ChipSuggestions<T> {
  final List<T> suggestions;
  final T match;

  const ChipSuggestions({this.suggestions, this.match});
  static empty<T>() => ChipSuggestions<T>(suggestions: []);
}
