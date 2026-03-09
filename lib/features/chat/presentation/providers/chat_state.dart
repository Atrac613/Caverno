import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/message.dart';

part 'chat_state.freezed.dart';

@freezed
abstract class ChatState with _$ChatState {
  const factory ChatState({
    required List<Message> messages,
    required bool isLoading,
    String? error,
  }) = _ChatState;

  factory ChatState.initial() =>
      const ChatState(messages: [], isLoading: false);
}
