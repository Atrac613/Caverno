enum HtmlPreviewStatus { idle, starting, running, stopping, failed }

/// Companion-panel state for one HTML preview, including which project it is.
class HtmlPreviewSessionState {
  const HtmlPreviewSessionState({
    this.status = HtmlPreviewStatus.idle,
    this.projectRoot = '',
    this.entryRelativePath = '',
    this.url = '',
    this.failure,
  });

  final HtmlPreviewStatus status;
  final String projectRoot;
  final String entryRelativePath;
  final String url;
  final String? failure;

  bool get isBusy =>
      status == HtmlPreviewStatus.starting ||
      status == HtmlPreviewStatus.stopping;

  bool get isActive =>
      status == HtmlPreviewStatus.starting ||
      status == HtmlPreviewStatus.running ||
      status == HtmlPreviewStatus.stopping;

  bool isActiveFor(String projectRoot) =>
      isActive && this.projectRoot == projectRoot;

  HtmlPreviewSessionState copyWith({
    HtmlPreviewStatus? status,
    String? projectRoot,
    String? entryRelativePath,
    String? url,
    String? failure,
    bool clearFailure = false,
  }) {
    return HtmlPreviewSessionState(
      status: status ?? this.status,
      projectRoot: projectRoot ?? this.projectRoot,
      entryRelativePath: entryRelativePath ?? this.entryRelativePath,
      url: url ?? this.url,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}
