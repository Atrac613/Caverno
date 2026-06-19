class LanguageDiagnosticsBridgeCapabilities {
  const LanguageDiagnosticsBridgeCapabilities({
    required this.diagnostics,
    required this.documentSymbols,
    required this.goToDefinition,
  });

  final bool diagnostics;
  final bool documentSymbols;
  final bool goToDefinition;

  Map<String, dynamic> toJson() => {
    'diagnostics': diagnostics,
    'document_symbols': documentSymbols,
    'go_to_definition': goToDefinition,
  };
}

class LanguageDiagnosticsBridgeMetadata {
  const LanguageDiagnosticsBridgeMetadata({
    required this.providerName,
    required this.protocol,
    required this.status,
    required this.capabilities,
    this.attemptedPrimaryProvider,
    this.degradeReason,
  });

  factory LanguageDiagnosticsBridgeMetadata.dartAnalyzerCli() {
    return const LanguageDiagnosticsBridgeMetadata(
      providerName: 'dart_analyzer',
      protocol: 'dart_analyzer_cli',
      status: 'ready',
      capabilities: LanguageDiagnosticsBridgeCapabilities(
        diagnostics: true,
        documentSymbols: false,
        goToDefinition: false,
      ),
    );
  }

  final String providerName;
  final String protocol;
  final String status;
  final LanguageDiagnosticsBridgeCapabilities capabilities;
  final String? attemptedPrimaryProvider;
  final String? degradeReason;

  LanguageDiagnosticsBridgeMetadata degradedFrom({
    required String attemptedProviderName,
    required String reason,
  }) {
    return LanguageDiagnosticsBridgeMetadata(
      providerName: providerName,
      protocol: protocol,
      status: 'degraded',
      capabilities: capabilities,
      attemptedPrimaryProvider: attemptedProviderName,
      degradeReason: reason,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': providerName,
    'protocol': protocol,
    'status': status,
    'capabilities': capabilities.toJson(),
    if (attemptedPrimaryProvider != null)
      'attempted_primary_provider': attemptedPrimaryProvider,
    if (degradeReason != null) 'degrade_reason': degradeReason,
  };
}
