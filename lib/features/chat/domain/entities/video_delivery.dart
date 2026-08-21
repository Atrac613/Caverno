/// How a video attachment was handed to the endpoint.
enum VideoDeliveryMode {
  /// Served from the local media host for the endpoint to fetch.
  url,

  /// Embedded in the request as a `data:` URI.
  inline,
}

/// The address a video was sent as, and how it got there.
///
/// Recorded so a turn that answered without its video can be told apart from
/// one that never had it. Which of the two modes was used is the first thing
/// worth knowing: it decides whether to go looking at the network or at the
/// request size.
class VideoDelivery {
  const VideoDelivery({required this.url, required this.mode});

  const VideoDelivery.url(String url)
    : this(url: url, mode: VideoDeliveryMode.url);

  const VideoDelivery.inline(String dataUri)
    : this(url: dataUri, mode: VideoDeliveryMode.inline);

  /// What goes into the request: an http URL, or a whole `data:` URI.
  final String url;

  final VideoDeliveryMode mode;

  bool get isInline => mode == VideoDeliveryMode.inline;

  /// What a log may keep.
  ///
  /// An inlined video is megabytes of base64; writing it to a log would bloat
  /// the file past usefulness and copy the person's video into it. The length
  /// is the part worth keeping -- it is what says how big the request got.
  String get loggableUrl =>
      isInline ? 'data: URI (${url.length} chars)' : url;
}
