/// Route name for the modal that presents one pending interaction.
///
/// The presenter uses this name to capture the newly pushed route, then removes
/// that exact route when another device answers, even beneath another screen.
///
/// Lives beside the approval sheets rather than with the presenter that
/// dismisses them: the sheets are what push the route, and a widget has no
/// business importing from `pages/`.
String approvalDialogRouteName(String id) => 'caverno.approval.$id';
