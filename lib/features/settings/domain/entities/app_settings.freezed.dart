// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$McpServerConfig {

 String get url; bool get enabled;@JsonKey(unknownEnumValue: McpServerType.http) McpServerType get type;@JsonKey(unknownEnumValue: McpServerTrustState.trusted) McpServerTrustState get trustState; String get command; List<String> get args; DateTime? get trustedAt;
/// Create a copy of McpServerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerConfigCopyWith<McpServerConfig> get copyWith => _$McpServerConfigCopyWithImpl<McpServerConfig>(this as McpServerConfig, _$identity);

  /// Serializes this McpServerConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.type, type) || other.type == type)&&(identical(other.trustState, trustState) || other.trustState == trustState)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, args)&&(identical(other.trustedAt, trustedAt) || other.trustedAt == trustedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,enabled,type,trustState,command,const DeepCollectionEquality().hash(args),trustedAt);

@override
String toString() {
  return 'McpServerConfig(url: $url, enabled: $enabled, type: $type, trustState: $trustState, command: $command, args: $args, trustedAt: $trustedAt)';
}


}

/// @nodoc
abstract mixin class $McpServerConfigCopyWith<$Res>  {
  factory $McpServerConfigCopyWith(McpServerConfig value, $Res Function(McpServerConfig) _then) = _$McpServerConfigCopyWithImpl;
@useResult
$Res call({
 String url, bool enabled,@JsonKey(unknownEnumValue: McpServerType.http) McpServerType type,@JsonKey(unknownEnumValue: McpServerTrustState.trusted) McpServerTrustState trustState, String command, List<String> args, DateTime? trustedAt
});




}
/// @nodoc
class _$McpServerConfigCopyWithImpl<$Res>
    implements $McpServerConfigCopyWith<$Res> {
  _$McpServerConfigCopyWithImpl(this._self, this._then);

  final McpServerConfig _self;
  final $Res Function(McpServerConfig) _then;

/// Create a copy of McpServerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? enabled = null,Object? type = null,Object? trustState = null,Object? command = null,Object? args = null,Object? trustedAt = freezed,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as McpServerType,trustState: null == trustState ? _self.trustState : trustState // ignore: cast_nullable_to_non_nullable
as McpServerTrustState,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,trustedAt: freezed == trustedAt ? _self.trustedAt : trustedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [McpServerConfig].
extension McpServerConfigPatterns on McpServerConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpServerConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpServerConfig() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpServerConfig value)  $default,){
final _that = this;
switch (_that) {
case _McpServerConfig():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpServerConfig value)?  $default,){
final _that = this;
switch (_that) {
case _McpServerConfig() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  bool enabled, @JsonKey(unknownEnumValue: McpServerType.http)  McpServerType type, @JsonKey(unknownEnumValue: McpServerTrustState.trusted)  McpServerTrustState trustState,  String command,  List<String> args,  DateTime? trustedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpServerConfig() when $default != null:
return $default(_that.url,_that.enabled,_that.type,_that.trustState,_that.command,_that.args,_that.trustedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  bool enabled, @JsonKey(unknownEnumValue: McpServerType.http)  McpServerType type, @JsonKey(unknownEnumValue: McpServerTrustState.trusted)  McpServerTrustState trustState,  String command,  List<String> args,  DateTime? trustedAt)  $default,) {final _that = this;
switch (_that) {
case _McpServerConfig():
return $default(_that.url,_that.enabled,_that.type,_that.trustState,_that.command,_that.args,_that.trustedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  bool enabled, @JsonKey(unknownEnumValue: McpServerType.http)  McpServerType type, @JsonKey(unknownEnumValue: McpServerTrustState.trusted)  McpServerTrustState trustState,  String command,  List<String> args,  DateTime? trustedAt)?  $default,) {final _that = this;
switch (_that) {
case _McpServerConfig() when $default != null:
return $default(_that.url,_that.enabled,_that.type,_that.trustState,_that.command,_that.args,_that.trustedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _McpServerConfig extends McpServerConfig {
  const _McpServerConfig({this.url = '', this.enabled = true, @JsonKey(unknownEnumValue: McpServerType.http) this.type = McpServerType.http, @JsonKey(unknownEnumValue: McpServerTrustState.trusted) this.trustState = McpServerTrustState.trusted, this.command = '', final  List<String> args = const <String>[], this.trustedAt}): _args = args,super._();
  factory _McpServerConfig.fromJson(Map<String, dynamic> json) => _$McpServerConfigFromJson(json);

@override@JsonKey() final  String url;
@override@JsonKey() final  bool enabled;
@override@JsonKey(unknownEnumValue: McpServerType.http) final  McpServerType type;
@override@JsonKey(unknownEnumValue: McpServerTrustState.trusted) final  McpServerTrustState trustState;
@override@JsonKey() final  String command;
 final  List<String> _args;
@override@JsonKey() List<String> get args {
  if (_args is EqualUnmodifiableListView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_args);
}

@override final  DateTime? trustedAt;

/// Create a copy of McpServerConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpServerConfigCopyWith<_McpServerConfig> get copyWith => __$McpServerConfigCopyWithImpl<_McpServerConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$McpServerConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpServerConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.type, type) || other.type == type)&&(identical(other.trustState, trustState) || other.trustState == trustState)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&(identical(other.trustedAt, trustedAt) || other.trustedAt == trustedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,enabled,type,trustState,command,const DeepCollectionEquality().hash(_args),trustedAt);

@override
String toString() {
  return 'McpServerConfig(url: $url, enabled: $enabled, type: $type, trustState: $trustState, command: $command, args: $args, trustedAt: $trustedAt)';
}


}

/// @nodoc
abstract mixin class _$McpServerConfigCopyWith<$Res> implements $McpServerConfigCopyWith<$Res> {
  factory _$McpServerConfigCopyWith(_McpServerConfig value, $Res Function(_McpServerConfig) _then) = __$McpServerConfigCopyWithImpl;
@override @useResult
$Res call({
 String url, bool enabled,@JsonKey(unknownEnumValue: McpServerType.http) McpServerType type,@JsonKey(unknownEnumValue: McpServerTrustState.trusted) McpServerTrustState trustState, String command, List<String> args, DateTime? trustedAt
});




}
/// @nodoc
class __$McpServerConfigCopyWithImpl<$Res>
    implements _$McpServerConfigCopyWith<$Res> {
  __$McpServerConfigCopyWithImpl(this._self, this._then);

  final _McpServerConfig _self;
  final $Res Function(_McpServerConfig) _then;

/// Create a copy of McpServerConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? enabled = null,Object? type = null,Object? trustState = null,Object? command = null,Object? args = null,Object? trustedAt = freezed,}) {
  return _then(_McpServerConfig(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as McpServerType,trustState: null == trustState ? _self.trustState : trustState // ignore: cast_nullable_to_non_nullable
as McpServerTrustState,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,trustedAt: freezed == trustedAt ? _self.trustedAt : trustedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$AppSettings {

 String get baseUrl; String get model; String get apiKey; double get temperature; int get maxTokens; String get googleChatWebhookUrl; String get mcpUrl; List<String> get mcpUrls; List<McpServerConfig> get mcpServers; bool get mcpEnabled;// Voice settings
 bool get ttsEnabled; bool get autoReadEnabled; double get speechRate;// Voice mode (Whisper + VOICEVOX)
 bool get voiceModeAutoStop; String get whisperUrl; String get voicevoxUrl; int get voicevoxSpeakerId; String get language;@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode get assistantMode; bool get confirmFileMutations; bool get confirmLocalCommands; bool get confirmGitWrites; bool get showMemoryUpdates; bool get demoMode; List<String> get disabledBuiltInTools;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other.mcpUrls, mcpUrls)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&const DeepCollectionEquality().equals(other.disabledBuiltInTools, disabledBuiltInTools));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,baseUrl,model,apiKey,temperature,maxTokens,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(mcpUrls),const DeepCollectionEquality().hash(mcpServers),mcpEnabled,ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,showMemoryUpdates,demoMode,const DeepCollectionEquality().hash(disabledBuiltInTools)]);

@override
String toString() {
  return 'AppSettings(baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, showMemoryUpdates: $showMemoryUpdates, demoMode: $demoMode, disabledBuiltInTools: $disabledBuiltInTools)';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
 String baseUrl, String model, String apiKey, double temperature, int maxTokens, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool showMemoryUpdates, bool demoMode, List<String> disabledBuiltInTools
});




}
/// @nodoc
class _$AppSettingsCopyWithImpl<$Res>
    implements $AppSettingsCopyWith<$Res> {
  _$AppSettingsCopyWithImpl(this._self, this._then);

  final AppSettings _self;
  final $Res Function(AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? showMemoryUpdates = null,Object? demoMode = null,Object? disabledBuiltInTools = null,}) {
  return _then(_self.copyWith(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,googleChatWebhookUrl: null == googleChatWebhookUrl ? _self.googleChatWebhookUrl : googleChatWebhookUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrl: null == mcpUrl ? _self.mcpUrl : mcpUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrls: null == mcpUrls ? _self.mcpUrls : mcpUrls // ignore: cast_nullable_to_non_nullable
as List<String>,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServerConfig>,mcpEnabled: null == mcpEnabled ? _self.mcpEnabled : mcpEnabled // ignore: cast_nullable_to_non_nullable
as bool,ttsEnabled: null == ttsEnabled ? _self.ttsEnabled : ttsEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoReadEnabled: null == autoReadEnabled ? _self.autoReadEnabled : autoReadEnabled // ignore: cast_nullable_to_non_nullable
as bool,speechRate: null == speechRate ? _self.speechRate : speechRate // ignore: cast_nullable_to_non_nullable
as double,voiceModeAutoStop: null == voiceModeAutoStop ? _self.voiceModeAutoStop : voiceModeAutoStop // ignore: cast_nullable_to_non_nullable
as bool,whisperUrl: null == whisperUrl ? _self.whisperUrl : whisperUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxUrl: null == voicevoxUrl ? _self.voicevoxUrl : voicevoxUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxSpeakerId: null == voicevoxSpeakerId ? _self.voicevoxSpeakerId : voicevoxSpeakerId // ignore: cast_nullable_to_non_nullable
as int,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
as AssistantMode,confirmFileMutations: null == confirmFileMutations ? _self.confirmFileMutations : confirmFileMutations // ignore: cast_nullable_to_non_nullable
as bool,confirmLocalCommands: null == confirmLocalCommands ? _self.confirmLocalCommands : confirmLocalCommands // ignore: cast_nullable_to_non_nullable
as bool,confirmGitWrites: null == confirmGitWrites ? _self.confirmGitWrites : confirmGitWrites // ignore: cast_nullable_to_non_nullable
as bool,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self.disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [AppSettings].
extension AppSettingsPatterns on AppSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppSettings value)  $default,){
final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppSettings value)?  $default,){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool showMemoryUpdates,  bool demoMode,  List<String> disabledBuiltInTools)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.showMemoryUpdates,_that.demoMode,_that.disabledBuiltInTools);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool showMemoryUpdates,  bool demoMode,  List<String> disabledBuiltInTools)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.showMemoryUpdates,_that.demoMode,_that.disabledBuiltInTools);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool showMemoryUpdates,  bool demoMode,  List<String> disabledBuiltInTools)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.showMemoryUpdates,_that.demoMode,_that.disabledBuiltInTools);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppSettings extends AppSettings {
  const _AppSettings({required this.baseUrl, required this.model, required this.apiKey, required this.temperature, required this.maxTokens, this.googleChatWebhookUrl = '', this.mcpUrl = '', final  List<String> mcpUrls = const <String>[], final  List<McpServerConfig> mcpServers = const <McpServerConfig>[], this.mcpEnabled = false, this.ttsEnabled = true, this.autoReadEnabled = false, this.speechRate = 0.5, this.voiceModeAutoStop = true, this.whisperUrl = 'http://localhost:8080', this.voicevoxUrl = 'http://localhost:50021', this.voicevoxSpeakerId = 0, this.language = 'system', @JsonKey(unknownEnumValue: AssistantMode.general) this.assistantMode = AssistantMode.general, this.confirmFileMutations = true, this.confirmLocalCommands = true, this.confirmGitWrites = true, this.showMemoryUpdates = false, this.demoMode = false, final  List<String> disabledBuiltInTools = const <String>[]}): _mcpUrls = mcpUrls,_mcpServers = mcpServers,_disabledBuiltInTools = disabledBuiltInTools,super._();
  factory _AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);

