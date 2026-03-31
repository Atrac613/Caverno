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
mixin _$AppSettings {

 String get baseUrl; String get model; String get apiKey; double get temperature; int get maxTokens; String get mcpUrl; bool get mcpEnabled;// Voice settings
 bool get ttsEnabled; bool get autoReadEnabled; double get speechRate;// Voice mode (Whisper + VOICEVOX)
 bool get voiceModeAutoStop; String get whisperUrl; String get voicevoxUrl; int get voicevoxSpeakerId; String get language;@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode get assistantMode; bool get demoMode;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,baseUrl,model,apiKey,temperature,maxTokens,mcpUrl,mcpEnabled,ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,demoMode);

@override
String toString() {
  return 'AppSettings(baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, mcpUrl: $mcpUrl, mcpEnabled: $mcpEnabled, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, demoMode: $demoMode)';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
 String baseUrl, String model, String apiKey, double temperature, int maxTokens, String mcpUrl, bool mcpEnabled, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode, bool demoMode
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
@pragma('vm:prefer-inline') @override $Res call({Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? mcpUrl = null,Object? mcpEnabled = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? demoMode = null,}) {
  return _then(_self.copyWith(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,mcpUrl: null == mcpUrl ? _self.mcpUrl : mcpUrl // ignore: cast_nullable_to_non_nullable
as String,mcpEnabled: null == mcpEnabled ? _self.mcpEnabled : mcpEnabled // ignore: cast_nullable_to_non_nullable
as bool,ttsEnabled: null == ttsEnabled ? _self.ttsEnabled : ttsEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoReadEnabled: null == autoReadEnabled ? _self.autoReadEnabled : autoReadEnabled // ignore: cast_nullable_to_non_nullable
as bool,speechRate: null == speechRate ? _self.speechRate : speechRate // ignore: cast_nullable_to_non_nullable
as double,voiceModeAutoStop: null == voiceModeAutoStop ? _self.voiceModeAutoStop : voiceModeAutoStop // ignore: cast_nullable_to_non_nullable
as bool,whisperUrl: null == whisperUrl ? _self.whisperUrl : whisperUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxUrl: null == voicevoxUrl ? _self.voicevoxUrl : voicevoxUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxSpeakerId: null == voicevoxSpeakerId ? _self.voicevoxSpeakerId : voicevoxSpeakerId // ignore: cast_nullable_to_non_nullable
as int,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
as AssistantMode,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens,  String mcpUrl,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode,  bool demoMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.mcpUrl,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.demoMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens,  String mcpUrl,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode,  bool demoMode)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.mcpUrl,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.demoMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens,  String mcpUrl,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode,  bool demoMode)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.mcpUrl,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.demoMode);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppSettings implements AppSettings {
  const _AppSettings({required this.baseUrl, required this.model, required this.apiKey, required this.temperature, required this.maxTokens, this.mcpUrl = '', this.mcpEnabled = false, this.ttsEnabled = true, this.autoReadEnabled = false, this.speechRate = 0.5, this.voiceModeAutoStop = true, this.whisperUrl = 'http://localhost:8080', this.voicevoxUrl = 'http://localhost:50021', this.voicevoxSpeakerId = 0, this.language = 'system', @JsonKey(unknownEnumValue: AssistantMode.general) this.assistantMode = AssistantMode.general, this.demoMode = false});
  factory _AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);

@override final  String baseUrl;
@override final  String model;
@override final  String apiKey;
@override final  double temperature;
@override final  int maxTokens;
@override@JsonKey() final  String mcpUrl;
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
@override@JsonKey() final  bool demoMode;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,baseUrl,model,apiKey,temperature,maxTokens,mcpUrl,mcpEnabled,ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,demoMode);

@override
String toString() {
  return 'AppSettings(baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, mcpUrl: $mcpUrl, mcpEnabled: $mcpEnabled, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, demoMode: $demoMode)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
 String baseUrl, String model, String apiKey, double temperature, int maxTokens, String mcpUrl, bool mcpEnabled, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode, bool demoMode
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
@override @pragma('vm:prefer-inline') $Res call({Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? mcpUrl = null,Object? mcpEnabled = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? demoMode = null,}) {
  return _then(_AppSettings(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,mcpUrl: null == mcpUrl ? _self.mcpUrl : mcpUrl // ignore: cast_nullable_to_non_nullable
as String,mcpEnabled: null == mcpEnabled ? _self.mcpEnabled : mcpEnabled // ignore: cast_nullable_to_non_nullable
as bool,ttsEnabled: null == ttsEnabled ? _self.ttsEnabled : ttsEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoReadEnabled: null == autoReadEnabled ? _self.autoReadEnabled : autoReadEnabled // ignore: cast_nullable_to_non_nullable
as bool,speechRate: null == speechRate ? _self.speechRate : speechRate // ignore: cast_nullable_to_non_nullable
as double,voiceModeAutoStop: null == voiceModeAutoStop ? _self.voiceModeAutoStop : voiceModeAutoStop // ignore: cast_nullable_to_non_nullable
as bool,whisperUrl: null == whisperUrl ? _self.whisperUrl : whisperUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxUrl: null == voicevoxUrl ? _self.voicevoxUrl : voicevoxUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxSpeakerId: null == voicevoxSpeakerId ? _self.voicevoxSpeakerId : voicevoxSpeakerId // ignore: cast_nullable_to_non_nullable
as int,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
as AssistantMode,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
