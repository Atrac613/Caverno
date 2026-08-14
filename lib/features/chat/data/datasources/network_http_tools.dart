import '../../../../core/security/egress_destination_policy.dart';
import 'network_http_request_executor.dart';

export 'network_http_request_executor.dart'
    show
        NetworkEgressAddressLookup,
        NetworkHttpClientFactory,
        NetworkPinnedSocketConnector;

class NetworkHttpTools {
  NetworkHttpTools({
    NetworkHttpClientFactory? clientFactory,
    NetworkEgressAddressLookup? addressLookup,
    NetworkPinnedSocketConnector? socketConnector,
    EgressDestinationPolicy destinationPolicy = const EgressDestinationPolicy(),
  }) : _executor = NetworkHttpRequestExecutor(
         clientFactory: clientFactory,
         addressLookup: addressLookup,
         socketConnector: socketConnector,
         destinationPolicy: destinationPolicy,
       );

  final NetworkHttpRequestExecutor _executor;

  Future<String> httpStatus({required String url, int timeoutSeconds = 10}) {
    return _executor.execute(
      method: 'GET',
      url: url,
      timeoutSeconds: timeoutSeconds,
      followRedirects: true,
      maxRedirects: 5,
      includeBody: false,
      statusOnly: true,
    );
  }

  Future<String> httpGet({
    required String url,
    Map<String, String>? headers,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _executor.execute(
      method: 'GET',
      url: url,
      headers: headers,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  Future<String> httpHead({
    required String url,
    Map<String, String>? headers,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _executor.execute(
      method: 'HEAD',
      url: url,
      headers: headers,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: false,
    );
  }

  Future<String> httpDelete({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _executor.execute(
      method: 'DELETE',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  Future<String> httpPost({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _executor.execute(
      method: 'POST',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  Future<String> httpPut({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _executor.execute(
      method: 'PUT',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  Future<String> httpPatch({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _executor.execute(
      method: 'PATCH',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }
}
