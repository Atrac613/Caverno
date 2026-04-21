import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/routine.dart';

class RoutineEditorResult {
  const RoutineEditorResult({
    required this.name,
    required this.prompt,
    required this.intervalValue,
    required this.intervalUnit,
    required this.enabled,
  });

  final String name;
  final String prompt;
  final int intervalValue;
  final RoutineIntervalUnit intervalUnit;
  final bool enabled;
}

class RoutineEditorSheet extends StatefulWidget {
  const RoutineEditorSheet({super.key, this.initialRoutine});

  final Routine? initialRoutine;

  @override
  State<RoutineEditorSheet> createState() => _RoutineEditorSheetState();
}

class _RoutineEditorSheetState extends State<RoutineEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late final TextEditingController _intervalController;
  late RoutineIntervalUnit _intervalUnit;
  late bool _enabled;

  bool get _isEditing => widget.initialRoutine != null;

  @override
  void initState() {
    super.initState();
    final initialRoutine = widget.initialRoutine;
    _nameController = TextEditingController(text: initialRoutine?.name ?? '');
    _promptController = TextEditingController(
      text: initialRoutine?.prompt ?? '',
    );
    _intervalController = TextEditingController(
      text: (initialRoutine?.intervalValue ?? 1).toString(),
    );
    _intervalUnit = initialRoutine?.intervalUnit ?? RoutineIntervalUnit.hours;
    _enabled = initialRoutine?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing
                    ? 'routines.edit_title'.tr()
                    : 'routines.create_title'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'routines.name_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'routines.name_required'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _promptController,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'routines.prompt_label'.tr(),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'routines.prompt_required'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _intervalController,
                      decoration: InputDecoration(
                        labelText: 'routines.interval_value_label'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final parsed = int.tryParse((value ?? '').trim());
                        if (parsed == null || parsed < 1) {
                          return 'routines.interval_value_required'.tr();
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<RoutineIntervalUnit>(
                      initialValue: _intervalUnit,
                      decoration: InputDecoration(
                        labelText: 'routines.interval_unit_label'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: RoutineIntervalUnit.values
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(_intervalUnitLabel(unit)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _intervalUnit = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('routines.enabled_label'.tr()),
                subtitle: Text('routines.enabled_hint'.tr()),
                value: _enabled,
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: Text('common.save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _intervalUnitLabel(RoutineIntervalUnit unit) {
    return switch (unit) {
      RoutineIntervalUnit.minutes => 'routines.unit_minutes'.tr(),
      RoutineIntervalUnit.hours => 'routines.unit_hours'.tr(),
      RoutineIntervalUnit.days => 'routines.unit_days'.tr(),
    };
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final intervalValue = int.tryParse(_intervalController.text.trim()) ?? 1;

    Navigator.of(context).pop(
      RoutineEditorResult(
        name: _nameController.text.trim(),
        prompt: _promptController.text.trim(),
        intervalValue: intervalValue,
        intervalUnit: _intervalUnit,
        enabled: _enabled,
      ),
    );
  }
}
