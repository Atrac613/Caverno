import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Dismisses the soft keyboard when a touch lands outside the focused field.
///
/// Phones only: desktop and web keep the caret where the user put it, and a
/// pointer-down there is a click, not a "done typing" gesture. The listener is
/// translucent so the tap still reaches whatever was under it.
Widget wrapWithMobileKeyboardDismiss(Widget child) {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
    return child;
  }
  return Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) =>
        _dismissKeyboardIfTapIsOutsideFocusedRegion(event.position),
    child: child,
  );
}

void _dismissKeyboardIfTapIsOutsideFocusedRegion(Offset position) {
  final primaryFocus = FocusManager.instance.primaryFocus;
  if (primaryFocus == null || !primaryFocus.hasFocus) {
    return;
  }

  final focusContext = primaryFocus.context;
  final renderObject = focusContext?.findRenderObject();
  if (renderObject is RenderBox && renderObject.attached) {
    final focusedRect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
    if (focusedRect.contains(position)) {
      return;
    }
  }

  primaryFocus.unfocus();
}
