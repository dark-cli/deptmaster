import 'package:flutter/material.dart';

/// Shape system following Material Design 3 guidelines
class AppShapes {
  AppShapes._(); // Private constructor to prevent instantiation

  // Border radius values
  static const double small = 4.0;
  static const double medium = 8.0;
  static const double large = 12.0;
  static const double extraLarge = 16.0;
  static const double round = 28.0; // For FAB and chips

  // Shape definitions
  static BorderRadius get smallRadius => BorderRadius.circular(small);
  static BorderRadius get mediumRadius => BorderRadius.circular(medium);
  static BorderRadius get largeRadius => BorderRadius.circular(large);
  static BorderRadius get extraLargeRadius => BorderRadius.circular(extraLarge);
  static BorderRadius get roundRadius => BorderRadius.circular(round);

  // Component-specific shapes
  static BorderRadius get cardRadius => largeRadius; // 12dp
  static BorderRadius get buttonRadius => mediumRadius; // 8dp
  static BorderRadius get textFieldRadius => smallRadius; // 4dp
  static BorderRadius get fabRadius => extraLargeRadius; // 16dp
  static BorderRadius get chipRadius => mediumRadius; // 8dp
  static BorderRadius get dialogRadius => largeRadius; // 12dp
}
