part of 'chat_page.dart';

extension _ChatPageMobileSupport on _ChatPageState {
  Widget _wrapWithMobileKeyboardDismiss(Widget child) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _dismissKeyboardIfTapIsOutsideFocusedRegion(event.position);
      },
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
}
