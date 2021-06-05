import 'package:flutter_google_places_sdk_platform_interface/src/types/time_of_week.dart';
import 'package:flutter_google_places_sdk_platform_interface/src/types/utils.dart';

class Period {
  const Period({this.open, this.close});

  final TimeOfWeek? open;
  final TimeOfWeek? close;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Period &&
              runtimeType == other.runtimeType &&
              open == other.open &&
              close == other.close;

  @override
  int get hashCode => open.hashCode ^ close.hashCode;

  @override
  String toString() => 'Period{open: $open, close: $close}';

  Map<String, dynamic> toMap() => {'open': open, 'close': close};

  static Period fromMap(Map<String, dynamic> map) => Period(
    open: TimeOfWeek.fromMap(toJsonMap(map['open'])),
    close: TimeOfWeek.fromMap(toJsonMap(map['close'])),
  );
}
