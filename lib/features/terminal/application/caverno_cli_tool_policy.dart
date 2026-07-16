import '../../../../core/services/macos_computer_use_tool_policy.dart';

const cavernoCliUnsupportedSkillTools = <String>{'load_skill', 'save_skill'};

const cavernoCliDisabledToolNames = <String>{
  ...MacosComputerUseToolPolicy.allToolNames,
  ...cavernoCliUnsupportedSkillTools,
};
