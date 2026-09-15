import 'package:flutter/material.dart';

/// Pops back to the home screen. Room screens leave the room in their
/// `PopScope` callback.
void goHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}
