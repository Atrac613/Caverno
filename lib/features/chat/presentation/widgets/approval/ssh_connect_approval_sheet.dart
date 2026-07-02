import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../providers/chat_state.dart';

class SshConnectApprovalSheet extends StatefulWidget {
  const SshConnectApprovalSheet({required this.pending, super.key});

  final PendingSshConnect pending;

  static Future<SshConnectApproval?> show(
    BuildContext context,
    PendingSshConnect pending,
  ) {
    return showModalBottomSheet<SshConnectApproval>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SshConnectApprovalSheet(pending: pending),
    );
  }

  @override
  State<SshConnectApprovalSheet> createState() =>
      _SshConnectApprovalSheetState();
}

class _SshConnectApprovalSheetState extends State<SshConnectApprovalSheet> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late bool _savePassword;
  bool _obscure = true;

  bool get _hasSavedHint => widget.pending.savedPassword != null;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.pending.host);
    _portController = TextEditingController(
      text: widget.pending.port.toString(),
    );
    _usernameController = TextEditingController(text: widget.pending.username);
    _passwordController = TextEditingController(
      text: widget.pending.savedPassword ?? '',
    );
    _savePassword = widget.pending.savedPassword != null;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.terminal_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SSH Connection',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Authenticate to remote server',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, null),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                // Form fields
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      // Host & Port in a row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _hostController,
                              decoration: InputDecoration(
                                labelText: 'Host',
                                prefixIcon: const Icon(
                                  Icons.dns_rounded,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: theme
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.outline.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Port',
                                filled: true,
                                fillColor: theme
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.outline.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(
                            Icons.person_rounded,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _hasSavedHint ? '(saved)' : null,
                          prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Save password toggle
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            secondary: Icon(
                              Icons.save_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              'Save password',
                              style: theme.textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              'Store in secure keychain',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            value: _savePassword,
                            onChanged: (v) => setState(() => _savePassword = v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                // Bottom action buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text('common.cancel'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _approve,
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: const Text('Connect'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _approve() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 22;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (host.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Host, username and password are required'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      SshConnectApproval(
        host: host,
        port: port,
        username: username,
        password: password,
        savePassword: _savePassword,
      ),
    );
  }
}
