import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/ssh_auth_credential.dart';
import '../../providers/chat_state.dart';

/// Connect-dialog authentication choices.
///
/// Password used to be the only path, and `Connect` refused to close while the
/// password box was empty. Key-authenticated hosts therefore had no way out of
/// the sheet except Cancel, which the tool reported to the model as "User
/// cancelled SSH connection" — so the method is now explicit and each method
/// validates only the fields it actually needs.
enum _AuthChoice { password, privateKey }

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
  late final TextEditingController _keyPathController;
  late final TextEditingController _passphraseController;
  late _AuthChoice _authChoice;
  late bool _remember;
  bool _obscure = true;

  bool get _hasSavedHint => widget.pending.savedCredential != null;

  @override
  void initState() {
    super.initState();
    final saved = widget.pending.savedCredential;
    _hostController = TextEditingController(text: widget.pending.host);
    _portController = TextEditingController(
      text: widget.pending.port.toString(),
    );
    _usernameController = TextEditingController(text: widget.pending.username);
    _passwordController = TextEditingController(
      text: saved is SshPasswordCredential ? saved.password : '',
    );
    // A saved key wins over a resolved candidate; otherwise the best candidate
    // (this host's `~/.ssh/config` identity, else the strongest default key)
    // is pre-filled so the common "this host already trusts my key" case needs
    // no typing.
    final defaultIdentity = widget.pending.identityCandidates.firstOrNull;
    _keyPathController = TextEditingController(
      text: saved is SshPrivateKeyCredential
          ? saved.keyPath
          : defaultIdentity ?? '',
    );
    _passphraseController = TextEditingController(
      text: saved is SshPrivateKeyCredential ? saved.passphrase ?? '' : '',
    );
    _authChoice = switch (saved) {
      SshPrivateKeyCredential() => _AuthChoice.privateKey,
      SshPasswordCredential() => _AuthChoice.password,
      null => defaultIdentity == null
          ? _AuthChoice.password
          : _AuthChoice.privateKey,
    };
    _remember = saved != null;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _keyPathController.dispose();
    _passphraseController.dispose();
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
                _DragHandle(theme: theme),
                _Header(theme: theme),
                const Divider(height: 24),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _field(
                              theme,
                              controller: _hostController,
                              label: 'Host',
                              icon: Icons.dns_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              theme,
                              controller: _portController,
                              label: 'Port',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _field(
                        theme,
                        controller: _usernameController,
                        label: 'Username',
                        icon: Icons.person_rounded,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<_AuthChoice>(
                        segments: const [
                          ButtonSegment(
                            value: _AuthChoice.password,
                            label: Text('Password'),
                            icon: Icon(Icons.lock_rounded, size: 18),
                          ),
                          ButtonSegment(
                            value: _AuthChoice.privateKey,
                            label: Text('Private key'),
                            icon: Icon(Icons.key_rounded, size: 18),
                          ),
                        ],
                        selected: {_authChoice},
                        onSelectionChanged: (selection) =>
                            setState(() => _authChoice = selection.first),
                      ),
                      const SizedBox(height: 16),
                      if (_authChoice == _AuthChoice.password)
                        ..._passwordFields(theme)
                      else
                        ..._privateKeyFields(theme),
                      const SizedBox(height: 8),
                      _rememberToggle(theme),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                _Actions(theme: theme, onApprove: _approve),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _passwordFields(ThemeData theme) => [
    _field(
      theme,
      controller: _passwordController,
      label: 'Password',
      icon: Icons.lock_rounded,
      helperText: _hasSavedHint ? '(saved)' : null,
      obscureText: _obscure,
      suffix: IconButton(
        icon: Icon(
          _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  ];

  List<Widget> _privateKeyFields(ThemeData theme) => [
    _field(
      theme,
      controller: _keyPathController,
      label: 'Private key file',
      icon: Icons.key_rounded,
      helperText: _hasSavedHint ? '(saved)' : null,
      suffix: IconButton(
        icon: const Icon(Icons.folder_open_rounded),
        tooltip: 'Choose key file',
        onPressed: _pickKeyFile,
      ),
    ),
    const SizedBox(height: 16),
    _field(
      theme,
      controller: _passphraseController,
      label: 'Key passphrase (optional)',
      icon: Icons.password_rounded,
      obscureText: _obscure,
      suffix: IconButton(
        icon: Icon(
          _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  ];

  Widget _rememberToggle(ThemeData theme) {
    final isKey = _authChoice == _AuthChoice.privateKey;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          secondary: Icon(
            Icons.save_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            isKey ? 'Remember this key' : 'Save password',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            isKey
                ? 'Stores the key path and passphrase, never the key itself'
                : 'Store in secure keychain',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          value: _remember,
          onChanged: (v) => setState(() => _remember = v),
        ),
      ),
    );
  }

  Widget _field(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    IconData? icon,
    String? helperText,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: border(
          theme.colorScheme.outline.withValues(alpha: 0.2),
          1,
        ),
        focusedBorder: border(theme.colorScheme.primary, 1.5),
      ),
    );
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.pickFiles();
    final path = result?.files.singleOrNull?.path;
    if (path == null || !mounted) return;
    setState(() => _keyPathController.text = path);
  }

  void _approve() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 22;
    final username = _usernameController.text.trim();
    if (host.isEmpty || username.isEmpty) {
      _reject('Host and username are required');
      return;
    }
    final SshAuthCredential credential;
    if (_authChoice == _AuthChoice.password) {
      final password = _passwordController.text;
      if (password.isEmpty) {
        _reject('Enter a password, or switch to Private key');
        return;
      }
      credential = SshPasswordCredential(password);
    } else {
      final keyPath = _keyPathController.text.trim();
      if (keyPath.isEmpty) {
        _reject('Choose a private key file');
        return;
      }
      final passphrase = _passphraseController.text;
      credential = SshPrivateKeyCredential(
        keyPath: keyPath,
        passphrase: passphrase.isEmpty ? null : passphrase,
      );
    }
    Navigator.pop(
      context,
      SshConnectApproval(
        host: host,
        port: port,
        username: username,
        credential: credential,
        remember: _remember,
      ),
    );
  }

  void _reject(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
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
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.theme, required this.onApprove});

  final ThemeData theme;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) => Padding(
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
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Text('common.cancel'.tr()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: onApprove,
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
  );
}
