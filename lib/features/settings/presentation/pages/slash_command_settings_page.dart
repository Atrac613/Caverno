import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/custom_slash_commands_notifier.dart';
import '../../../chat/presentation/slash_commands/slash_command.dart';
import '../../../chat/presentation/slash_commands/slash_command_prompt_template.dart';

enum _SlashCommandTemplateAction { edit, delete }

class SlashCommandSettingsPage extends ConsumerWidget {
  const SlashCommandSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(customSlashCommandsNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings.slash_commands_title'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('slash-command-add'),
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text('settings.slash_command_add'.tr()),
      ),
      body: templates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'settings.slash_command_empty'.tr(),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              itemCount: templates.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final template = templates[index];
                return ListTile(
                  key: ValueKey('slash-command-template-${template.id}'),
                  leading: const Icon(Icons.terminal_outlined),
                  title: Text('/${template.name}'),
                  subtitle: Text(template.description),
                  trailing: PopupMenuButton<_SlashCommandTemplateAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _SlashCommandTemplateAction.edit:
                          _showEditor(context, ref, template: template);
                          break;
                        case _SlashCommandTemplateAction.delete:
                          _confirmDelete(context, ref, template);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _SlashCommandTemplateAction.edit,
                        child: Row(
                          children: [
                            const Icon(Icons.edit_outlined),
                            const SizedBox(width: 12),
                            Text('common.edit'.tr()),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: _SlashCommandTemplateAction.delete,
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline),
                            const SizedBox(width: 12),
                            Text('common.delete'.tr()),
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

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref, {
    SlashCommandPromptTemplate? template,
  }) async {
    final result = await showDialog<SlashCommandPromptTemplate>(
      context: context,
      builder: (context) => _SlashCommandTemplateDialog(template: template),
    );
    if (result == null) return;

    try {
      await ref
          .read(customSlashCommandsNotifierProvider.notifier)
          .upsert(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.slash_command_saved'.tr())),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'settings.slash_command_save_failed'.tr(
                namedArgs: {'error': error.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SlashCommandPromptTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.slash_command_delete_title'.tr()),
        content: Text(
          'settings.slash_command_delete_confirm'.tr(
            namedArgs: {'command': '/${template.name}'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref
        .read(customSlashCommandsNotifierProvider.notifier)
        .remove(template.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.slash_command_deleted'.tr())),
      );
    }
  }
}

class _SlashCommandTemplateDialog extends StatefulWidget {
  const _SlashCommandTemplateDialog({this.template});

  final SlashCommandPromptTemplate? template;

  @override
  State<_SlashCommandTemplateDialog> createState() =>
      _SlashCommandTemplateDialogState();
}

class _SlashCommandTemplateDialogState
    extends State<_SlashCommandTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _aliasesController;
  late final TextEditingController _argumentHintController;
  late final TextEditingController _templateController;
  late SlashCommandArgumentRequirement _argumentRequirement;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _nameController = TextEditingController(text: template?.name ?? '');
    _descriptionController = TextEditingController(
      text: template?.description ?? '',
    );
    _aliasesController = TextEditingController(
      text: template?.aliases.join(', ') ?? '',
    );
    _argumentHintController = TextEditingController(
      text: template?.argumentHint ?? '<input>',
    );
    _templateController = TextEditingController(
      text: template?.template ?? slashCommandPromptArgumentPlaceholder,
    );
    _argumentRequirement =
        template?.argumentRequirement ??
        SlashCommandArgumentRequirement.required;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _aliasesController.dispose();
    _argumentHintController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.template == null
            ? 'settings.slash_command_add'.tr()
            : 'settings.slash_command_edit'.tr(),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('slash-command-name-field'),
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'settings.slash_command_name'.tr(),
                    prefixText: '/',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('slash-command-description-field'),
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'settings.slash_command_description'.tr(),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('slash-command-aliases-field'),
                  controller: _aliasesController,
                  decoration: InputDecoration(
                    labelText: 'settings.slash_command_aliases'.tr(),
                    helperText: 'settings.slash_command_aliases_helper'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SlashCommandArgumentRequirement>(
                  key: const ValueKey('slash-command-argument-field'),
                  initialValue: _argumentRequirement,
                  decoration: InputDecoration(
                    labelText: 'settings.slash_command_arguments'.tr(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: SlashCommandArgumentRequirement.required,
                      child: Text('settings.slash_command_arg_required'.tr()),
                    ),
                    DropdownMenuItem(
                      value: SlashCommandArgumentRequirement.optional,
                      child: Text('settings.slash_command_arg_optional'.tr()),
                    ),
                    DropdownMenuItem(
                      value: SlashCommandArgumentRequirement.none,
                      child: Text('settings.slash_command_arg_none'.tr()),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _argumentRequirement = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('slash-command-hint-field'),
                  controller: _argumentHintController,
                  decoration: InputDecoration(
                    labelText: 'settings.slash_command_argument_hint'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('slash-command-template-field'),
                  controller: _templateController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    alignLabelWithHint: true,
                    labelText: 'settings.slash_command_template'.tr(),
                    helperText: 'settings.slash_command_template_helper'.tr(),
                  ),
                  validator: _requiredValidator,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('slash-command-save'),
          onPressed: _submit,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'settings.slash_command_required_field'.tr();
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final argumentHint = _argumentHintController.text.trim();
    final resolvedArgumentHint =
        _argumentRequirement == SlashCommandArgumentRequirement.none
        ? null
        : (argumentHint.isEmpty ? '<input>' : argumentHint);
    Navigator.of(context).pop(
      SlashCommandPromptTemplate(
        id:
            widget.template?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        aliases: _aliasesController.text
            .split(',')
            .map((alias) => alias.trim())
            .where((alias) => alias.isNotEmpty)
            .toList(growable: false),
        argumentHint: resolvedArgumentHint,
        argumentRequirement: _argumentRequirement,
        template: _templateController.text,
      ),
    );
  }
}