@override final  String baseUrl;
@override final  String model;
@override final  String apiKey;
@override final  double temperature;
@override final  int maxTokens;
@override@JsonKey() final  String googleChatWebhookUrl;
@override@JsonKey() final  String mcpUrl;
 final  List<String> _mcpUrls;
@override@JsonKey() List<String> get mcpUrls {
  if (_mcpUrls is EqualUnmodifiableListView) return _mcpUrls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpUrls);
}

 final  List<McpServerConfig> _mcpServers;
@override@JsonKey() List<McpServerConfig> get mcpServers {
  if (_mcpServers is EqualUnmodifiableListView) return _mcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpServers);
}

@override@JsonKey() final  bool mcpEnabled;
// Voice settings
@override@JsonKey() final  bool ttsEnabled;
@override@JsonKey() final  bool autoReadEnabled;
@override@JsonKey() final  double speechRate;
// Voice mode (Whisper + VOICEVOX)
@override@JsonKey() final  bool voiceModeAutoStop;
@override@JsonKey() final  String whisperUrl;
@override@JsonKey() final  String voicevoxUrl;
@override@JsonKey() final  int voicevoxSpeakerId;
@override@JsonKey() final  String language;
@override@JsonKey(unknownEnumValue: AssistantMode.general) final  AssistantMode assistantMode;
@override@JsonKey() final  bool confirmFileMutations;
@override@JsonKey() final  bool confirmLocalCommands;
@override@JsonKey() final  bool confirmGitWrites;
@override@JsonKey() final  bool showMemoryUpdates;
@override@JsonKey() final  bool demoMode;
 final  List<String> _disabledBuiltInTools;
