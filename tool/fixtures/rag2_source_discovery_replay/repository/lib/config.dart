const defaultEndpoint = 'http://localhost:1234/v1';

class RetryPolicy {
  const RetryPolicy(this.limit);

  final int limit;
}
