import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../providers/conversations_notifier.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showDeleteConversationDialog(
    BuildContext context,
    ConversationsNotifier conversationsNotifier,
    String conversationId,
    String conversationTitle,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('chat.delete_title'.tr()),
        content: Text('chat.delete_confirm'.tr(namedArgs: {'title': conversationTitle})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await conversationsNotifier.deleteConversation(conversationId);
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.deleted'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );

    // Scroll when the message list changes.
    ref.listen(chatNotifierProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          (next.messages.isNotEmpty && next.messages.last.isStreaming)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    });

    // SSH connect confirmation dialog.
    ref.listen<PendingSshConnect?>(
      chatNotifierProvider.select((s) => s.pendingSshConnect),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showSshConnectDialog(context, next);
        }
      },
    );

    // SSH per-command confirmation dialog.
    ref.listen<PendingSshCommand?>(
      chatNotifierProvider.select((s) => s.pendingSshCommand),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showSshCommandDialog(context, next);
        }
      },
    );

    final currentConversation = conversationsState.currentConversation;
    final rawTitle = currentConversation?.title ?? 'Caverno';
    final currentTitle = rawTitle == defaultConversationTitle
        ? 'chat.new_conversation'.tr()
        : rawTitle;

    final settings = ref.watch(settingsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(child: Text(currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (settings.demoMode) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text('chat.demo_banner'.tr()),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => conversationsNotifier.createNewConversation(),
            icon: const Icon(Icons.add),
            tooltip: 'chat.new_conversation'.tr(),
          ),
          if (currentConversation != null)
            IconButton(
              onPressed: () => _showDeleteConversationDialog(
                context,
                conversationsNotifier,
                currentConversation.id,
                currentConversation.title,
              ),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'chat.delete_current'.tr(),
            ),
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
            icon: const Icon(Icons.settings),
            tooltip: 'chat.settings'.tr(),
          ),
        ],
      ),
      drawer: const ConversationDrawer(),
      body: Column(
        children: [
          // Error banner
          if (chatState.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Message list
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: chatState.messages[index]);
                    },
                  ),
          ),
          // Token usage indicator
          if (chatState.totalTokens > 0)
            _buildTokenUsageBar(context, chatState),
          // Input area
          MessageInput(
            onSend: (message, imageBase64, imageMimeType) =>
                chatNotifier.sendMessage(
                  message,
                  imageBase64: imageBase64,
                  imageMimeType: imageMimeType,
                  languageCode: context.locale.languageCode,
                ),
            onCancel: () => chatNotifier.cancelStreaming(),
            isLoading: chatState.isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildTokenUsageBar(BuildContext context, ChatState chatState) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            Icons.token_outlined,
            size: 14,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            'chat.token_usage'.tr(
              namedArgs: {
                'prompt': _formatTokenCount(chatState.promptTokens),
                'completion': _formatTokenCount(chatState.completionTokens),
                'total': _formatTokenCount(chatState.totalTokens),
              },
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTokenCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  Future<void> _showSshConnectDialog(
    BuildContext context,
    PendingSshConnect pending,
  ) async {
    final hostController = TextEditingController(text: pending.host);
    final portController =
        TextEditingController(text: pending.port.toString());
    final usernameController = TextEditingController(text: pending.username);
    final passwordController =
        TextEditingController(text: pending.savedPassword ?? '');
    var savePassword = pending.savedPassword != null;
    var obscure = true;
    final hasSavedHint = pending.savedPassword != null;

    final approval = await showDialog<SshConnectApproval>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('SSH connect'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                      ),
                    ),
                    TextField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                      ),
                    ),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                      ),
                    ),
                    TextField(
                      controller: passwordController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: hasSavedHint ? '(saved)' : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Save password for this host'),
                      value: savePassword,
                      onChanged: (v) =>
                          setState(() => savePassword = v ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: Text('common.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () {
                    final host = hostController.text.trim();
                    final port =
                        int.tryParse(portController.text.trim()) ?? 22;
                    final username = usernameController.text.trim();
                    final password = passwordController.text;
                    if (host.isEmpty ||
                        username.isEmpty ||
                        password.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Host, username and password are required',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      SshConnectApproval(
                        host: host,
                        port: port,
                        username: username,
                        password: password,
                        savePassword: savePassword,
                      ),
                    );
                  },
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );

    hostController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();

    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshConnect(id: pending.id, approval: approval);
  }

  Future<void> _showSshCommandDialog(
    BuildContext context,
    PendingSshCommand pending,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Run command on ${pending.username}@${pending.host}?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending.reason != null && pending.reason!.isNotEmpty) ...[
                  Text(
                    'Reason: ${pending.reason}',
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    pending.command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Deny'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );

    ref.read(chatNotifierProvider.notifier).resolveSshCommand(
          id: pending.id,
          approved: approved ?? false,
        );
  }

  Widget _buildEmptyState(BuildContext context) {
    final emptySettings = ref.watch(settingsNotifierProvider);
    final isDefault = emptySettings.baseUrl == ApiConstants.defaultBaseUrl &&
        !emptySettings.demoMode;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDefault ? Icons.settings_suggest : Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            if (isDefault) ...[
              Text(
                'chat.setup_title'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'chat.setup_message'.tr(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref.read(settingsNotifierProvider.notifier).updateDemoMode(true);
                },
                icon: const Icon(Icons.play_arrow),
                label: Text('chat.try_demo'.tr()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
                icon: const Icon(Icons.settings),
                label: Text('chat.setup_button'.tr()),
              ),
            ] else
              Text(
                'chat.empty_state'.tr(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