@override@JsonKey() List<String> get disabledBuiltInTools {
  if (_disabledBuiltInTools is EqualUnmodifiableListView) return _disabledBuiltInTools;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_disabledBuiltInTools);
}


/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppSettingsCopyWith<_AppSettings> get copyWith => __$AppSettingsCopyWithImpl<_AppSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other._mcpUrls, _mcpUrls)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&const DeepCollectionEquality().equals(other._disabledBuiltInTools, _disabledBuiltInTools));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,baseUrl,model,apiKey,temperature,maxTokens,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(_mcpUrls),const DeepCollectionEquality().hash(_mcpServers),mcpEnabled,ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,showMemoryUpdates,demoMode,const DeepCollectionEquality().hash(_disabledBuiltInTools)]);

@override
String toString() {
  return 'AppSettings(baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, showMemoryUpdates: $showMemoryUpdates, demoMode: $demoMode, disabledBuiltInTools: $disabledBuiltInTools)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
 String baseUrl, String model, String apiKey, double temperature, int maxTokens, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool showMemoryUpdates, bool demoMode, List<String> disabledBuiltInTools
});




}
/// @nodoc
class __$AppSettingsCopyWithImpl<$Res>
    implements _$AppSettingsCopyWith<$Res> {
  __$AppSettingsCopyWithImpl(this._self, this._then);

  final _AppSettings _self;
  final $Res Function(_AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? showMemoryUpdates = null,Object? demoMode = null,Object? disabledBuiltInTools = null,}) {
  return _then(_AppSettings(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,googleChatWebhookUrl: null == googleChatWebhookUrl ? _self.googleChatWebhookUrl : googleChatWebhookUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrl: null == mcpUrl ? _self.mcpUrl : mcpUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrls: null == mcpUrls ? _self._mcpUrls : mcpUrls // ignore: cast_nullable_to_non_nullable
as List<String>,mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServerConfig>,mcpEnabled: null == mcpEnabled ? _self.mcpEnabled : mcpEnabled // ignore: cast_nullable_to_non_nullable
as bool,ttsEnabled: null == ttsEnabled ? _self.ttsEnabled : ttsEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoReadEnabled: null == autoReadEnabled ? _self.autoReadEnabled : autoReadEnabled // ignore: cast_nullable_to_non_nullable
as bool,speechRate: null == speechRate ? _self.speechRate : speechRate // ignore: cast_nullable_to_non_nullable
as double,voiceModeAutoStop: null == voiceModeAutoStop ? _self.voiceModeAutoStop : voiceModeAutoStop // ignore: cast_nullable_to_non_nullable
as bool,whisperUrl: null == whisperUrl ? _self.whisperUrl : whisperUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxUrl: null == voicevoxUrl ? _self.voicevoxUrl : voicevoxUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxSpeakerId: null == voicevoxSpeakerId ? _self.voicevoxSpeakerId : voicevoxSpeakerId // ignore: cast_nullable_to_non_nullable
as int,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
as AssistantMode,confirmFileMutations: null == confirmFileMutations ? _self.confirmFileMutations : confirmFileMutations // ignore: cast_nullable_to_non_nullable
as bool,confirmLocalCommands: null == confirmLocalCommands ? _self.confirmLocalCommands : confirmLocalCommands // ignore: cast_nullable_to_non_nullable
as bool,confirmGitWrites: null == confirmGitWrites ? _self.confirmGitWrites : confirmGitWrites // ignore: cast_nullable_to_non_nullable
as bool,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self._disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
