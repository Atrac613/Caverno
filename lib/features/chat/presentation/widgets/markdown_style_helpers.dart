import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

TableBorder markdownTableBorder(ThemeData theme) {
  final side = markdownTableBorderSide(theme);
  return TableBorder.all(color: side.color, width: side.width);
}

BorderSide markdownTableBorderSide(ThemeData theme) {
  final appColors = theme.extension<AppSemanticColors>();
  return BorderSide(
    color: appColors?.hairlineStrong ?? theme.colorScheme.outline,
    width: 0.5,
  );
}
