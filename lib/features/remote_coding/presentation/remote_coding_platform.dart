import 'dart:io';

import 'package:flutter/foundation.dart';

bool isRemoteCodingMobileRuntimePlatform() =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
