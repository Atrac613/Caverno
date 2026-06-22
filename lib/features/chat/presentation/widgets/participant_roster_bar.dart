import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/conversation_participant.dart';
import '../../domain/services/participant_turn_coordinator.dart';
import '../providers/chat_state.dart';

typedef ParticipantRosterChanged =
    FutureOr<void> Function({
      required List<ConversationParticipant> participants,
      required ParticipantTurnConfig config,
    });

const _participantPalette = <int>[
  0xFF6750A4,
  0xFF006A6A,
  0xFFB3261E,
  0xFF7D5700,
  0xFF386A20,
  0xFF5D5FEF,
  0xFF984061,
  0xFF3A608F,
];

class ParticipantRosterBar extends StatelessWidget {
  const ParticipantRosterBar({
    super.key,
    required this.participants,
    required this.config,
    required this.endpoints,
    required this.primaryModel,
    required this.onChanged,
    this.enabled = true,
    this.runtime,
    this.onStopRequested,
    this.onContinueRequested,
  });

  final List<ConversationParticipant> participants;
  final ParticipantTurnConfig config;
  final List<NamedEndpoint> endpoints;
  final String primaryModel;
  final ParticipantRosterChanged onChanged;
  final bool enabled;
  final ParticipantTurnRuntime? runtime;
  final VoidCallback? onStopRequested;
  final VoidCallback? onContinueRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orderedParticipants = const ParticipantTurnCoordinator()
        .orderedEnabledOrDisabled(participants);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: orderedParticipants.isEmpty
            ? _EmptyRosterButton(
                enabled: enabled,
                onPressed: () => _showParticipantSheet(context),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_2_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    for (final participant in orderedParticipants) ...[
                      _ParticipantChip(
                        participant: participant,
                        enabled: enabled,
                        onPressed: () => _showParticipantSheet(
                          context,
                          participant: participant,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Tooltip(
                      message: 'Add participant',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        onPressed: enabled
                            ? () => _showParticipantSheet(context)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TurnDepthControl(
                      config: config,
                      enabled: enabled,
                      onChanged: (nextConfig) => _emitChange(
                        participants: participants,
                        config: nextConfig,
                      ),
                    ),
                    if (runtime != null) ...[
                      const SizedBox(width: 8),
                      _ParticipantRuntimeControl(
                        runtime: runtime!,
                        onStopRequested: onStopRequested,
                        onContinueRequested: onContinueRequested,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _showParticipantSheet(
    BuildContext context, {
    ConversationParticipant? participant,
  }) async {
    if (!enabled) return;
    final isNew = participant == null;
    final draft = participant ?? _newParticipantDraft();
    final result = await showModalBottomSheet<_ParticipantEditorResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ParticipantEditorSheet(
        participant: draft,
        endpoints: endpoints,
        primaryModel: primaryModel,
        isNew: isNew,
      ),
    );
    if (result == null) return;

    if (result.removeParticipant) {
      final nextParticipants = participants
          .where((item) => item.id != result.participant.id)
          .toList(growable: false);
      await _emitChange(participants: nextParticipants, config: config);
      return;
    }

    final existingIndex = participants.indexWhere(
      (item) => item.id == result.participant.id,
    );
    final nextParticipants = [...participants];
    if (existingIndex >= 0) {
      nextParticipants[existingIndex] = result.participant;
    } else {
      nextParticipants.add(result.participant);
    }
    await _emitChange(participants: nextParticipants, config: config);
  }

  ConversationParticipant _newParticipantDraft() {
    final nextOrder = participants.isEmpty
        ? 1
        : participants.map((item) => item.order).reduce(math.max) + 1;
    final endpointId = endpoints.isEmpty ? '' : endpoints.first.id;
    final colorValue =
        _participantPalette[participants.length % _participantPalette.length];
    return ConversationParticipant(
      id: const Uuid().v4(),
      displayName: 'Reviewer',
      roleLabel: 'Reviewer',
      roleSystemPrompt:
          'Review the conversation, add a concise second opinion, and call out risks or missing context.',
      endpointId: endpointId,
      colorValue: colorValue,
      order: nextOrder,
    );
  }

  Future<void> _emitChange({
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
  }) async {
    final normalizedParticipants = const ParticipantTurnCoordinator()
        .normalizeParticipants(
          participants: participants,
          primaryModel: primaryModel,
        );
    await Future<void>.value(
      onChanged(participants: normalizedParticipants, config: config),
    );
  }
}

class _ParticipantRuntimeControl extends StatelessWidget {
  const _ParticipantRuntimeControl({
    required this.runtime,
    this.onStopRequested,
    this.onContinueRequested,
  });

  final ParticipantTurnRuntime runtime;
  final VoidCallback? onStopRequested;
  final VoidCallback? onContinueRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeName = runtime.activeParticipantName.trim();
    final label = runtime.paused
        ? 'Paused at round ${runtime.currentRound}/${runtime.maxRounds}'
        : activeName.isEmpty
        ? 'Round ${runtime.currentRound}/${runtime.maxRounds}'
        : '$activeName - round ${runtime.currentRound}/${runtime.maxRounds}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.64,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (runtime.activeParticipantColorValue != null) ...[
              _ParticipantColorDot(
                color: Color(runtime.activeParticipantColorValue!),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            if (runtime.paused)
              Tooltip(
                message: 'Continue participant turns',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.play_arrow_outlined, size: 18),
                  onPressed: onContinueRequested,
                ),
              )
            else if (runtime.multiRound && !runtime.stopRequested)
              Tooltip(
                message: 'Stop after current participant',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.pause_circle_outline, size: 18),
                  onPressed: onStopRequested,
                ),
              )
            else if (runtime.stopRequested)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRosterButton extends StatelessWidget {
  const _EmptyRosterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.group_add_outlined, size: 18),
        label: const Text('Participants'),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  const _ParticipantChip({
    required this.participant,
    required this.enabled,
    required this.onPressed,
  });

  final ConversationParticipant participant;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = participant.effectiveDisplayName;
    final role = participant.effectiveRoleLabel;
    final color = Color(participant.colorValue);
    final labelColor = participant.enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Opacity(
      opacity: participant.enabled ? 1 : 0.56,
      child: ActionChip(
        avatar: _ParticipantColorDot(color: color),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (role.isNotEmpty && role != name) ...[
                Text(
                  ' - ',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                Flexible(
                  child: Text(
                    role,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

class _ParticipantColorDot extends StatelessWidget {
  const _ParticipantColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TurnDepthControl extends StatelessWidget {
  const _TurnDepthControl({
    required this.config,
    required this.enabled,
    required this.onChanged,
  });

  final ParticipantTurnConfig config;
  final bool enabled;
  final ValueChanged<ParticipantTurnConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxRounds = config.maxRounds.clamp(2, 8).toInt();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<ParticipantTurnDepth>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          showSelectedIcon: false,
          selected: {config.depth},
          segments: const [
            ButtonSegment(
              value: ParticipantTurnDepth.singleRound,
              icon: Icon(Icons.looks_one_outlined, size: 16),
              label: Text('Single'),
            ),
            ButtonSegment(
              value: ParticipantTurnDepth.multiRound,
              icon: Icon(Icons.repeat_outlined, size: 16),
              label: Text('Multi'),
            ),
          ],
          onSelectionChanged: enabled
              ? (selection) {
                  onChanged(config.copyWith(depth: selection.single));
                }
              : null,
        ),
        if (config.depth == ParticipantTurnDepth.multiRound) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Decrease rounds',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              onPressed: enabled && maxRounds > 2
                  ? () => onChanged(config.copyWith(maxRounds: maxRounds - 1))
                  : null,
            ),
          ),
          Text(
            '$maxRounds rounds',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Tooltip(
            message: 'Increase rounds',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              onPressed: enabled && maxRounds < 8
                  ? () => onChanged(config.copyWith(maxRounds: maxRounds + 1))
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _ParticipantEditorResult {
  const _ParticipantEditorResult({
    required this.participant,
    this.removeParticipant = false,
  });

  final ConversationParticipant participant;
  final bool removeParticipant;
}

class _ParticipantEditorSheet extends StatefulWidget {
  const _ParticipantEditorSheet({
    required this.participant,
    required this.endpoints,
    required this.primaryModel,
    required this.isNew,
  });

  final ConversationParticipant participant;
  final List<NamedEndpoint> endpoints;
  final String primaryModel;
  final bool isNew;

  @override
  State<_ParticipantEditorSheet> createState() =>
      _ParticipantEditorSheetState();
}

class _ParticipantEditorSheetState extends State<_ParticipantEditorSheet> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _roleLabelController;
  late final TextEditingController _rolePromptController;
  late final TextEditingController _modelController;
  late String _endpointId;
  late int _colorValue;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final participant = widget.participant;
    _displayNameController = TextEditingController(
      text: participant.displayName,
    );
    _roleLabelController = TextEditingController(text: participant.roleLabel);
    _rolePromptController = TextEditingController(
      text: participant.roleSystemPrompt,
    );
    _modelController = TextEditingController(text: participant.model);
    _endpointId = participant.endpointId;
    _colorValue = participant.colorValue;
    _enabled = participant.enabled;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _roleLabelController.dispose();
    _rolePromptController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final endpointIds = widget.endpoints.map((endpoint) => endpoint.id).toSet();
    final hasMissingEndpoint =
        _endpointId.isNotEmpty && !endpointIds.contains(_endpointId);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isNew ? 'Add participant' : 'Edit participant',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _displayNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _roleLabelController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.assignment_ind_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _endpointId,
                decoration: const InputDecoration(
                  labelText: 'Endpoint',
                  prefixIcon: Icon(Icons.hub_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Primary endpoint'),
                  ),
                  if (hasMissingEndpoint)
                    DropdownMenuItem(
                      value: _endpointId,
                      child: Text('Missing endpoint: $_endpointId'),
                    ),
                  for (final endpoint in widget.endpoints)
                    DropdownMenuItem(
                      value: endpoint.id,
                      child: Text(
                        endpoint.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _endpointId = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Model override',
                  hintText: widget.primaryModel,
                  prefixIcon: const Icon(Icons.memory_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rolePromptController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Role prompt',
                  prefixIcon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Color',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final colorValue in _participantPalette)
                    _ColorSwatchButton(
                      colorValue: colorValue,
                      selected: colorValue == _colorValue,
                      onPressed: () {
                        setState(() => _colorValue = colorValue);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!widget.isNew)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                      onPressed: () {
                        Navigator.of(context).pop(
                          _ParticipantEditorResult(
                            participant: widget.participant,
                            removeParticipant: true,
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final participant = widget.participant.copyWith(
      displayName: _displayNameController.text.trim(),
      roleLabel: _roleLabelController.text.trim(),
      roleSystemPrompt: _rolePromptController.text.trim(),
      endpointId: _endpointId.trim(),
      model: _modelController.text.trim(),
      colorValue: _colorValue,
      enabled: _enabled,
    );
    Navigator.of(
      context,
    ).pop(_ParticipantEditorResult(participant: participant));
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.colorValue,
    required this.selected,
    required this.onPressed,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(colorValue);
    return Tooltip(
      message: 'Select color',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: theme.colorScheme.onPrimary)
              : null,
        ),
      ),
    );
  }
}
