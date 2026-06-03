// Same-library extension on [_ChatPageState]. The State base class marks
// `setState`/`context` as `@protected`, which the analyzer flags even for
// extensions within the same library; the ignore here suppresses that noise.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPageEmptyStateBuilders on _ChatPageState {
  Widget _buildCodingProjectEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'chat.coding_no_project_title'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'chat.coding_no_project_message'.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickAndActivateProject,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text('chat.add_project'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool isCodingWorkspace,
  }) {
    final emptySettings = ref.watch(settingsNotifierProvider);
    final isDefault =
        emptySettings.baseUrl == ApiConstants.defaultBaseUrl &&
        !emptySettings.demoMode;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDefault ? Icons.settings_suggest : Icons.chat_bubble_outline,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              if (isDefault && !isCodingWorkspace) ...[
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
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateDemoMode(true);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text('chat.try_demo'.tr()),
                ),
              ] else
                Text(
                  isCodingWorkspace
                      ? 'chat.coding_empty_state'.tr()
                      : 'chat.empty_state'.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
