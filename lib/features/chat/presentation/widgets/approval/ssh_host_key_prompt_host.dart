import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ssh_host_key_prompt_controller.dart';
import 'ssh_host_key_approval_sheet.dart';

/// Listens for SSH host-key prompts outside ChatPage so the page library
/// ratchet does not grow.
class SshHostKeyPromptHost extends ConsumerWidget {
  const SshHostKeyPromptHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sshHostKeyPromptControllerProvider, (previous, next) {
      if (next == null || previous?.id == next.id) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) {
          ref.read(sshHostKeyPromptControllerProvider.notifier).resolve(false);
          return;
        }
        final accepted = await SshHostKeyApprovalSheet.show(
          context,
          next.decision,
        );
        if (!context.mounted) {
          ref.read(sshHostKeyPromptControllerProvider.notifier).resolve(false);
          return;
        }
        ref
            .read(sshHostKeyPromptControllerProvider.notifier)
            .resolve(accepted ?? false);
      });
    });
    return child;
  }
}
