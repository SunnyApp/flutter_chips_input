import 'package:collection_diff/list_diff_model.dart';
import 'package:flutter_chips_input_sunny/flutter_chips_input.dart';

class ChipsDiff<V> {
  final ListDiffs<V> diffs;
  final ChipChangeOperation source;

  ChipsDiff(this.diffs, this.source);
}
