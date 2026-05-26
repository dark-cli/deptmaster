import 'package:flutter/material.dart';

@immutable
class CustomAppColorsExtension extends ThemeExtension<CustomAppColorsExtension> {
  const CustomAppColorsExtension({
    required this.success,
    required this.warning,
    required this.lightGive,
    required this.lightReceived,
    required this.darkGive,
    required this.darkReceived,
  });

  final Color? success;
  final Color? warning;
  final Color? lightGive;
  final Color? lightReceived;
  final Color? darkGive;
  final Color? darkReceived;

  @override
  CustomAppColorsExtension copyWith({
    Color? success,
    Color? warning,
    Color? lightGive,
    Color? lightReceived,
    Color? darkGive,
    Color? darkReceived,
  }) {
    return CustomAppColorsExtension(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      lightGive: lightGive ?? this.lightGive,
      lightReceived: lightReceived ?? this.lightReceived,
      darkGive: darkGive ?? this.darkGive,
      darkReceived: darkReceived ?? this.darkReceived,
    );
  }

  @override
  CustomAppColorsExtension lerp(
      covariant ThemeExtension<CustomAppColorsExtension>? other, double t) {
    if (other is! CustomAppColorsExtension) {
      return this;
    }
    return CustomAppColorsExtension(
      success: Color.lerp(success, other.success, t),
      warning: Color.lerp(warning, other.warning, t),
      lightGive: Color.lerp(lightGive, other.lightGive, t),
      lightReceived: Color.lerp(lightReceived, other.lightReceived, t),
      darkGive: Color.lerp(darkGive, other.darkGive, t),
      darkReceived: Color.lerp(darkReceived, other.darkReceived, t),
    );
  }
}
