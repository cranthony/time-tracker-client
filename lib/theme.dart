import 'package:flutter/material.dart';

/// The app's theme for [brightness]. Shared by the app and its visual tests
/// (test/visual), so what they render is what the app shows.
ThemeData appTheme(Brightness brightness) =>
    ThemeData(colorSchemeSeed: Colors.teal, brightness: brightness);
