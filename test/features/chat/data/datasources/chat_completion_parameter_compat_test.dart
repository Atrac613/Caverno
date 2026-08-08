import 'package:caverno/features/chat/data/datasources/chat_completion_parameter_compat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart';

void main() {
  group('ChatCompletionParameterCompat', () {
    test('switches to max_completion_tokens on the OpenAI GPT-5 rejection', () {
      final compat = ChatCompletionParameterCompat();

      final changed = compat.absorb(
        const BadRequestException(
          message:
              "Unsupported parameter: 'max_tokens' is not supported with this "
              "model. Use 'max_completion_tokens' instead.",
          param: 'max_tokens',
        ),
      );

      expect(changed, isTrue);
      expect(compat.useMaxCompletionTokens, isTrue);
      expect(compat.omitTemperature, isFalse);
    });

    test('absorbs the rejection without structured param fields', () {
      final compat = ChatCompletionParameterCompat();

      expect(
        compat.absorb(
          const BadRequestException(
            message:
                "Unsupported parameter: 'max_tokens' is not supported with "
                "this model. Use 'max_completion_tokens' instead.",
          ),
        ),
        isTrue,
      );
      expect(compat.useMaxCompletionTokens, isTrue);
    });

    test('drops temperature when the server rejects the value', () {
      final compat = ChatCompletionParameterCompat();

      expect(
        compat.absorb(
          const BadRequestException(
            message:
                "Unsupported value: 'temperature' does not support 0.2 with "
                'this model. Only the default (1) value is supported.',
            param: 'temperature',
          ),
        ),
        isTrue,
      );
      expect(compat.omitTemperature, isTrue);
      expect(compat.useMaxCompletionTokens, isFalse);
    });

    test('pins reasoning effort to none when tools conflict with it', () {
      final compat = ChatCompletionParameterCompat();

      expect(
        compat.absorb(
          const BadRequestException(
            message:
                'Function tools with reasoning_effort are not supported for '
                'gpt-5.6-luna in /v1/chat/completions. To use function tools, '
                "use /v1/responses or set reasoning_effort to 'none'.",
          ),
        ),
        isTrue,
      );
      expect(compat.forceReasoningEffortNone, isTrue);
      expect(compat.useMaxCompletionTokens, isFalse);
      expect(compat.omitTemperature, isFalse);
    });

    test('leaves reasoning effort alone for unrelated reasoning errors', () {
      final compat = ChatCompletionParameterCompat();

      expect(
        compat.absorb(
          const BadRequestException(
            message: 'Unrecognized request argument: reasoning_effort',
            param: 'reasoning_effort',
          ),
        ),
        isFalse,
      );
      expect(compat.forceReasoningEffortNone, isFalse);
    });

    test('reports no change once a quirk is already recorded', () {
      final compat = ChatCompletionParameterCompat();
      const error = BadRequestException(
        message:
            "Unsupported parameter: 'max_tokens' ... use "
            "'max_completion_tokens' instead.",
        param: 'max_tokens',
      );

      expect(compat.absorb(error), isTrue);
      expect(compat.absorb(error), isFalse);
    });

    test('ignores unrelated bad requests and non-400 failures', () {
      final compat = ChatCompletionParameterCompat();

      expect(
        compat.absorb(
          const BadRequestException(message: 'model not found', param: 'model'),
        ),
        isFalse,
      );
      expect(
        compat.absorb(
          const ApiException(
            message: "'max_tokens' unsupported, use 'max_completion_tokens'",
            statusCode: 500,
          ),
        ),
        isFalse,
      );
      expect(compat.useMaxCompletionTokens, isFalse);
      expect(compat.omitTemperature, isFalse);
    });
  });
}
