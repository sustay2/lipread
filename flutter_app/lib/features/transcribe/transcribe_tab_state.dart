import 'package:flutter/foundation.dart';

/// Global state so nav bar and transcribe widgets can talk.
///
/// When the Transcribe tab is active, this should be true.
/// When any other tab is active, this should be false.
class TranscribeTabState {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);
}