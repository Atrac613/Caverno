/// Route name for the modal that presents one pending interaction.
///
/// Naming the route is what lets the phone take a dialog away again when the
/// interaction is answered somewhere else — today, the Apple Watch. Dismissal
/// pops by name rather than popping whatever happens to be on top, so a
/// mistimed resolution can never close an unrelated screen.
///
/// Lives beside the approval sheets rather than with the presenter that
/// dismisses them: the sheets are what push the route, and a widget has no
/// business importing from `pages/`.
String approvalDialogRouteName(String id) => 'caverno.approval.$id';
