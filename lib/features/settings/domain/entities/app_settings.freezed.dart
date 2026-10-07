// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LocalCommandPermissionRule {

 String get id; bool get enabled;@JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask) LocalCommandPermissionAction get action;@JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact) LocalCommandPermissionMatch get match; String get pattern; String get workingDirectory; DateTime? get createdAt;
/// Create a copy of LocalCommandPermissionRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalCommandPermissionRuleCopyWith<LocalCommandPermissionRule> get copyWith => _$LocalCommandPermissionRuleCopyWithImpl<LocalCommandPermissionRule>(this as LocalCommandPermissionRule, _$identity);

  /// Serializes this LocalCommandPermissionRule to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LocalCommandPermissionRule;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalCommandPermissionRule&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.match, _this.match) || other.match == _this.match)&&(identical(other.pattern, _this.pattern) || other.pattern == _this.pattern)&&(identical(other.workingDirectory, _this.workingDirectory) || other.workingDirectory == _this.workingDirectory)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LocalCommandPermissionRule;
  return Object.hash(runtimeType,_this.id,_this.enabled,_this.action,_this.match,_this.pattern,_this.workingDirectory,_this.createdAt);
}

@override
String toString() {
  final _this = this as LocalCommandPermissionRule;
  return 'LocalCommandPermissionRule(id: ${_this.id}, enabled: ${_this.enabled}, action: ${_this.action}, match: ${_this.match}, pattern: ${_this.pattern}, workingDirectory: ${_this.workingDirectory}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $LocalCommandPermissionRuleCopyWith<$Res>  {
  factory $LocalCommandPermissionRuleCopyWith(LocalCommandPermissionRule value, $Res Function(LocalCommandPermissionRule) _then) = _$LocalCommandPermissionRuleCopyWithImpl;
@useResult
$Res call({
 String id, bool enabled,@JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask) LocalCommandPermissionAction action,@JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact) LocalCommandPermissionMatch match, String pattern, String workingDirectory, DateTime? createdAt
});




}
/// @nodoc
class _$LocalCommandPermissionRuleCopyWithImpl<$Res>
    implements $LocalCommandPermissionRuleCopyWith<$Res> {
  _$LocalCommandPermissionRuleCopyWithImpl(this._self, this._then);

  final LocalCommandPermissionRule _self;
  final $Res Function(LocalCommandPermissionRule) _then;

/// Create a copy of LocalCommandPermissionRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? enabled = null,Object? action = null,Object? match = null,Object? pattern = null,Object? workingDirectory = null,Object? createdAt = freezed,}) {
  return _then(LocalCommandPermissionRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as LocalCommandPermissionAction,match: null == match ? _self.match : match // ignore: cast_nullable_to_non_nullable
as LocalCommandPermissionMatch,pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,workingDirectory: null == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [LocalCommandPermissionRule].
extension LocalCommandPermissionRulePatterns on LocalCommandPermissionRule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LocalCommandPermissionRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LocalCommandPermissionRule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LocalCommandPermissionRule value)  $default,){
final _that = this;
switch (_that) {
case _LocalCommandPermissionRule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LocalCommandPermissionRule value)?  $default,){
final _that = this;
switch (_that) {
case _LocalCommandPermissionRule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  bool enabled, @JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask)  LocalCommandPermissionAction action, @JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact)  LocalCommandPermissionMatch match,  String pattern,  String workingDirectory,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LocalCommandPermissionRule() when $default != null:
return $default(_that.id,_that.enabled,_that.action,_that.match,_that.pattern,_that.workingDirectory,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  bool enabled, @JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask)  LocalCommandPermissionAction action, @JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact)  LocalCommandPermissionMatch match,  String pattern,  String workingDirectory,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _LocalCommandPermissionRule():
return $default(_that.id,_that.enabled,_that.action,_that.match,_that.pattern,_that.workingDirectory,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  bool enabled, @JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask)  LocalCommandPermissionAction action, @JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact)  LocalCommandPermissionMatch match,  String pattern,  String workingDirectory,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _LocalCommandPermissionRule() when $default != null:
return $default(_that.id,_that.enabled,_that.action,_that.match,_that.pattern,_that.workingDirectory,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LocalCommandPermissionRule extends LocalCommandPermissionRule {
  const _LocalCommandPermissionRule({required this.id, this.enabled = true, @JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask) this.action = LocalCommandPermissionAction.ask, @JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact) this.match = LocalCommandPermissionMatch.exact, this.pattern = '', this.workingDirectory = '', this.createdAt}): super._();
  factory _LocalCommandPermissionRule.fromJson(Map<String, dynamic> json) => _$LocalCommandPermissionRuleFromJson(json);

@override final  String id;
@override@JsonKey() final  bool enabled;
@override@JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask) final  LocalCommandPermissionAction action;
@override@JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact) final  LocalCommandPermissionMatch match;
@override@JsonKey() final  String pattern;
@override@JsonKey() final  String workingDirectory;
@override final  DateTime? createdAt;

/// Create a copy of LocalCommandPermissionRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocalCommandPermissionRuleCopyWith<_LocalCommandPermissionRule> get copyWith => __$LocalCommandPermissionRuleCopyWithImpl<_LocalCommandPermissionRule>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LocalCommandPermissionRuleToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LocalCommandPermissionRule&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.action, action) || other.action == action)&&(identical(other.match, match) || other.match == match)&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,enabled,action,match,pattern,workingDirectory,createdAt);
}

@override
String toString() {
    return 'LocalCommandPermissionRule(id: $id, enabled: $enabled, action: $action, match: $match, pattern: $pattern, workingDirectory: $workingDirectory, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$LocalCommandPermissionRuleCopyWith<$Res> implements $LocalCommandPermissionRuleCopyWith<$Res> {
  factory _$LocalCommandPermissionRuleCopyWith(_LocalCommandPermissionRule value, $Res Function(_LocalCommandPermissionRule) _then) = __$LocalCommandPermissionRuleCopyWithImpl;
@override @useResult
$Res call({
 String id, bool enabled,@JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask) LocalCommandPermissionAction action,@JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact) LocalCommandPermissionMatch match, String pattern, String workingDirectory, DateTime? createdAt
});




}
/// @nodoc
class __$LocalCommandPermissionRuleCopyWithImpl<$Res>
    implements _$LocalCommandPermissionRuleCopyWith<$Res> {
  __$LocalCommandPermissionRuleCopyWithImpl(this._self, this._then);

  final _LocalCommandPermissionRule _self;
  final $Res Function(_LocalCommandPermissionRule) _then;

/// Create a copy of LocalCommandPermissionRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? enabled = null,Object? action = null,Object? match = null,Object? pattern = null,Object? workingDirectory = null,Object? createdAt = freezed,}) {
  return _then(_LocalCommandPermissionRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as LocalCommandPermissionAction,match: null == match ? _self.match : match // ignore: cast_nullable_to_non_nullable
as LocalCommandPermissionMatch,pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,workingDirectory: null == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$RoutineComputerUseActionAllowlistEntry {

 String get id; bool get enabled; String get label; String get toolName; String get targetLabelContains; String get targetRole; String get targetAction; String get targetRisk; String get appNameContains; String get appBundleId; String get windowTitleContains; String get urlHost; String get urlStartsWith; String get exactText;
/// Create a copy of RoutineComputerUseActionAllowlistEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineComputerUseActionAllowlistEntryCopyWith<RoutineComputerUseActionAllowlistEntry> get copyWith => _$RoutineComputerUseActionAllowlistEntryCopyWithImpl<RoutineComputerUseActionAllowlistEntry>(this as RoutineComputerUseActionAllowlistEntry, _$identity);

  /// Serializes this RoutineComputerUseActionAllowlistEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RoutineComputerUseActionAllowlistEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineComputerUseActionAllowlistEntry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.toolName, _this.toolName) || other.toolName == _this.toolName)&&(identical(other.targetLabelContains, _this.targetLabelContains) || other.targetLabelContains == _this.targetLabelContains)&&(identical(other.targetRole, _this.targetRole) || other.targetRole == _this.targetRole)&&(identical(other.targetAction, _this.targetAction) || other.targetAction == _this.targetAction)&&(identical(other.targetRisk, _this.targetRisk) || other.targetRisk == _this.targetRisk)&&(identical(other.appNameContains, _this.appNameContains) || other.appNameContains == _this.appNameContains)&&(identical(other.appBundleId, _this.appBundleId) || other.appBundleId == _this.appBundleId)&&(identical(other.windowTitleContains, _this.windowTitleContains) || other.windowTitleContains == _this.windowTitleContains)&&(identical(other.urlHost, _this.urlHost) || other.urlHost == _this.urlHost)&&(identical(other.urlStartsWith, _this.urlStartsWith) || other.urlStartsWith == _this.urlStartsWith)&&(identical(other.exactText, _this.exactText) || other.exactText == _this.exactText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RoutineComputerUseActionAllowlistEntry;
  return Object.hash(runtimeType,_this.id,_this.enabled,_this.label,_this.toolName,_this.targetLabelContains,_this.targetRole,_this.targetAction,_this.targetRisk,_this.appNameContains,_this.appBundleId,_this.windowTitleContains,_this.urlHost,_this.urlStartsWith,_this.exactText);
}

@override
String toString() {
  final _this = this as RoutineComputerUseActionAllowlistEntry;
  return 'RoutineComputerUseActionAllowlistEntry(id: ${_this.id}, enabled: ${_this.enabled}, label: ${_this.label}, toolName: ${_this.toolName}, targetLabelContains: ${_this.targetLabelContains}, targetRole: ${_this.targetRole}, targetAction: ${_this.targetAction}, targetRisk: ${_this.targetRisk}, appNameContains: ${_this.appNameContains}, appBundleId: ${_this.appBundleId}, windowTitleContains: ${_this.windowTitleContains}, urlHost: ${_this.urlHost}, urlStartsWith: ${_this.urlStartsWith}, exactText: ${_this.exactText})';
}


}

/// @nodoc
abstract mixin class $RoutineComputerUseActionAllowlistEntryCopyWith<$Res>  {
  factory $RoutineComputerUseActionAllowlistEntryCopyWith(RoutineComputerUseActionAllowlistEntry value, $Res Function(RoutineComputerUseActionAllowlistEntry) _then) = _$RoutineComputerUseActionAllowlistEntryCopyWithImpl;
@useResult
$Res call({
 String id, bool enabled, String label, String toolName, String targetLabelContains, String targetRole, String targetAction, String targetRisk, String appNameContains, String appBundleId, String windowTitleContains, String urlHost, String urlStartsWith, String exactText
});




}
/// @nodoc
class _$RoutineComputerUseActionAllowlistEntryCopyWithImpl<$Res>
    implements $RoutineComputerUseActionAllowlistEntryCopyWith<$Res> {
  _$RoutineComputerUseActionAllowlistEntryCopyWithImpl(this._self, this._then);

  final RoutineComputerUseActionAllowlistEntry _self;
  final $Res Function(RoutineComputerUseActionAllowlistEntry) _then;

/// Create a copy of RoutineComputerUseActionAllowlistEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? enabled = null,Object? label = null,Object? toolName = null,Object? targetLabelContains = null,Object? targetRole = null,Object? targetAction = null,Object? targetRisk = null,Object? appNameContains = null,Object? appBundleId = null,Object? windowTitleContains = null,Object? urlHost = null,Object? urlStartsWith = null,Object? exactText = null,}) {
  return _then(RoutineComputerUseActionAllowlistEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,toolName: null == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String,targetLabelContains: null == targetLabelContains ? _self.targetLabelContains : targetLabelContains // ignore: cast_nullable_to_non_nullable
as String,targetRole: null == targetRole ? _self.targetRole : targetRole // ignore: cast_nullable_to_non_nullable
as String,targetAction: null == targetAction ? _self.targetAction : targetAction // ignore: cast_nullable_to_non_nullable
as String,targetRisk: null == targetRisk ? _self.targetRisk : targetRisk // ignore: cast_nullable_to_non_nullable
as String,appNameContains: null == appNameContains ? _self.appNameContains : appNameContains // ignore: cast_nullable_to_non_nullable
as String,appBundleId: null == appBundleId ? _self.appBundleId : appBundleId // ignore: cast_nullable_to_non_nullable
as String,windowTitleContains: null == windowTitleContains ? _self.windowTitleContains : windowTitleContains // ignore: cast_nullable_to_non_nullable
as String,urlHost: null == urlHost ? _self.urlHost : urlHost // ignore: cast_nullable_to_non_nullable
as String,urlStartsWith: null == urlStartsWith ? _self.urlStartsWith : urlStartsWith // ignore: cast_nullable_to_non_nullable
as String,exactText: null == exactText ? _self.exactText : exactText // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineComputerUseActionAllowlistEntry].
extension RoutineComputerUseActionAllowlistEntryPatterns on RoutineComputerUseActionAllowlistEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineComputerUseActionAllowlistEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineComputerUseActionAllowlistEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineComputerUseActionAllowlistEntry value)  $default,){
final _that = this;
switch (_that) {
case _RoutineComputerUseActionAllowlistEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineComputerUseActionAllowlistEntry value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineComputerUseActionAllowlistEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  bool enabled,  String label,  String toolName,  String targetLabelContains,  String targetRole,  String targetAction,  String targetRisk,  String appNameContains,  String appBundleId,  String windowTitleContains,  String urlHost,  String urlStartsWith,  String exactText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineComputerUseActionAllowlistEntry() when $default != null:
return $default(_that.id,_that.enabled,_that.label,_that.toolName,_that.targetLabelContains,_that.targetRole,_that.targetAction,_that.targetRisk,_that.appNameContains,_that.appBundleId,_that.windowTitleContains,_that.urlHost,_that.urlStartsWith,_that.exactText);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  bool enabled,  String label,  String toolName,  String targetLabelContains,  String targetRole,  String targetAction,  String targetRisk,  String appNameContains,  String appBundleId,  String windowTitleContains,  String urlHost,  String urlStartsWith,  String exactText)  $default,) {final _that = this;
switch (_that) {
case _RoutineComputerUseActionAllowlistEntry():
return $default(_that.id,_that.enabled,_that.label,_that.toolName,_that.targetLabelContains,_that.targetRole,_that.targetAction,_that.targetRisk,_that.appNameContains,_that.appBundleId,_that.windowTitleContains,_that.urlHost,_that.urlStartsWith,_that.exactText);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  bool enabled,  String label,  String toolName,  String targetLabelContains,  String targetRole,  String targetAction,  String targetRisk,  String appNameContains,  String appBundleId,  String windowTitleContains,  String urlHost,  String urlStartsWith,  String exactText)?  $default,) {final _that = this;
switch (_that) {
case _RoutineComputerUseActionAllowlistEntry() when $default != null:
return $default(_that.id,_that.enabled,_that.label,_that.toolName,_that.targetLabelContains,_that.targetRole,_that.targetAction,_that.targetRisk,_that.appNameContains,_that.appBundleId,_that.windowTitleContains,_that.urlHost,_that.urlStartsWith,_that.exactText);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineComputerUseActionAllowlistEntry extends RoutineComputerUseActionAllowlistEntry {
  const _RoutineComputerUseActionAllowlistEntry({required this.id, this.enabled = true, this.label = '', this.toolName = '', this.targetLabelContains = '', this.targetRole = '', this.targetAction = '', this.targetRisk = '', this.appNameContains = '', this.appBundleId = '', this.windowTitleContains = '', this.urlHost = '', this.urlStartsWith = '', this.exactText = ''}): super._();
  factory _RoutineComputerUseActionAllowlistEntry.fromJson(Map<String, dynamic> json) => _$RoutineComputerUseActionAllowlistEntryFromJson(json);

@override final  String id;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  String label;
@override@JsonKey() final  String toolName;
@override@JsonKey() final  String targetLabelContains;
@override@JsonKey() final  String targetRole;
@override@JsonKey() final  String targetAction;
@override@JsonKey() final  String targetRisk;
@override@JsonKey() final  String appNameContains;
@override@JsonKey() final  String appBundleId;
@override@JsonKey() final  String windowTitleContains;
@override@JsonKey() final  String urlHost;
@override@JsonKey() final  String urlStartsWith;
@override@JsonKey() final  String exactText;

/// Create a copy of RoutineComputerUseActionAllowlistEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineComputerUseActionAllowlistEntryCopyWith<_RoutineComputerUseActionAllowlistEntry> get copyWith => __$RoutineComputerUseActionAllowlistEntryCopyWithImpl<_RoutineComputerUseActionAllowlistEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineComputerUseActionAllowlistEntryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineComputerUseActionAllowlistEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.label, label) || other.label == label)&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.targetLabelContains, targetLabelContains) || other.targetLabelContains == targetLabelContains)&&(identical(other.targetRole, targetRole) || other.targetRole == targetRole)&&(identical(other.targetAction, targetAction) || other.targetAction == targetAction)&&(identical(other.targetRisk, targetRisk) || other.targetRisk == targetRisk)&&(identical(other.appNameContains, appNameContains) || other.appNameContains == appNameContains)&&(identical(other.appBundleId, appBundleId) || other.appBundleId == appBundleId)&&(identical(other.windowTitleContains, windowTitleContains) || other.windowTitleContains == windowTitleContains)&&(identical(other.urlHost, urlHost) || other.urlHost == urlHost)&&(identical(other.urlStartsWith, urlStartsWith) || other.urlStartsWith == urlStartsWith)&&(identical(other.exactText, exactText) || other.exactText == exactText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,enabled,label,toolName,targetLabelContains,targetRole,targetAction,targetRisk,appNameContains,appBundleId,windowTitleContains,urlHost,urlStartsWith,exactText);
}

@override
String toString() {
    return 'RoutineComputerUseActionAllowlistEntry(id: $id, enabled: $enabled, label: $label, toolName: $toolName, targetLabelContains: $targetLabelContains, targetRole: $targetRole, targetAction: $targetAction, targetRisk: $targetRisk, appNameContains: $appNameContains, appBundleId: $appBundleId, windowTitleContains: $windowTitleContains, urlHost: $urlHost, urlStartsWith: $urlStartsWith, exactText: $exactText)';
}


}

/// @nodoc
abstract mixin class _$RoutineComputerUseActionAllowlistEntryCopyWith<$Res> implements $RoutineComputerUseActionAllowlistEntryCopyWith<$Res> {
  factory _$RoutineComputerUseActionAllowlistEntryCopyWith(_RoutineComputerUseActionAllowlistEntry value, $Res Function(_RoutineComputerUseActionAllowlistEntry) _then) = __$RoutineComputerUseActionAllowlistEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, bool enabled, String label, String toolName, String targetLabelContains, String targetRole, String targetAction, String targetRisk, String appNameContains, String appBundleId, String windowTitleContains, String urlHost, String urlStartsWith, String exactText
});




}
/// @nodoc
class __$RoutineComputerUseActionAllowlistEntryCopyWithImpl<$Res>
    implements _$RoutineComputerUseActionAllowlistEntryCopyWith<$Res> {
  __$RoutineComputerUseActionAllowlistEntryCopyWithImpl(this._self, this._then);

  final _RoutineComputerUseActionAllowlistEntry _self;
  final $Res Function(_RoutineComputerUseActionAllowlistEntry) _then;

/// Create a copy of RoutineComputerUseActionAllowlistEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? enabled = null,Object? label = null,Object? toolName = null,Object? targetLabelContains = null,Object? targetRole = null,Object? targetAction = null,Object? targetRisk = null,Object? appNameContains = null,Object? appBundleId = null,Object? windowTitleContains = null,Object? urlHost = null,Object? urlStartsWith = null,Object? exactText = null,}) {
  return _then(_RoutineComputerUseActionAllowlistEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,toolName: null == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String,targetLabelContains: null == targetLabelContains ? _self.targetLabelContains : targetLabelContains // ignore: cast_nullable_to_non_nullable
as String,targetRole: null == targetRole ? _self.targetRole : targetRole // ignore: cast_nullable_to_non_nullable
as String,targetAction: null == targetAction ? _self.targetAction : targetAction // ignore: cast_nullable_to_non_nullable
as String,targetRisk: null == targetRisk ? _self.targetRisk : targetRisk // ignore: cast_nullable_to_non_nullable
as String,appNameContains: null == appNameContains ? _self.appNameContains : appNameContains // ignore: cast_nullable_to_non_nullable
as String,appBundleId: null == appBundleId ? _self.appBundleId : appBundleId // ignore: cast_nullable_to_non_nullable
as String,windowTitleContains: null == windowTitleContains ? _self.windowTitleContains : windowTitleContains // ignore: cast_nullable_to_non_nullable
as String,urlHost: null == urlHost ? _self.urlHost : urlHost // ignore: cast_nullable_to_non_nullable
as String,urlStartsWith: null == urlStartsWith ? _self.urlStartsWith : urlStartsWith // ignore: cast_nullable_to_non_nullable
as String,exactText: null == exactText ? _self.exactText : exactText // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$McpServerConfig {

 String get url; bool get enabled;@JsonKey(unknownEnumValue: McpServerType.http) McpServerType get type;@JsonKey(unknownEnumValue: McpServerTrustState.trusted) McpServerTrustState get trustState; String get command; List<String> get args; Map<String, String> get env; String get sourceId; DateTime? get trustedAt;
/// Create a copy of McpServerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerConfigCopyWith<McpServerConfig> get copyWith => _$McpServerConfigCopyWithImpl<McpServerConfig>(this as McpServerConfig, _$identity);

  /// Serializes this McpServerConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as McpServerConfig;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerConfig&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.trustState, _this.trustState) || other.trustState == _this.trustState)&&(identical(other.command, _this.command) || other.command == _this.command)&&const DeepCollectionEquality().equals(other.args, _this.args)&&const DeepCollectionEquality().equals(other.env, _this.env)&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.trustedAt, _this.trustedAt) || other.trustedAt == _this.trustedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as McpServerConfig;
  return Object.hash(runtimeType,_this.url,_this.enabled,_this.type,_this.trustState,_this.command,const DeepCollectionEquality().hash(_this.args),const DeepCollectionEquality().hash(_this.env),_this.sourceId,_this.trustedAt);
}

@override
String toString() {
  final _this = this as McpServerConfig;
  return 'McpServerConfig(url: ${_this.url}, enabled: ${_this.enabled}, type: ${_this.type}, trustState: ${_this.trustState}, command: ${_this.command}, args: ${_this.args}, env: ${_this.env}, sourceId: ${_this.sourceId}, trustedAt: ${_this.trustedAt})';
}


}

/// @nodoc
abstract mixin class $McpServerConfigCopyWith<$Res>  {
  factory $McpServerConfigCopyWith(McpServerConfig value, $Res Function(McpServerConfig) _then) = _$McpServerConfigCopyWithImpl;
@useResult
$Res call({
 String url, bool enabled,@JsonKey(unknownEnumValue: McpServerType.http) McpServerType type,@JsonKey(unknownEnumValue: McpServerTrustState.trusted) McpServerTrustState trustState, String command, List<String> args, Map<String, String> env, String sourceId, DateTime? trustedAt
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
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? enabled = null,Object? type = null,Object? trustState = null,Object? command = null,Object? args = null,Object? env = null,Object? sourceId = null,Object? trustedAt = freezed,}) {
  return _then(McpServerConfig(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as McpServerType,trustState: null == trustState ? _self.trustState : trustState // ignore: cast_nullable_to_non_nullable
as McpServerTrustState,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,trustedAt: freezed == trustedAt ? _self.trustedAt : trustedAt // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  bool enabled, @JsonKey(unknownEnumValue: McpServerType.http)  McpServerType type, @JsonKey(unknownEnumValue: McpServerTrustState.trusted)  McpServerTrustState trustState,  String command,  List<String> args,  Map<String, String> env,  String sourceId,  DateTime? trustedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpServerConfig() when $default != null:
return $default(_that.url,_that.enabled,_that.type,_that.trustState,_that.command,_that.args,_that.env,_that.sourceId,_that.trustedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  bool enabled, @JsonKey(unknownEnumValue: McpServerType.http)  McpServerType type, @JsonKey(unknownEnumValue: McpServerTrustState.trusted)  McpServerTrustState trustState,  String command,  List<String> args,  Map<String, String> env,  String sourceId,  DateTime? trustedAt)  $default,) {final _that = this;
switch (_that) {
case _McpServerConfig():
return $default(_that.url,_that.enabled,_that.type,_that.trustState,_that.command,_that.args,_that.env,_that.sourceId,_that.trustedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  bool enabled, @JsonKey(unknownEnumValue: McpServerType.http)  McpServerType type, @JsonKey(unknownEnumValue: McpServerTrustState.trusted)  McpServerTrustState trustState,  String command,  List<String> args,  Map<String, String> env,  String sourceId,  DateTime? trustedAt)?  $default,) {final _that = this;
switch (_that) {
case _McpServerConfig() when $default != null:
return $default(_that.url,_that.enabled,_that.type,_that.trustState,_that.command,_that.args,_that.env,_that.sourceId,_that.trustedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _McpServerConfig extends McpServerConfig {
  const _McpServerConfig({this.url = '', this.enabled = true, @JsonKey(unknownEnumValue: McpServerType.http) this.type = McpServerType.http, @JsonKey(unknownEnumValue: McpServerTrustState.trusted) this.trustState = McpServerTrustState.trusted, this.command = '',  List<String> args = const <String>[],  Map<String, String> env = const <String, String>{}, this.sourceId = '', this.trustedAt}): _args = args,_env = env,super._();
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

 final  Map<String, String> _env;
@override@JsonKey() Map<String, String> get env {
  if (_env is EqualUnmodifiableMapView) return _env;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_env);
}

@override@JsonKey() final  String sourceId;
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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpServerConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.type, type) || other.type == type)&&(identical(other.trustState, trustState) || other.trustState == trustState)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, _args)&&const DeepCollectionEquality().equals(other.env, _env)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.trustedAt, trustedAt) || other.trustedAt == trustedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,url,enabled,type,trustState,command,const DeepCollectionEquality().hash(_args),const DeepCollectionEquality().hash(_env),sourceId,trustedAt);
}

@override
String toString() {
    return 'McpServerConfig(url: $url, enabled: $enabled, type: $type, trustState: $trustState, command: $command, args: $args, env: $env, sourceId: $sourceId, trustedAt: $trustedAt)';
}


}

/// @nodoc
abstract mixin class _$McpServerConfigCopyWith<$Res> implements $McpServerConfigCopyWith<$Res> {
  factory _$McpServerConfigCopyWith(_McpServerConfig value, $Res Function(_McpServerConfig) _then) = __$McpServerConfigCopyWithImpl;
@override @useResult
$Res call({
 String url, bool enabled,@JsonKey(unknownEnumValue: McpServerType.http) McpServerType type,@JsonKey(unknownEnumValue: McpServerTrustState.trusted) McpServerTrustState trustState, String command, List<String> args, Map<String, String> env, String sourceId, DateTime? trustedAt
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
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? enabled = null,Object? type = null,Object? trustState = null,Object? command = null,Object? args = null,Object? env = null,Object? sourceId = null,Object? trustedAt = freezed,}) {
  return _then(_McpServerConfig(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as McpServerType,trustState: null == trustState ? _self.trustState : trustState // ignore: cast_nullable_to_non_nullable
as McpServerTrustState,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,trustedAt: freezed == trustedAt ? _self.trustedAt : trustedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$ExternalToolHook {

 String get id; bool get enabled; String get event; String get command; List<String> get args; Map<String, String> get env; String get sourceId; DateTime? get reviewedAt;
/// Create a copy of ExternalToolHook
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExternalToolHookCopyWith<ExternalToolHook> get copyWith => _$ExternalToolHookCopyWithImpl<ExternalToolHook>(this as ExternalToolHook, _$identity);

  /// Serializes this ExternalToolHook to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ExternalToolHook;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExternalToolHook&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.event, _this.event) || other.event == _this.event)&&(identical(other.command, _this.command) || other.command == _this.command)&&const DeepCollectionEquality().equals(other.args, _this.args)&&const DeepCollectionEquality().equals(other.env, _this.env)&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.reviewedAt, _this.reviewedAt) || other.reviewedAt == _this.reviewedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ExternalToolHook;
  return Object.hash(runtimeType,_this.id,_this.enabled,_this.event,_this.command,const DeepCollectionEquality().hash(_this.args),const DeepCollectionEquality().hash(_this.env),_this.sourceId,_this.reviewedAt);
}

@override
String toString() {
  final _this = this as ExternalToolHook;
  return 'ExternalToolHook(id: ${_this.id}, enabled: ${_this.enabled}, event: ${_this.event}, command: ${_this.command}, args: ${_this.args}, env: ${_this.env}, sourceId: ${_this.sourceId}, reviewedAt: ${_this.reviewedAt})';
}


}

/// @nodoc
abstract mixin class $ExternalToolHookCopyWith<$Res>  {
  factory $ExternalToolHookCopyWith(ExternalToolHook value, $Res Function(ExternalToolHook) _then) = _$ExternalToolHookCopyWithImpl;
@useResult
$Res call({
 String id, bool enabled, String event, String command, List<String> args, Map<String, String> env, String sourceId, DateTime? reviewedAt
});




}
/// @nodoc
class _$ExternalToolHookCopyWithImpl<$Res>
    implements $ExternalToolHookCopyWith<$Res> {
  _$ExternalToolHookCopyWithImpl(this._self, this._then);

  final ExternalToolHook _self;
  final $Res Function(ExternalToolHook) _then;

/// Create a copy of ExternalToolHook
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? enabled = null,Object? event = null,Object? command = null,Object? args = null,Object? env = null,Object? sourceId = null,Object? reviewedAt = freezed,}) {
  return _then(ExternalToolHook(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,reviewedAt: freezed == reviewedAt ? _self.reviewedAt : reviewedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ExternalToolHook].
extension ExternalToolHookPatterns on ExternalToolHook {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExternalToolHook value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExternalToolHook() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExternalToolHook value)  $default,){
final _that = this;
switch (_that) {
case _ExternalToolHook():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExternalToolHook value)?  $default,){
final _that = this;
switch (_that) {
case _ExternalToolHook() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  bool enabled,  String event,  String command,  List<String> args,  Map<String, String> env,  String sourceId,  DateTime? reviewedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExternalToolHook() when $default != null:
return $default(_that.id,_that.enabled,_that.event,_that.command,_that.args,_that.env,_that.sourceId,_that.reviewedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  bool enabled,  String event,  String command,  List<String> args,  Map<String, String> env,  String sourceId,  DateTime? reviewedAt)  $default,) {final _that = this;
switch (_that) {
case _ExternalToolHook():
return $default(_that.id,_that.enabled,_that.event,_that.command,_that.args,_that.env,_that.sourceId,_that.reviewedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  bool enabled,  String event,  String command,  List<String> args,  Map<String, String> env,  String sourceId,  DateTime? reviewedAt)?  $default,) {final _that = this;
switch (_that) {
case _ExternalToolHook() when $default != null:
return $default(_that.id,_that.enabled,_that.event,_that.command,_that.args,_that.env,_that.sourceId,_that.reviewedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExternalToolHook extends ExternalToolHook {
  const _ExternalToolHook({required this.id, this.enabled = true, this.event = '', this.command = '',  List<String> args = const <String>[],  Map<String, String> env = const <String, String>{}, this.sourceId = '', this.reviewedAt}): _args = args,_env = env,super._();
  factory _ExternalToolHook.fromJson(Map<String, dynamic> json) => _$ExternalToolHookFromJson(json);

@override final  String id;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  String event;
@override@JsonKey() final  String command;
 final  List<String> _args;
@override@JsonKey() List<String> get args {
  if (_args is EqualUnmodifiableListView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_args);
}

 final  Map<String, String> _env;
@override@JsonKey() Map<String, String> get env {
  if (_env is EqualUnmodifiableMapView) return _env;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_env);
}

@override@JsonKey() final  String sourceId;
@override final  DateTime? reviewedAt;

/// Create a copy of ExternalToolHook
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExternalToolHookCopyWith<_ExternalToolHook> get copyWith => __$ExternalToolHookCopyWithImpl<_ExternalToolHook>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExternalToolHookToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExternalToolHook&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.event, event) || other.event == event)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, _args)&&const DeepCollectionEquality().equals(other.env, _env)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.reviewedAt, reviewedAt) || other.reviewedAt == reviewedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,enabled,event,command,const DeepCollectionEquality().hash(_args),const DeepCollectionEquality().hash(_env),sourceId,reviewedAt);
}

@override
String toString() {
    return 'ExternalToolHook(id: $id, enabled: $enabled, event: $event, command: $command, args: $args, env: $env, sourceId: $sourceId, reviewedAt: $reviewedAt)';
}


}

/// @nodoc
abstract mixin class _$ExternalToolHookCopyWith<$Res> implements $ExternalToolHookCopyWith<$Res> {
  factory _$ExternalToolHookCopyWith(_ExternalToolHook value, $Res Function(_ExternalToolHook) _then) = __$ExternalToolHookCopyWithImpl;
@override @useResult
$Res call({
 String id, bool enabled, String event, String command, List<String> args, Map<String, String> env, String sourceId, DateTime? reviewedAt
});




}
/// @nodoc
class __$ExternalToolHookCopyWithImpl<$Res>
    implements _$ExternalToolHookCopyWith<$Res> {
  __$ExternalToolHookCopyWithImpl(this._self, this._then);

  final _ExternalToolHook _self;
  final $Res Function(_ExternalToolHook) _then;

/// Create a copy of ExternalToolHook
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? enabled = null,Object? event = null,Object? command = null,Object? args = null,Object? env = null,Object? sourceId = null,Object? reviewedAt = freezed,}) {
  return _then(_ExternalToolHook(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,reviewedAt: freezed == reviewedAt ? _self.reviewedAt : reviewedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$ModelCapabilityProfile {

 String get id;@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider get provider; String get baseUrl; String get model;@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle get toolCallStyle;@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport get structuredOutputSupport;@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) ModelGoalUpdateFidelity get goalUpdateFidelity;@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference get editFormatPreference;@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) ModelVisionSupport get visionSupport;@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) ModelVideoInputSupport get videoInputSupport; int get usableContextTokens;/// The `reasoning_effort` values the endpoint accepted for this model, as
/// measured by `ReasoningEffortProbe`. Null when never measured or when the
/// endpoint refused none of them, which cannot tell "accepts all" from
/// "ignores the field"; the composer then offers every effort.
 List<String>? get supportedReasoningEfforts; DateTime? get probedAt; String get probeSummary; Map<String, String> get probeMetadata;
/// Create a copy of ModelCapabilityProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCapabilityProfileCopyWith<ModelCapabilityProfile> get copyWith => _$ModelCapabilityProfileCopyWithImpl<ModelCapabilityProfile>(this as ModelCapabilityProfile, _$identity);

  /// Serializes this ModelCapabilityProfile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ModelCapabilityProfile;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCapabilityProfile&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.toolCallStyle, _this.toolCallStyle) || other.toolCallStyle == _this.toolCallStyle)&&(identical(other.structuredOutputSupport, _this.structuredOutputSupport) || other.structuredOutputSupport == _this.structuredOutputSupport)&&(identical(other.goalUpdateFidelity, _this.goalUpdateFidelity) || other.goalUpdateFidelity == _this.goalUpdateFidelity)&&(identical(other.editFormatPreference, _this.editFormatPreference) || other.editFormatPreference == _this.editFormatPreference)&&(identical(other.visionSupport, _this.visionSupport) || other.visionSupport == _this.visionSupport)&&(identical(other.videoInputSupport, _this.videoInputSupport) || other.videoInputSupport == _this.videoInputSupport)&&(identical(other.usableContextTokens, _this.usableContextTokens) || other.usableContextTokens == _this.usableContextTokens)&&const DeepCollectionEquality().equals(other.supportedReasoningEfforts, _this.supportedReasoningEfforts)&&(identical(other.probedAt, _this.probedAt) || other.probedAt == _this.probedAt)&&(identical(other.probeSummary, _this.probeSummary) || other.probeSummary == _this.probeSummary)&&const DeepCollectionEquality().equals(other.probeMetadata, _this.probeMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ModelCapabilityProfile;
  return Object.hash(runtimeType,_this.id,_this.provider,_this.baseUrl,_this.model,_this.toolCallStyle,_this.structuredOutputSupport,_this.goalUpdateFidelity,_this.editFormatPreference,_this.visionSupport,_this.videoInputSupport,_this.usableContextTokens,const DeepCollectionEquality().hash(_this.supportedReasoningEfforts),_this.probedAt,_this.probeSummary,const DeepCollectionEquality().hash(_this.probeMetadata));
}

@override
String toString() {
  final _this = this as ModelCapabilityProfile;
  return 'ModelCapabilityProfile(id: ${_this.id}, provider: ${_this.provider}, baseUrl: ${_this.baseUrl}, model: ${_this.model}, toolCallStyle: ${_this.toolCallStyle}, structuredOutputSupport: ${_this.structuredOutputSupport}, goalUpdateFidelity: ${_this.goalUpdateFidelity}, editFormatPreference: ${_this.editFormatPreference}, visionSupport: ${_this.visionSupport}, videoInputSupport: ${_this.videoInputSupport}, usableContextTokens: ${_this.usableContextTokens}, supportedReasoningEfforts: ${_this.supportedReasoningEfforts}, probedAt: ${_this.probedAt}, probeSummary: ${_this.probeSummary}, probeMetadata: ${_this.probeMetadata})';
}


}

/// @nodoc
abstract mixin class $ModelCapabilityProfileCopyWith<$Res>  {
  factory $ModelCapabilityProfileCopyWith(ModelCapabilityProfile value, $Res Function(ModelCapabilityProfile) _then) = _$ModelCapabilityProfileCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) ModelGoalUpdateFidelity goalUpdateFidelity,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference,@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) ModelVisionSupport visionSupport,@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) ModelVideoInputSupport videoInputSupport, int usableContextTokens, List<String>? supportedReasoningEfforts, DateTime? probedAt, String probeSummary, Map<String, String> probeMetadata
});




}
/// @nodoc
class _$ModelCapabilityProfileCopyWithImpl<$Res>
    implements $ModelCapabilityProfileCopyWith<$Res> {
  _$ModelCapabilityProfileCopyWithImpl(this._self, this._then);

  final ModelCapabilityProfile _self;
  final $Res Function(ModelCapabilityProfile) _then;

/// Create a copy of ModelCapabilityProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? goalUpdateFidelity = null,Object? editFormatPreference = null,Object? visionSupport = null,Object? videoInputSupport = null,Object? usableContextTokens = null,Object? supportedReasoningEfforts = freezed,Object? probedAt = freezed,Object? probeSummary = null,Object? probeMetadata = null,}) {
  return _then(ModelCapabilityProfile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,goalUpdateFidelity: null == goalUpdateFidelity ? _self.goalUpdateFidelity : goalUpdateFidelity // ignore: cast_nullable_to_non_nullable
as ModelGoalUpdateFidelity,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,visionSupport: null == visionSupport ? _self.visionSupport : visionSupport // ignore: cast_nullable_to_non_nullable
as ModelVisionSupport,videoInputSupport: null == videoInputSupport ? _self.videoInputSupport : videoInputSupport // ignore: cast_nullable_to_non_nullable
as ModelVideoInputSupport,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,supportedReasoningEfforts: freezed == supportedReasoningEfforts ? _self.supportedReasoningEfforts : supportedReasoningEfforts // ignore: cast_nullable_to_non_nullable
as List<String>?,probedAt: freezed == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,probeMetadata: null == probeMetadata ? _self.probeMetadata : probeMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelCapabilityProfile].
extension ModelCapabilityProfilePatterns on ModelCapabilityProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCapabilityProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCapabilityProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCapabilityProfile value)  $default,){
final _that = this;
switch (_that) {
case _ModelCapabilityProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCapabilityProfile value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCapabilityProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)  ModelGoalUpdateFidelity goalUpdateFidelity, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)  ModelVisionSupport visionSupport, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown)  ModelVideoInputSupport videoInputSupport,  int usableContextTokens,  List<String>? supportedReasoningEfforts,  DateTime? probedAt,  String probeSummary,  Map<String, String> probeMetadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCapabilityProfile() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.toolCallStyle,_that.structuredOutputSupport,_that.goalUpdateFidelity,_that.editFormatPreference,_that.visionSupport,_that.videoInputSupport,_that.usableContextTokens,_that.supportedReasoningEfforts,_that.probedAt,_that.probeSummary,_that.probeMetadata);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)  ModelGoalUpdateFidelity goalUpdateFidelity, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)  ModelVisionSupport visionSupport, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown)  ModelVideoInputSupport videoInputSupport,  int usableContextTokens,  List<String>? supportedReasoningEfforts,  DateTime? probedAt,  String probeSummary,  Map<String, String> probeMetadata)  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfile():
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.toolCallStyle,_that.structuredOutputSupport,_that.goalUpdateFidelity,_that.editFormatPreference,_that.visionSupport,_that.videoInputSupport,_that.usableContextTokens,_that.supportedReasoningEfforts,_that.probedAt,_that.probeSummary,_that.probeMetadata);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)  ModelGoalUpdateFidelity goalUpdateFidelity, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)  ModelVisionSupport visionSupport, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown)  ModelVideoInputSupport videoInputSupport,  int usableContextTokens,  List<String>? supportedReasoningEfforts,  DateTime? probedAt,  String probeSummary,  Map<String, String> probeMetadata)?  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfile() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.toolCallStyle,_that.structuredOutputSupport,_that.goalUpdateFidelity,_that.editFormatPreference,_that.visionSupport,_that.videoInputSupport,_that.usableContextTokens,_that.supportedReasoningEfforts,_that.probedAt,_that.probeSummary,_that.probeMetadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelCapabilityProfile extends ModelCapabilityProfile {
  const _ModelCapabilityProfile({required this.id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) this.provider = LlmProvider.openAiCompatible, this.baseUrl = '', required this.model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) this.toolCallStyle = ModelToolCallStyle.unknown, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) this.structuredOutputSupport = ModelStructuredOutputSupport.unknown, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) this.goalUpdateFidelity = ModelGoalUpdateFidelity.unknown, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) this.editFormatPreference = ModelEditFormatPreference.unknown, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown) this.visionSupport = ModelVisionSupport.unknown, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) this.videoInputSupport = ModelVideoInputSupport.unknown, this.usableContextTokens = 0,  List<String>? supportedReasoningEfforts, this.probedAt, this.probeSummary = '',  Map<String, String> probeMetadata = const <String, String>{}}): _supportedReasoningEfforts = supportedReasoningEfforts,_probeMetadata = probeMetadata,super._();
  factory _ModelCapabilityProfile.fromJson(Map<String, dynamic> json) => _$ModelCapabilityProfileFromJson(json);

@override final  String id;
@override@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) final  LlmProvider provider;
@override@JsonKey() final  String baseUrl;
@override final  String model;
@override@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) final  ModelToolCallStyle toolCallStyle;
@override@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) final  ModelStructuredOutputSupport structuredOutputSupport;
@override@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) final  ModelGoalUpdateFidelity goalUpdateFidelity;
@override@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) final  ModelEditFormatPreference editFormatPreference;
@override@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) final  ModelVisionSupport visionSupport;
@override@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) final  ModelVideoInputSupport videoInputSupport;
@override@JsonKey() final  int usableContextTokens;
/// The `reasoning_effort` values the endpoint accepted for this model, as
/// measured by `ReasoningEffortProbe`. Null when never measured or when the
/// endpoint refused none of them, which cannot tell "accepts all" from
/// "ignores the field"; the composer then offers every effort.
 final  List<String>? _supportedReasoningEfforts;
/// The `reasoning_effort` values the endpoint accepted for this model, as
/// measured by `ReasoningEffortProbe`. Null when never measured or when the
/// endpoint refused none of them, which cannot tell "accepts all" from
/// "ignores the field"; the composer then offers every effort.
@override List<String>? get supportedReasoningEfforts {
  final value = _supportedReasoningEfforts;
  if (value == null) return null;
  if (_supportedReasoningEfforts is EqualUnmodifiableListView) return _supportedReasoningEfforts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  DateTime? probedAt;
@override@JsonKey() final  String probeSummary;
 final  Map<String, String> _probeMetadata;
@override@JsonKey() Map<String, String> get probeMetadata {
  if (_probeMetadata is EqualUnmodifiableMapView) return _probeMetadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_probeMetadata);
}


/// Create a copy of ModelCapabilityProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCapabilityProfileCopyWith<_ModelCapabilityProfile> get copyWith => __$ModelCapabilityProfileCopyWithImpl<_ModelCapabilityProfile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelCapabilityProfileToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCapabilityProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.toolCallStyle, toolCallStyle) || other.toolCallStyle == toolCallStyle)&&(identical(other.structuredOutputSupport, structuredOutputSupport) || other.structuredOutputSupport == structuredOutputSupport)&&(identical(other.goalUpdateFidelity, goalUpdateFidelity) || other.goalUpdateFidelity == goalUpdateFidelity)&&(identical(other.editFormatPreference, editFormatPreference) || other.editFormatPreference == editFormatPreference)&&(identical(other.visionSupport, visionSupport) || other.visionSupport == visionSupport)&&(identical(other.videoInputSupport, videoInputSupport) || other.videoInputSupport == videoInputSupport)&&(identical(other.usableContextTokens, usableContextTokens) || other.usableContextTokens == usableContextTokens)&&const DeepCollectionEquality().equals(other.supportedReasoningEfforts, _supportedReasoningEfforts)&&(identical(other.probedAt, probedAt) || other.probedAt == probedAt)&&(identical(other.probeSummary, probeSummary) || other.probeSummary == probeSummary)&&const DeepCollectionEquality().equals(other.probeMetadata, _probeMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,provider,baseUrl,model,toolCallStyle,structuredOutputSupport,goalUpdateFidelity,editFormatPreference,visionSupport,videoInputSupport,usableContextTokens,const DeepCollectionEquality().hash(_supportedReasoningEfforts),probedAt,probeSummary,const DeepCollectionEquality().hash(_probeMetadata));
}

@override
String toString() {
    return 'ModelCapabilityProfile(id: $id, provider: $provider, baseUrl: $baseUrl, model: $model, toolCallStyle: $toolCallStyle, structuredOutputSupport: $structuredOutputSupport, goalUpdateFidelity: $goalUpdateFidelity, editFormatPreference: $editFormatPreference, visionSupport: $visionSupport, videoInputSupport: $videoInputSupport, usableContextTokens: $usableContextTokens, supportedReasoningEfforts: $supportedReasoningEfforts, probedAt: $probedAt, probeSummary: $probeSummary, probeMetadata: $probeMetadata)';
}


}

/// @nodoc
abstract mixin class _$ModelCapabilityProfileCopyWith<$Res> implements $ModelCapabilityProfileCopyWith<$Res> {
  factory _$ModelCapabilityProfileCopyWith(_ModelCapabilityProfile value, $Res Function(_ModelCapabilityProfile) _then) = __$ModelCapabilityProfileCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) ModelGoalUpdateFidelity goalUpdateFidelity,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference,@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) ModelVisionSupport visionSupport,@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) ModelVideoInputSupport videoInputSupport, int usableContextTokens, List<String>? supportedReasoningEfforts, DateTime? probedAt, String probeSummary, Map<String, String> probeMetadata
});




}
/// @nodoc
class __$ModelCapabilityProfileCopyWithImpl<$Res>
    implements _$ModelCapabilityProfileCopyWith<$Res> {
  __$ModelCapabilityProfileCopyWithImpl(this._self, this._then);

  final _ModelCapabilityProfile _self;
  final $Res Function(_ModelCapabilityProfile) _then;

/// Create a copy of ModelCapabilityProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? goalUpdateFidelity = null,Object? editFormatPreference = null,Object? visionSupport = null,Object? videoInputSupport = null,Object? usableContextTokens = null,Object? supportedReasoningEfforts = freezed,Object? probedAt = freezed,Object? probeSummary = null,Object? probeMetadata = null,}) {
  return _then(_ModelCapabilityProfile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,goalUpdateFidelity: null == goalUpdateFidelity ? _self.goalUpdateFidelity : goalUpdateFidelity // ignore: cast_nullable_to_non_nullable
as ModelGoalUpdateFidelity,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,visionSupport: null == visionSupport ? _self.visionSupport : visionSupport // ignore: cast_nullable_to_non_nullable
as ModelVisionSupport,videoInputSupport: null == videoInputSupport ? _self.videoInputSupport : videoInputSupport // ignore: cast_nullable_to_non_nullable
as ModelVideoInputSupport,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,supportedReasoningEfforts: freezed == supportedReasoningEfforts ? _self._supportedReasoningEfforts : supportedReasoningEfforts // ignore: cast_nullable_to_non_nullable
as List<String>?,probedAt: freezed == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,probeMetadata: null == probeMetadata ? _self._probeMetadata : probeMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}


/// @nodoc
mixin _$ModelHarnessConfig {

 String get id;@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider get provider; String get baseUrl; String get model; String get bootstrapInstruction; String get executionInstruction; String get verificationInstruction; String get failureRecoveryInstruction; int get toolLoopMaxIterations; bool get recoveryMiddlewareEnabled; bool get explorationToEditNudgeEnabled; bool get summaryFirstToolResultsEnabled;@JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk) GoalCompletionPolicy get goalCompletionPolicy;
/// Create a copy of ModelHarnessConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelHarnessConfigCopyWith<ModelHarnessConfig> get copyWith => _$ModelHarnessConfigCopyWithImpl<ModelHarnessConfig>(this as ModelHarnessConfig, _$identity);

  /// Serializes this ModelHarnessConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ModelHarnessConfig;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelHarnessConfig&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.bootstrapInstruction, _this.bootstrapInstruction) || other.bootstrapInstruction == _this.bootstrapInstruction)&&(identical(other.executionInstruction, _this.executionInstruction) || other.executionInstruction == _this.executionInstruction)&&(identical(other.verificationInstruction, _this.verificationInstruction) || other.verificationInstruction == _this.verificationInstruction)&&(identical(other.failureRecoveryInstruction, _this.failureRecoveryInstruction) || other.failureRecoveryInstruction == _this.failureRecoveryInstruction)&&(identical(other.toolLoopMaxIterations, _this.toolLoopMaxIterations) || other.toolLoopMaxIterations == _this.toolLoopMaxIterations)&&(identical(other.recoveryMiddlewareEnabled, _this.recoveryMiddlewareEnabled) || other.recoveryMiddlewareEnabled == _this.recoveryMiddlewareEnabled)&&(identical(other.explorationToEditNudgeEnabled, _this.explorationToEditNudgeEnabled) || other.explorationToEditNudgeEnabled == _this.explorationToEditNudgeEnabled)&&(identical(other.summaryFirstToolResultsEnabled, _this.summaryFirstToolResultsEnabled) || other.summaryFirstToolResultsEnabled == _this.summaryFirstToolResultsEnabled)&&(identical(other.goalCompletionPolicy, _this.goalCompletionPolicy) || other.goalCompletionPolicy == _this.goalCompletionPolicy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ModelHarnessConfig;
  return Object.hash(runtimeType,_this.id,_this.provider,_this.baseUrl,_this.model,_this.bootstrapInstruction,_this.executionInstruction,_this.verificationInstruction,_this.failureRecoveryInstruction,_this.toolLoopMaxIterations,_this.recoveryMiddlewareEnabled,_this.explorationToEditNudgeEnabled,_this.summaryFirstToolResultsEnabled,_this.goalCompletionPolicy);
}

@override
String toString() {
  final _this = this as ModelHarnessConfig;
  return 'ModelHarnessConfig(id: ${_this.id}, provider: ${_this.provider}, baseUrl: ${_this.baseUrl}, model: ${_this.model}, bootstrapInstruction: ${_this.bootstrapInstruction}, executionInstruction: ${_this.executionInstruction}, verificationInstruction: ${_this.verificationInstruction}, failureRecoveryInstruction: ${_this.failureRecoveryInstruction}, toolLoopMaxIterations: ${_this.toolLoopMaxIterations}, recoveryMiddlewareEnabled: ${_this.recoveryMiddlewareEnabled}, explorationToEditNudgeEnabled: ${_this.explorationToEditNudgeEnabled}, summaryFirstToolResultsEnabled: ${_this.summaryFirstToolResultsEnabled}, goalCompletionPolicy: ${_this.goalCompletionPolicy})';
}


}

/// @nodoc
abstract mixin class $ModelHarnessConfigCopyWith<$Res>  {
  factory $ModelHarnessConfigCopyWith(ModelHarnessConfig value, $Res Function(ModelHarnessConfig) _then) = _$ModelHarnessConfigCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model, String bootstrapInstruction, String executionInstruction, String verificationInstruction, String failureRecoveryInstruction, int toolLoopMaxIterations, bool recoveryMiddlewareEnabled, bool explorationToEditNudgeEnabled, bool summaryFirstToolResultsEnabled,@JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk) GoalCompletionPolicy goalCompletionPolicy
});




}
/// @nodoc
class _$ModelHarnessConfigCopyWithImpl<$Res>
    implements $ModelHarnessConfigCopyWith<$Res> {
  _$ModelHarnessConfigCopyWithImpl(this._self, this._then);

  final ModelHarnessConfig _self;
  final $Res Function(ModelHarnessConfig) _then;

/// Create a copy of ModelHarnessConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? bootstrapInstruction = null,Object? executionInstruction = null,Object? verificationInstruction = null,Object? failureRecoveryInstruction = null,Object? toolLoopMaxIterations = null,Object? recoveryMiddlewareEnabled = null,Object? explorationToEditNudgeEnabled = null,Object? summaryFirstToolResultsEnabled = null,Object? goalCompletionPolicy = null,}) {
  return _then(ModelHarnessConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,bootstrapInstruction: null == bootstrapInstruction ? _self.bootstrapInstruction : bootstrapInstruction // ignore: cast_nullable_to_non_nullable
as String,executionInstruction: null == executionInstruction ? _self.executionInstruction : executionInstruction // ignore: cast_nullable_to_non_nullable
as String,verificationInstruction: null == verificationInstruction ? _self.verificationInstruction : verificationInstruction // ignore: cast_nullable_to_non_nullable
as String,failureRecoveryInstruction: null == failureRecoveryInstruction ? _self.failureRecoveryInstruction : failureRecoveryInstruction // ignore: cast_nullable_to_non_nullable
as String,toolLoopMaxIterations: null == toolLoopMaxIterations ? _self.toolLoopMaxIterations : toolLoopMaxIterations // ignore: cast_nullable_to_non_nullable
as int,recoveryMiddlewareEnabled: null == recoveryMiddlewareEnabled ? _self.recoveryMiddlewareEnabled : recoveryMiddlewareEnabled // ignore: cast_nullable_to_non_nullable
as bool,explorationToEditNudgeEnabled: null == explorationToEditNudgeEnabled ? _self.explorationToEditNudgeEnabled : explorationToEditNudgeEnabled // ignore: cast_nullable_to_non_nullable
as bool,summaryFirstToolResultsEnabled: null == summaryFirstToolResultsEnabled ? _self.summaryFirstToolResultsEnabled : summaryFirstToolResultsEnabled // ignore: cast_nullable_to_non_nullable
as bool,goalCompletionPolicy: null == goalCompletionPolicy ? _self.goalCompletionPolicy : goalCompletionPolicy // ignore: cast_nullable_to_non_nullable
as GoalCompletionPolicy,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelHarnessConfig].
extension ModelHarnessConfigPatterns on ModelHarnessConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelHarnessConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelHarnessConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelHarnessConfig value)  $default,){
final _that = this;
switch (_that) {
case _ModelHarnessConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelHarnessConfig value)?  $default,){
final _that = this;
switch (_that) {
case _ModelHarnessConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model,  String bootstrapInstruction,  String executionInstruction,  String verificationInstruction,  String failureRecoveryInstruction,  int toolLoopMaxIterations,  bool recoveryMiddlewareEnabled,  bool explorationToEditNudgeEnabled,  bool summaryFirstToolResultsEnabled, @JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk)  GoalCompletionPolicy goalCompletionPolicy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelHarnessConfig() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.bootstrapInstruction,_that.executionInstruction,_that.verificationInstruction,_that.failureRecoveryInstruction,_that.toolLoopMaxIterations,_that.recoveryMiddlewareEnabled,_that.explorationToEditNudgeEnabled,_that.summaryFirstToolResultsEnabled,_that.goalCompletionPolicy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model,  String bootstrapInstruction,  String executionInstruction,  String verificationInstruction,  String failureRecoveryInstruction,  int toolLoopMaxIterations,  bool recoveryMiddlewareEnabled,  bool explorationToEditNudgeEnabled,  bool summaryFirstToolResultsEnabled, @JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk)  GoalCompletionPolicy goalCompletionPolicy)  $default,) {final _that = this;
switch (_that) {
case _ModelHarnessConfig():
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.bootstrapInstruction,_that.executionInstruction,_that.verificationInstruction,_that.failureRecoveryInstruction,_that.toolLoopMaxIterations,_that.recoveryMiddlewareEnabled,_that.explorationToEditNudgeEnabled,_that.summaryFirstToolResultsEnabled,_that.goalCompletionPolicy);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model,  String bootstrapInstruction,  String executionInstruction,  String verificationInstruction,  String failureRecoveryInstruction,  int toolLoopMaxIterations,  bool recoveryMiddlewareEnabled,  bool explorationToEditNudgeEnabled,  bool summaryFirstToolResultsEnabled, @JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk)  GoalCompletionPolicy goalCompletionPolicy)?  $default,) {final _that = this;
switch (_that) {
case _ModelHarnessConfig() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.bootstrapInstruction,_that.executionInstruction,_that.verificationInstruction,_that.failureRecoveryInstruction,_that.toolLoopMaxIterations,_that.recoveryMiddlewareEnabled,_that.explorationToEditNudgeEnabled,_that.summaryFirstToolResultsEnabled,_that.goalCompletionPolicy);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelHarnessConfig extends ModelHarnessConfig {
  const _ModelHarnessConfig({required this.id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) this.provider = LlmProvider.openAiCompatible, this.baseUrl = '', required this.model, this.bootstrapInstruction = '', this.executionInstruction = '', this.verificationInstruction = '', this.failureRecoveryInstruction = '', this.toolLoopMaxIterations = 0, this.recoveryMiddlewareEnabled = false, this.explorationToEditNudgeEnabled = false, this.summaryFirstToolResultsEnabled = false, @JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk) this.goalCompletionPolicy = GoalCompletionPolicy.toolOrAsk}): super._();
  factory _ModelHarnessConfig.fromJson(Map<String, dynamic> json) => _$ModelHarnessConfigFromJson(json);

@override final  String id;
@override@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) final  LlmProvider provider;
@override@JsonKey() final  String baseUrl;
@override final  String model;
@override@JsonKey() final  String bootstrapInstruction;
@override@JsonKey() final  String executionInstruction;
@override@JsonKey() final  String verificationInstruction;
@override@JsonKey() final  String failureRecoveryInstruction;
@override@JsonKey() final  int toolLoopMaxIterations;
@override@JsonKey() final  bool recoveryMiddlewareEnabled;
@override@JsonKey() final  bool explorationToEditNudgeEnabled;
@override@JsonKey() final  bool summaryFirstToolResultsEnabled;
@override@JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk) final  GoalCompletionPolicy goalCompletionPolicy;

/// Create a copy of ModelHarnessConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelHarnessConfigCopyWith<_ModelHarnessConfig> get copyWith => __$ModelHarnessConfigCopyWithImpl<_ModelHarnessConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelHarnessConfigToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelHarnessConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.bootstrapInstruction, bootstrapInstruction) || other.bootstrapInstruction == bootstrapInstruction)&&(identical(other.executionInstruction, executionInstruction) || other.executionInstruction == executionInstruction)&&(identical(other.verificationInstruction, verificationInstruction) || other.verificationInstruction == verificationInstruction)&&(identical(other.failureRecoveryInstruction, failureRecoveryInstruction) || other.failureRecoveryInstruction == failureRecoveryInstruction)&&(identical(other.toolLoopMaxIterations, toolLoopMaxIterations) || other.toolLoopMaxIterations == toolLoopMaxIterations)&&(identical(other.recoveryMiddlewareEnabled, recoveryMiddlewareEnabled) || other.recoveryMiddlewareEnabled == recoveryMiddlewareEnabled)&&(identical(other.explorationToEditNudgeEnabled, explorationToEditNudgeEnabled) || other.explorationToEditNudgeEnabled == explorationToEditNudgeEnabled)&&(identical(other.summaryFirstToolResultsEnabled, summaryFirstToolResultsEnabled) || other.summaryFirstToolResultsEnabled == summaryFirstToolResultsEnabled)&&(identical(other.goalCompletionPolicy, goalCompletionPolicy) || other.goalCompletionPolicy == goalCompletionPolicy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,provider,baseUrl,model,bootstrapInstruction,executionInstruction,verificationInstruction,failureRecoveryInstruction,toolLoopMaxIterations,recoveryMiddlewareEnabled,explorationToEditNudgeEnabled,summaryFirstToolResultsEnabled,goalCompletionPolicy);
}

@override
String toString() {
    return 'ModelHarnessConfig(id: $id, provider: $provider, baseUrl: $baseUrl, model: $model, bootstrapInstruction: $bootstrapInstruction, executionInstruction: $executionInstruction, verificationInstruction: $verificationInstruction, failureRecoveryInstruction: $failureRecoveryInstruction, toolLoopMaxIterations: $toolLoopMaxIterations, recoveryMiddlewareEnabled: $recoveryMiddlewareEnabled, explorationToEditNudgeEnabled: $explorationToEditNudgeEnabled, summaryFirstToolResultsEnabled: $summaryFirstToolResultsEnabled, goalCompletionPolicy: $goalCompletionPolicy)';
}


}

/// @nodoc
abstract mixin class _$ModelHarnessConfigCopyWith<$Res> implements $ModelHarnessConfigCopyWith<$Res> {
  factory _$ModelHarnessConfigCopyWith(_ModelHarnessConfig value, $Res Function(_ModelHarnessConfig) _then) = __$ModelHarnessConfigCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model, String bootstrapInstruction, String executionInstruction, String verificationInstruction, String failureRecoveryInstruction, int toolLoopMaxIterations, bool recoveryMiddlewareEnabled, bool explorationToEditNudgeEnabled, bool summaryFirstToolResultsEnabled,@JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk) GoalCompletionPolicy goalCompletionPolicy
});




}
/// @nodoc
class __$ModelHarnessConfigCopyWithImpl<$Res>
    implements _$ModelHarnessConfigCopyWith<$Res> {
  __$ModelHarnessConfigCopyWithImpl(this._self, this._then);

  final _ModelHarnessConfig _self;
  final $Res Function(_ModelHarnessConfig) _then;

/// Create a copy of ModelHarnessConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? bootstrapInstruction = null,Object? executionInstruction = null,Object? verificationInstruction = null,Object? failureRecoveryInstruction = null,Object? toolLoopMaxIterations = null,Object? recoveryMiddlewareEnabled = null,Object? explorationToEditNudgeEnabled = null,Object? summaryFirstToolResultsEnabled = null,Object? goalCompletionPolicy = null,}) {
  return _then(_ModelHarnessConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,bootstrapInstruction: null == bootstrapInstruction ? _self.bootstrapInstruction : bootstrapInstruction // ignore: cast_nullable_to_non_nullable
as String,executionInstruction: null == executionInstruction ? _self.executionInstruction : executionInstruction // ignore: cast_nullable_to_non_nullable
as String,verificationInstruction: null == verificationInstruction ? _self.verificationInstruction : verificationInstruction // ignore: cast_nullable_to_non_nullable
as String,failureRecoveryInstruction: null == failureRecoveryInstruction ? _self.failureRecoveryInstruction : failureRecoveryInstruction // ignore: cast_nullable_to_non_nullable
as String,toolLoopMaxIterations: null == toolLoopMaxIterations ? _self.toolLoopMaxIterations : toolLoopMaxIterations // ignore: cast_nullable_to_non_nullable
as int,recoveryMiddlewareEnabled: null == recoveryMiddlewareEnabled ? _self.recoveryMiddlewareEnabled : recoveryMiddlewareEnabled // ignore: cast_nullable_to_non_nullable
as bool,explorationToEditNudgeEnabled: null == explorationToEditNudgeEnabled ? _self.explorationToEditNudgeEnabled : explorationToEditNudgeEnabled // ignore: cast_nullable_to_non_nullable
as bool,summaryFirstToolResultsEnabled: null == summaryFirstToolResultsEnabled ? _self.summaryFirstToolResultsEnabled : summaryFirstToolResultsEnabled // ignore: cast_nullable_to_non_nullable
as bool,goalCompletionPolicy: null == goalCompletionPolicy ? _self.goalCompletionPolicy : goalCompletionPolicy // ignore: cast_nullable_to_non_nullable
as GoalCompletionPolicy,
  ));
}


}


/// @nodoc
mixin _$ModelCapabilityProfileRevision {

 String get profileId; DateTime get probedAt;@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle get toolCallStyle;@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport get structuredOutputSupport;@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) ModelGoalUpdateFidelity get goalUpdateFidelity;@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference get editFormatPreference;@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) ModelVisionSupport get visionSupport;@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) ModelVideoInputSupport get videoInputSupport; int get usableContextTokens; String get probeSummary;/// LL39 bounded conformance score for this revision, and the suite that
/// produced it. Null means the revision predates the benchmark or came from
/// a path that does not score (a settings import, a bounded re-probe with
/// no scored probes) — which is not the same as scoring zero, so a missing
/// value must never read as a regression.
///
/// Kept on the revision, not only on the profile: the profile is
/// overwritten by every run, so without this the score has no history and
/// nothing can be compared.
 int? get benchmarkPoints; int? get benchmarkAttemptedPoints; int? get benchmarkMaxPoints;/// Suite identity, e.g. `cavernobench-v2`. Two suite versions are not
/// comparable, so history is partitioned by this before any delta.
 String get benchmarkSuite;/// LL39 physical capability ladder evidence. The ladder is versioned
/// independently from bounded conformance so adding harder stages does not
/// invalidate score history.
 String get difficultyLadder; String get difficultyLadderAxis; int? get difficultyLadderMeasuredPromptTokens; int? get difficultyLadderHighestStagePromptTokens; int? get difficultyLadderNextStagePromptTokens; int? get difficultyLadderPassedStageCount; int? get difficultyLadderStageCount;/// Unit-bearing LL39 capability measurements retained independently from
/// the bounded score. Keys are version-stable metric identities such as
/// `capability.streaming.ttftMs`; values remain strings for forward JSON
/// compatibility with new physical axes.
 Map<String, String> get physicalCapabilityMetrics;/// True when this revision's score dropped by more than the spread measured
/// across earlier same-suite revisions. Separate from
/// [capabilityChangeDetected] because the diagnosis differs: an enum flip
/// says a capability appeared or vanished, while this says every capability
/// still reports the same but the model got measurably worse.
 bool get benchmarkRegressionDetected;/// How this revision was triggered. Known values: 'initial', 'idle_re_probe',
/// 'calibrate', 'benchmark_artifact', 'manual', 'probe'.
 String get source;/// True when any key capability field changed vs the immediately preceding
/// revision for the same [profileId] — a heuristic for GGUF/weight swaps.
 bool get capabilityChangeDetected;
/// Create a copy of ModelCapabilityProfileRevision
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCapabilityProfileRevisionCopyWith<ModelCapabilityProfileRevision> get copyWith => _$ModelCapabilityProfileRevisionCopyWithImpl<ModelCapabilityProfileRevision>(this as ModelCapabilityProfileRevision, _$identity);

  /// Serializes this ModelCapabilityProfileRevision to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ModelCapabilityProfileRevision;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCapabilityProfileRevision&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.probedAt, _this.probedAt) || other.probedAt == _this.probedAt)&&(identical(other.toolCallStyle, _this.toolCallStyle) || other.toolCallStyle == _this.toolCallStyle)&&(identical(other.structuredOutputSupport, _this.structuredOutputSupport) || other.structuredOutputSupport == _this.structuredOutputSupport)&&(identical(other.goalUpdateFidelity, _this.goalUpdateFidelity) || other.goalUpdateFidelity == _this.goalUpdateFidelity)&&(identical(other.editFormatPreference, _this.editFormatPreference) || other.editFormatPreference == _this.editFormatPreference)&&(identical(other.visionSupport, _this.visionSupport) || other.visionSupport == _this.visionSupport)&&(identical(other.videoInputSupport, _this.videoInputSupport) || other.videoInputSupport == _this.videoInputSupport)&&(identical(other.usableContextTokens, _this.usableContextTokens) || other.usableContextTokens == _this.usableContextTokens)&&(identical(other.probeSummary, _this.probeSummary) || other.probeSummary == _this.probeSummary)&&(identical(other.benchmarkPoints, _this.benchmarkPoints) || other.benchmarkPoints == _this.benchmarkPoints)&&(identical(other.benchmarkAttemptedPoints, _this.benchmarkAttemptedPoints) || other.benchmarkAttemptedPoints == _this.benchmarkAttemptedPoints)&&(identical(other.benchmarkMaxPoints, _this.benchmarkMaxPoints) || other.benchmarkMaxPoints == _this.benchmarkMaxPoints)&&(identical(other.benchmarkSuite, _this.benchmarkSuite) || other.benchmarkSuite == _this.benchmarkSuite)&&(identical(other.difficultyLadder, _this.difficultyLadder) || other.difficultyLadder == _this.difficultyLadder)&&(identical(other.difficultyLadderAxis, _this.difficultyLadderAxis) || other.difficultyLadderAxis == _this.difficultyLadderAxis)&&(identical(other.difficultyLadderMeasuredPromptTokens, _this.difficultyLadderMeasuredPromptTokens) || other.difficultyLadderMeasuredPromptTokens == _this.difficultyLadderMeasuredPromptTokens)&&(identical(other.difficultyLadderHighestStagePromptTokens, _this.difficultyLadderHighestStagePromptTokens) || other.difficultyLadderHighestStagePromptTokens == _this.difficultyLadderHighestStagePromptTokens)&&(identical(other.difficultyLadderNextStagePromptTokens, _this.difficultyLadderNextStagePromptTokens) || other.difficultyLadderNextStagePromptTokens == _this.difficultyLadderNextStagePromptTokens)&&(identical(other.difficultyLadderPassedStageCount, _this.difficultyLadderPassedStageCount) || other.difficultyLadderPassedStageCount == _this.difficultyLadderPassedStageCount)&&(identical(other.difficultyLadderStageCount, _this.difficultyLadderStageCount) || other.difficultyLadderStageCount == _this.difficultyLadderStageCount)&&const DeepCollectionEquality().equals(other.physicalCapabilityMetrics, _this.physicalCapabilityMetrics)&&(identical(other.benchmarkRegressionDetected, _this.benchmarkRegressionDetected) || other.benchmarkRegressionDetected == _this.benchmarkRegressionDetected)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.capabilityChangeDetected, _this.capabilityChangeDetected) || other.capabilityChangeDetected == _this.capabilityChangeDetected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ModelCapabilityProfileRevision;
  return Object.hashAll([runtimeType,_this.profileId,_this.probedAt,_this.toolCallStyle,_this.structuredOutputSupport,_this.goalUpdateFidelity,_this.editFormatPreference,_this.visionSupport,_this.videoInputSupport,_this.usableContextTokens,_this.probeSummary,_this.benchmarkPoints,_this.benchmarkAttemptedPoints,_this.benchmarkMaxPoints,_this.benchmarkSuite,_this.difficultyLadder,_this.difficultyLadderAxis,_this.difficultyLadderMeasuredPromptTokens,_this.difficultyLadderHighestStagePromptTokens,_this.difficultyLadderNextStagePromptTokens,_this.difficultyLadderPassedStageCount,_this.difficultyLadderStageCount,const DeepCollectionEquality().hash(_this.physicalCapabilityMetrics),_this.benchmarkRegressionDetected,_this.source,_this.capabilityChangeDetected]);
}

@override
String toString() {
  final _this = this as ModelCapabilityProfileRevision;
  return 'ModelCapabilityProfileRevision(profileId: ${_this.profileId}, probedAt: ${_this.probedAt}, toolCallStyle: ${_this.toolCallStyle}, structuredOutputSupport: ${_this.structuredOutputSupport}, goalUpdateFidelity: ${_this.goalUpdateFidelity}, editFormatPreference: ${_this.editFormatPreference}, visionSupport: ${_this.visionSupport}, videoInputSupport: ${_this.videoInputSupport}, usableContextTokens: ${_this.usableContextTokens}, probeSummary: ${_this.probeSummary}, benchmarkPoints: ${_this.benchmarkPoints}, benchmarkAttemptedPoints: ${_this.benchmarkAttemptedPoints}, benchmarkMaxPoints: ${_this.benchmarkMaxPoints}, benchmarkSuite: ${_this.benchmarkSuite}, difficultyLadder: ${_this.difficultyLadder}, difficultyLadderAxis: ${_this.difficultyLadderAxis}, difficultyLadderMeasuredPromptTokens: ${_this.difficultyLadderMeasuredPromptTokens}, difficultyLadderHighestStagePromptTokens: ${_this.difficultyLadderHighestStagePromptTokens}, difficultyLadderNextStagePromptTokens: ${_this.difficultyLadderNextStagePromptTokens}, difficultyLadderPassedStageCount: ${_this.difficultyLadderPassedStageCount}, difficultyLadderStageCount: ${_this.difficultyLadderStageCount}, physicalCapabilityMetrics: ${_this.physicalCapabilityMetrics}, benchmarkRegressionDetected: ${_this.benchmarkRegressionDetected}, source: ${_this.source}, capabilityChangeDetected: ${_this.capabilityChangeDetected})';
}


}

/// @nodoc
abstract mixin class $ModelCapabilityProfileRevisionCopyWith<$Res>  {
  factory $ModelCapabilityProfileRevisionCopyWith(ModelCapabilityProfileRevision value, $Res Function(ModelCapabilityProfileRevision) _then) = _$ModelCapabilityProfileRevisionCopyWithImpl;
@useResult
$Res call({
 String profileId, DateTime probedAt,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) ModelGoalUpdateFidelity goalUpdateFidelity,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference,@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) ModelVisionSupport visionSupport,@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) ModelVideoInputSupport videoInputSupport, int usableContextTokens, String probeSummary, int? benchmarkPoints, int? benchmarkAttemptedPoints, int? benchmarkMaxPoints, String benchmarkSuite, String difficultyLadder, String difficultyLadderAxis, int? difficultyLadderMeasuredPromptTokens, int? difficultyLadderHighestStagePromptTokens, int? difficultyLadderNextStagePromptTokens, int? difficultyLadderPassedStageCount, int? difficultyLadderStageCount, Map<String, String> physicalCapabilityMetrics, bool benchmarkRegressionDetected, String source, bool capabilityChangeDetected
});




}
/// @nodoc
class _$ModelCapabilityProfileRevisionCopyWithImpl<$Res>
    implements $ModelCapabilityProfileRevisionCopyWith<$Res> {
  _$ModelCapabilityProfileRevisionCopyWithImpl(this._self, this._then);

  final ModelCapabilityProfileRevision _self;
  final $Res Function(ModelCapabilityProfileRevision) _then;

/// Create a copy of ModelCapabilityProfileRevision
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? profileId = null,Object? probedAt = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? goalUpdateFidelity = null,Object? editFormatPreference = null,Object? visionSupport = null,Object? videoInputSupport = null,Object? usableContextTokens = null,Object? probeSummary = null,Object? benchmarkPoints = freezed,Object? benchmarkAttemptedPoints = freezed,Object? benchmarkMaxPoints = freezed,Object? benchmarkSuite = null,Object? difficultyLadder = null,Object? difficultyLadderAxis = null,Object? difficultyLadderMeasuredPromptTokens = freezed,Object? difficultyLadderHighestStagePromptTokens = freezed,Object? difficultyLadderNextStagePromptTokens = freezed,Object? difficultyLadderPassedStageCount = freezed,Object? difficultyLadderStageCount = freezed,Object? physicalCapabilityMetrics = null,Object? benchmarkRegressionDetected = null,Object? source = null,Object? capabilityChangeDetected = null,}) {
  return _then(ModelCapabilityProfileRevision(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,probedAt: null == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,goalUpdateFidelity: null == goalUpdateFidelity ? _self.goalUpdateFidelity : goalUpdateFidelity // ignore: cast_nullable_to_non_nullable
as ModelGoalUpdateFidelity,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,visionSupport: null == visionSupport ? _self.visionSupport : visionSupport // ignore: cast_nullable_to_non_nullable
as ModelVisionSupport,videoInputSupport: null == videoInputSupport ? _self.videoInputSupport : videoInputSupport // ignore: cast_nullable_to_non_nullable
as ModelVideoInputSupport,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,benchmarkPoints: freezed == benchmarkPoints ? _self.benchmarkPoints : benchmarkPoints // ignore: cast_nullable_to_non_nullable
as int?,benchmarkAttemptedPoints: freezed == benchmarkAttemptedPoints ? _self.benchmarkAttemptedPoints : benchmarkAttemptedPoints // ignore: cast_nullable_to_non_nullable
as int?,benchmarkMaxPoints: freezed == benchmarkMaxPoints ? _self.benchmarkMaxPoints : benchmarkMaxPoints // ignore: cast_nullable_to_non_nullable
as int?,benchmarkSuite: null == benchmarkSuite ? _self.benchmarkSuite : benchmarkSuite // ignore: cast_nullable_to_non_nullable
as String,difficultyLadder: null == difficultyLadder ? _self.difficultyLadder : difficultyLadder // ignore: cast_nullable_to_non_nullable
as String,difficultyLadderAxis: null == difficultyLadderAxis ? _self.difficultyLadderAxis : difficultyLadderAxis // ignore: cast_nullable_to_non_nullable
as String,difficultyLadderMeasuredPromptTokens: freezed == difficultyLadderMeasuredPromptTokens ? _self.difficultyLadderMeasuredPromptTokens : difficultyLadderMeasuredPromptTokens // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderHighestStagePromptTokens: freezed == difficultyLadderHighestStagePromptTokens ? _self.difficultyLadderHighestStagePromptTokens : difficultyLadderHighestStagePromptTokens // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderNextStagePromptTokens: freezed == difficultyLadderNextStagePromptTokens ? _self.difficultyLadderNextStagePromptTokens : difficultyLadderNextStagePromptTokens // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderPassedStageCount: freezed == difficultyLadderPassedStageCount ? _self.difficultyLadderPassedStageCount : difficultyLadderPassedStageCount // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderStageCount: freezed == difficultyLadderStageCount ? _self.difficultyLadderStageCount : difficultyLadderStageCount // ignore: cast_nullable_to_non_nullable
as int?,physicalCapabilityMetrics: null == physicalCapabilityMetrics ? _self.physicalCapabilityMetrics : physicalCapabilityMetrics // ignore: cast_nullable_to_non_nullable
as Map<String, String>,benchmarkRegressionDetected: null == benchmarkRegressionDetected ? _self.benchmarkRegressionDetected : benchmarkRegressionDetected // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,capabilityChangeDetected: null == capabilityChangeDetected ? _self.capabilityChangeDetected : capabilityChangeDetected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelCapabilityProfileRevision].
extension ModelCapabilityProfileRevisionPatterns on ModelCapabilityProfileRevision {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCapabilityProfileRevision value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCapabilityProfileRevision value)  $default,){
final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCapabilityProfileRevision value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String profileId,  DateTime probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)  ModelGoalUpdateFidelity goalUpdateFidelity, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)  ModelVisionSupport visionSupport, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown)  ModelVideoInputSupport videoInputSupport,  int usableContextTokens,  String probeSummary,  int? benchmarkPoints,  int? benchmarkAttemptedPoints,  int? benchmarkMaxPoints,  String benchmarkSuite,  String difficultyLadder,  String difficultyLadderAxis,  int? difficultyLadderMeasuredPromptTokens,  int? difficultyLadderHighestStagePromptTokens,  int? difficultyLadderNextStagePromptTokens,  int? difficultyLadderPassedStageCount,  int? difficultyLadderStageCount,  Map<String, String> physicalCapabilityMetrics,  bool benchmarkRegressionDetected,  String source,  bool capabilityChangeDetected)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision() when $default != null:
return $default(_that.profileId,_that.probedAt,_that.toolCallStyle,_that.structuredOutputSupport,_that.goalUpdateFidelity,_that.editFormatPreference,_that.visionSupport,_that.videoInputSupport,_that.usableContextTokens,_that.probeSummary,_that.benchmarkPoints,_that.benchmarkAttemptedPoints,_that.benchmarkMaxPoints,_that.benchmarkSuite,_that.difficultyLadder,_that.difficultyLadderAxis,_that.difficultyLadderMeasuredPromptTokens,_that.difficultyLadderHighestStagePromptTokens,_that.difficultyLadderNextStagePromptTokens,_that.difficultyLadderPassedStageCount,_that.difficultyLadderStageCount,_that.physicalCapabilityMetrics,_that.benchmarkRegressionDetected,_that.source,_that.capabilityChangeDetected);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String profileId,  DateTime probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)  ModelGoalUpdateFidelity goalUpdateFidelity, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)  ModelVisionSupport visionSupport, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown)  ModelVideoInputSupport videoInputSupport,  int usableContextTokens,  String probeSummary,  int? benchmarkPoints,  int? benchmarkAttemptedPoints,  int? benchmarkMaxPoints,  String benchmarkSuite,  String difficultyLadder,  String difficultyLadderAxis,  int? difficultyLadderMeasuredPromptTokens,  int? difficultyLadderHighestStagePromptTokens,  int? difficultyLadderNextStagePromptTokens,  int? difficultyLadderPassedStageCount,  int? difficultyLadderStageCount,  Map<String, String> physicalCapabilityMetrics,  bool benchmarkRegressionDetected,  String source,  bool capabilityChangeDetected)  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision():
return $default(_that.profileId,_that.probedAt,_that.toolCallStyle,_that.structuredOutputSupport,_that.goalUpdateFidelity,_that.editFormatPreference,_that.visionSupport,_that.videoInputSupport,_that.usableContextTokens,_that.probeSummary,_that.benchmarkPoints,_that.benchmarkAttemptedPoints,_that.benchmarkMaxPoints,_that.benchmarkSuite,_that.difficultyLadder,_that.difficultyLadderAxis,_that.difficultyLadderMeasuredPromptTokens,_that.difficultyLadderHighestStagePromptTokens,_that.difficultyLadderNextStagePromptTokens,_that.difficultyLadderPassedStageCount,_that.difficultyLadderStageCount,_that.physicalCapabilityMetrics,_that.benchmarkRegressionDetected,_that.source,_that.capabilityChangeDetected);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String profileId,  DateTime probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)  ModelGoalUpdateFidelity goalUpdateFidelity, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)  ModelVisionSupport visionSupport, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown)  ModelVideoInputSupport videoInputSupport,  int usableContextTokens,  String probeSummary,  int? benchmarkPoints,  int? benchmarkAttemptedPoints,  int? benchmarkMaxPoints,  String benchmarkSuite,  String difficultyLadder,  String difficultyLadderAxis,  int? difficultyLadderMeasuredPromptTokens,  int? difficultyLadderHighestStagePromptTokens,  int? difficultyLadderNextStagePromptTokens,  int? difficultyLadderPassedStageCount,  int? difficultyLadderStageCount,  Map<String, String> physicalCapabilityMetrics,  bool benchmarkRegressionDetected,  String source,  bool capabilityChangeDetected)?  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision() when $default != null:
return $default(_that.profileId,_that.probedAt,_that.toolCallStyle,_that.structuredOutputSupport,_that.goalUpdateFidelity,_that.editFormatPreference,_that.visionSupport,_that.videoInputSupport,_that.usableContextTokens,_that.probeSummary,_that.benchmarkPoints,_that.benchmarkAttemptedPoints,_that.benchmarkMaxPoints,_that.benchmarkSuite,_that.difficultyLadder,_that.difficultyLadderAxis,_that.difficultyLadderMeasuredPromptTokens,_that.difficultyLadderHighestStagePromptTokens,_that.difficultyLadderNextStagePromptTokens,_that.difficultyLadderPassedStageCount,_that.difficultyLadderStageCount,_that.physicalCapabilityMetrics,_that.benchmarkRegressionDetected,_that.source,_that.capabilityChangeDetected);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelCapabilityProfileRevision extends ModelCapabilityProfileRevision {
  const _ModelCapabilityProfileRevision({required this.profileId, required this.probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) required this.toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) required this.structuredOutputSupport, @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) this.goalUpdateFidelity = ModelGoalUpdateFidelity.unknown, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) required this.editFormatPreference, @JsonKey(unknownEnumValue: ModelVisionSupport.unknown) this.visionSupport = ModelVisionSupport.unknown, @JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) this.videoInputSupport = ModelVideoInputSupport.unknown, required this.usableContextTokens, this.probeSummary = '', this.benchmarkPoints, this.benchmarkAttemptedPoints, this.benchmarkMaxPoints, this.benchmarkSuite = '', this.difficultyLadder = '', this.difficultyLadderAxis = '', this.difficultyLadderMeasuredPromptTokens, this.difficultyLadderHighestStagePromptTokens, this.difficultyLadderNextStagePromptTokens, this.difficultyLadderPassedStageCount, this.difficultyLadderStageCount,  Map<String, String> physicalCapabilityMetrics = const <String, String>{}, this.benchmarkRegressionDetected = false, this.source = 'probe', this.capabilityChangeDetected = false}): _physicalCapabilityMetrics = physicalCapabilityMetrics,super._();
  factory _ModelCapabilityProfileRevision.fromJson(Map<String, dynamic> json) => _$ModelCapabilityProfileRevisionFromJson(json);

@override final  String profileId;
@override final  DateTime probedAt;
@override@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) final  ModelToolCallStyle toolCallStyle;
@override@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) final  ModelStructuredOutputSupport structuredOutputSupport;
@override@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) final  ModelGoalUpdateFidelity goalUpdateFidelity;
@override@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) final  ModelEditFormatPreference editFormatPreference;
@override@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) final  ModelVisionSupport visionSupport;
@override@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) final  ModelVideoInputSupport videoInputSupport;
@override final  int usableContextTokens;
@override@JsonKey() final  String probeSummary;
/// LL39 bounded conformance score for this revision, and the suite that
/// produced it. Null means the revision predates the benchmark or came from
/// a path that does not score (a settings import, a bounded re-probe with
/// no scored probes) — which is not the same as scoring zero, so a missing
/// value must never read as a regression.
///
/// Kept on the revision, not only on the profile: the profile is
/// overwritten by every run, so without this the score has no history and
/// nothing can be compared.
@override final  int? benchmarkPoints;
@override final  int? benchmarkAttemptedPoints;
@override final  int? benchmarkMaxPoints;
/// Suite identity, e.g. `cavernobench-v2`. Two suite versions are not
/// comparable, so history is partitioned by this before any delta.
@override@JsonKey() final  String benchmarkSuite;
/// LL39 physical capability ladder evidence. The ladder is versioned
/// independently from bounded conformance so adding harder stages does not
/// invalidate score history.
@override@JsonKey() final  String difficultyLadder;
@override@JsonKey() final  String difficultyLadderAxis;
@override final  int? difficultyLadderMeasuredPromptTokens;
@override final  int? difficultyLadderHighestStagePromptTokens;
@override final  int? difficultyLadderNextStagePromptTokens;
@override final  int? difficultyLadderPassedStageCount;
@override final  int? difficultyLadderStageCount;
/// Unit-bearing LL39 capability measurements retained independently from
/// the bounded score. Keys are version-stable metric identities such as
/// `capability.streaming.ttftMs`; values remain strings for forward JSON
/// compatibility with new physical axes.
 final  Map<String, String> _physicalCapabilityMetrics;
/// Unit-bearing LL39 capability measurements retained independently from
/// the bounded score. Keys are version-stable metric identities such as
/// `capability.streaming.ttftMs`; values remain strings for forward JSON
/// compatibility with new physical axes.
@override@JsonKey() Map<String, String> get physicalCapabilityMetrics {
  if (_physicalCapabilityMetrics is EqualUnmodifiableMapView) return _physicalCapabilityMetrics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_physicalCapabilityMetrics);
}

/// True when this revision's score dropped by more than the spread measured
/// across earlier same-suite revisions. Separate from
/// [capabilityChangeDetected] because the diagnosis differs: an enum flip
/// says a capability appeared or vanished, while this says every capability
/// still reports the same but the model got measurably worse.
@override@JsonKey() final  bool benchmarkRegressionDetected;
/// How this revision was triggered. Known values: 'initial', 'idle_re_probe',
/// 'calibrate', 'benchmark_artifact', 'manual', 'probe'.
@override@JsonKey() final  String source;
/// True when any key capability field changed vs the immediately preceding
/// revision for the same [profileId] — a heuristic for GGUF/weight swaps.
@override@JsonKey() final  bool capabilityChangeDetected;

/// Create a copy of ModelCapabilityProfileRevision
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCapabilityProfileRevisionCopyWith<_ModelCapabilityProfileRevision> get copyWith => __$ModelCapabilityProfileRevisionCopyWithImpl<_ModelCapabilityProfileRevision>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelCapabilityProfileRevisionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCapabilityProfileRevision&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.probedAt, probedAt) || other.probedAt == probedAt)&&(identical(other.toolCallStyle, toolCallStyle) || other.toolCallStyle == toolCallStyle)&&(identical(other.structuredOutputSupport, structuredOutputSupport) || other.structuredOutputSupport == structuredOutputSupport)&&(identical(other.goalUpdateFidelity, goalUpdateFidelity) || other.goalUpdateFidelity == goalUpdateFidelity)&&(identical(other.editFormatPreference, editFormatPreference) || other.editFormatPreference == editFormatPreference)&&(identical(other.visionSupport, visionSupport) || other.visionSupport == visionSupport)&&(identical(other.videoInputSupport, videoInputSupport) || other.videoInputSupport == videoInputSupport)&&(identical(other.usableContextTokens, usableContextTokens) || other.usableContextTokens == usableContextTokens)&&(identical(other.probeSummary, probeSummary) || other.probeSummary == probeSummary)&&(identical(other.benchmarkPoints, benchmarkPoints) || other.benchmarkPoints == benchmarkPoints)&&(identical(other.benchmarkAttemptedPoints, benchmarkAttemptedPoints) || other.benchmarkAttemptedPoints == benchmarkAttemptedPoints)&&(identical(other.benchmarkMaxPoints, benchmarkMaxPoints) || other.benchmarkMaxPoints == benchmarkMaxPoints)&&(identical(other.benchmarkSuite, benchmarkSuite) || other.benchmarkSuite == benchmarkSuite)&&(identical(other.difficultyLadder, difficultyLadder) || other.difficultyLadder == difficultyLadder)&&(identical(other.difficultyLadderAxis, difficultyLadderAxis) || other.difficultyLadderAxis == difficultyLadderAxis)&&(identical(other.difficultyLadderMeasuredPromptTokens, difficultyLadderMeasuredPromptTokens) || other.difficultyLadderMeasuredPromptTokens == difficultyLadderMeasuredPromptTokens)&&(identical(other.difficultyLadderHighestStagePromptTokens, difficultyLadderHighestStagePromptTokens) || other.difficultyLadderHighestStagePromptTokens == difficultyLadderHighestStagePromptTokens)&&(identical(other.difficultyLadderNextStagePromptTokens, difficultyLadderNextStagePromptTokens) || other.difficultyLadderNextStagePromptTokens == difficultyLadderNextStagePromptTokens)&&(identical(other.difficultyLadderPassedStageCount, difficultyLadderPassedStageCount) || other.difficultyLadderPassedStageCount == difficultyLadderPassedStageCount)&&(identical(other.difficultyLadderStageCount, difficultyLadderStageCount) || other.difficultyLadderStageCount == difficultyLadderStageCount)&&const DeepCollectionEquality().equals(other.physicalCapabilityMetrics, _physicalCapabilityMetrics)&&(identical(other.benchmarkRegressionDetected, benchmarkRegressionDetected) || other.benchmarkRegressionDetected == benchmarkRegressionDetected)&&(identical(other.source, source) || other.source == source)&&(identical(other.capabilityChangeDetected, capabilityChangeDetected) || other.capabilityChangeDetected == capabilityChangeDetected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,profileId,probedAt,toolCallStyle,structuredOutputSupport,goalUpdateFidelity,editFormatPreference,visionSupport,videoInputSupport,usableContextTokens,probeSummary,benchmarkPoints,benchmarkAttemptedPoints,benchmarkMaxPoints,benchmarkSuite,difficultyLadder,difficultyLadderAxis,difficultyLadderMeasuredPromptTokens,difficultyLadderHighestStagePromptTokens,difficultyLadderNextStagePromptTokens,difficultyLadderPassedStageCount,difficultyLadderStageCount,const DeepCollectionEquality().hash(_physicalCapabilityMetrics),benchmarkRegressionDetected,source,capabilityChangeDetected]);
}

@override
String toString() {
    return 'ModelCapabilityProfileRevision(profileId: $profileId, probedAt: $probedAt, toolCallStyle: $toolCallStyle, structuredOutputSupport: $structuredOutputSupport, goalUpdateFidelity: $goalUpdateFidelity, editFormatPreference: $editFormatPreference, visionSupport: $visionSupport, videoInputSupport: $videoInputSupport, usableContextTokens: $usableContextTokens, probeSummary: $probeSummary, benchmarkPoints: $benchmarkPoints, benchmarkAttemptedPoints: $benchmarkAttemptedPoints, benchmarkMaxPoints: $benchmarkMaxPoints, benchmarkSuite: $benchmarkSuite, difficultyLadder: $difficultyLadder, difficultyLadderAxis: $difficultyLadderAxis, difficultyLadderMeasuredPromptTokens: $difficultyLadderMeasuredPromptTokens, difficultyLadderHighestStagePromptTokens: $difficultyLadderHighestStagePromptTokens, difficultyLadderNextStagePromptTokens: $difficultyLadderNextStagePromptTokens, difficultyLadderPassedStageCount: $difficultyLadderPassedStageCount, difficultyLadderStageCount: $difficultyLadderStageCount, physicalCapabilityMetrics: $physicalCapabilityMetrics, benchmarkRegressionDetected: $benchmarkRegressionDetected, source: $source, capabilityChangeDetected: $capabilityChangeDetected)';
}


}

/// @nodoc
abstract mixin class _$ModelCapabilityProfileRevisionCopyWith<$Res> implements $ModelCapabilityProfileRevisionCopyWith<$Res> {
  factory _$ModelCapabilityProfileRevisionCopyWith(_ModelCapabilityProfileRevision value, $Res Function(_ModelCapabilityProfileRevision) _then) = __$ModelCapabilityProfileRevisionCopyWithImpl;
@override @useResult
$Res call({
 String profileId, DateTime probedAt,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown) ModelGoalUpdateFidelity goalUpdateFidelity,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference,@JsonKey(unknownEnumValue: ModelVisionSupport.unknown) ModelVisionSupport visionSupport,@JsonKey(unknownEnumValue: ModelVideoInputSupport.unknown) ModelVideoInputSupport videoInputSupport, int usableContextTokens, String probeSummary, int? benchmarkPoints, int? benchmarkAttemptedPoints, int? benchmarkMaxPoints, String benchmarkSuite, String difficultyLadder, String difficultyLadderAxis, int? difficultyLadderMeasuredPromptTokens, int? difficultyLadderHighestStagePromptTokens, int? difficultyLadderNextStagePromptTokens, int? difficultyLadderPassedStageCount, int? difficultyLadderStageCount, Map<String, String> physicalCapabilityMetrics, bool benchmarkRegressionDetected, String source, bool capabilityChangeDetected
});




}
/// @nodoc
class __$ModelCapabilityProfileRevisionCopyWithImpl<$Res>
    implements _$ModelCapabilityProfileRevisionCopyWith<$Res> {
  __$ModelCapabilityProfileRevisionCopyWithImpl(this._self, this._then);

  final _ModelCapabilityProfileRevision _self;
  final $Res Function(_ModelCapabilityProfileRevision) _then;

/// Create a copy of ModelCapabilityProfileRevision
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? profileId = null,Object? probedAt = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? goalUpdateFidelity = null,Object? editFormatPreference = null,Object? visionSupport = null,Object? videoInputSupport = null,Object? usableContextTokens = null,Object? probeSummary = null,Object? benchmarkPoints = freezed,Object? benchmarkAttemptedPoints = freezed,Object? benchmarkMaxPoints = freezed,Object? benchmarkSuite = null,Object? difficultyLadder = null,Object? difficultyLadderAxis = null,Object? difficultyLadderMeasuredPromptTokens = freezed,Object? difficultyLadderHighestStagePromptTokens = freezed,Object? difficultyLadderNextStagePromptTokens = freezed,Object? difficultyLadderPassedStageCount = freezed,Object? difficultyLadderStageCount = freezed,Object? physicalCapabilityMetrics = null,Object? benchmarkRegressionDetected = null,Object? source = null,Object? capabilityChangeDetected = null,}) {
  return _then(_ModelCapabilityProfileRevision(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,probedAt: null == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,goalUpdateFidelity: null == goalUpdateFidelity ? _self.goalUpdateFidelity : goalUpdateFidelity // ignore: cast_nullable_to_non_nullable
as ModelGoalUpdateFidelity,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,visionSupport: null == visionSupport ? _self.visionSupport : visionSupport // ignore: cast_nullable_to_non_nullable
as ModelVisionSupport,videoInputSupport: null == videoInputSupport ? _self.videoInputSupport : videoInputSupport // ignore: cast_nullable_to_non_nullable
as ModelVideoInputSupport,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,benchmarkPoints: freezed == benchmarkPoints ? _self.benchmarkPoints : benchmarkPoints // ignore: cast_nullable_to_non_nullable
as int?,benchmarkAttemptedPoints: freezed == benchmarkAttemptedPoints ? _self.benchmarkAttemptedPoints : benchmarkAttemptedPoints // ignore: cast_nullable_to_non_nullable
as int?,benchmarkMaxPoints: freezed == benchmarkMaxPoints ? _self.benchmarkMaxPoints : benchmarkMaxPoints // ignore: cast_nullable_to_non_nullable
as int?,benchmarkSuite: null == benchmarkSuite ? _self.benchmarkSuite : benchmarkSuite // ignore: cast_nullable_to_non_nullable
as String,difficultyLadder: null == difficultyLadder ? _self.difficultyLadder : difficultyLadder // ignore: cast_nullable_to_non_nullable
as String,difficultyLadderAxis: null == difficultyLadderAxis ? _self.difficultyLadderAxis : difficultyLadderAxis // ignore: cast_nullable_to_non_nullable
as String,difficultyLadderMeasuredPromptTokens: freezed == difficultyLadderMeasuredPromptTokens ? _self.difficultyLadderMeasuredPromptTokens : difficultyLadderMeasuredPromptTokens // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderHighestStagePromptTokens: freezed == difficultyLadderHighestStagePromptTokens ? _self.difficultyLadderHighestStagePromptTokens : difficultyLadderHighestStagePromptTokens // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderNextStagePromptTokens: freezed == difficultyLadderNextStagePromptTokens ? _self.difficultyLadderNextStagePromptTokens : difficultyLadderNextStagePromptTokens // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderPassedStageCount: freezed == difficultyLadderPassedStageCount ? _self.difficultyLadderPassedStageCount : difficultyLadderPassedStageCount // ignore: cast_nullable_to_non_nullable
as int?,difficultyLadderStageCount: freezed == difficultyLadderStageCount ? _self.difficultyLadderStageCount : difficultyLadderStageCount // ignore: cast_nullable_to_non_nullable
as int?,physicalCapabilityMetrics: null == physicalCapabilityMetrics ? _self._physicalCapabilityMetrics : physicalCapabilityMetrics // ignore: cast_nullable_to_non_nullable
as Map<String, String>,benchmarkRegressionDetected: null == benchmarkRegressionDetected ? _self.benchmarkRegressionDetected : benchmarkRegressionDetected // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,capabilityChangeDetected: null == capabilityChangeDetected ? _self.capabilityChangeDetected : capabilityChangeDetected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$LlmEndpoint {

 String get id; String get label; String get baseUrl; String get apiKey; String get model; bool get enabled;/// Manual opt-in for video attachments.
///
/// The probe can only auto-detect endpoints that advertise their input
/// modalities. A proxy that rewrites requests for a video-capable server
/// usually advertises nothing, and there is no way to tell that apart from
/// a server that simply cannot take video -- so the person says.
 bool get videoInputEnabled;/// Manual opt-in for `chat_template_kwargs`, the llama.cpp chat-template
/// control that carries `enable_thinking`.
///
/// Like [videoInputEnabled], nothing advertises this: a server that has
/// never heard of the field and a server that honours it look identical
/// over the wire, so the person says. Off by default, because sending it
/// to an endpoint that does not know it is the outcome worth avoiding.
///
/// Until this existed, whether a request could suppress thinking was
/// decided by the model *name*, even though suppression is a fact about
/// the request: a local llama.cpp serving any unrecognised family got none
/// on its JSON utility calls, so goalSuggestion, memoryExtraction and
/// approvalAutoReview thought inside a 400-token budget and returned
/// nothing usable. This flag replaced that gate, so no model name takes
/// part in the decision any more.
 bool get chatTemplateKwargsEnabled;@JsonKey(unknownEnumValue: LlmEndpointSource.manual) LlmEndpointSource get source; DateTime? get createdAt;
/// Create a copy of LlmEndpoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LlmEndpointCopyWith<LlmEndpoint> get copyWith => _$LlmEndpointCopyWithImpl<LlmEndpoint>(this as LlmEndpoint, _$identity);

  /// Serializes this LlmEndpoint to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LlmEndpoint;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LlmEndpoint&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.apiKey, _this.apiKey) || other.apiKey == _this.apiKey)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.videoInputEnabled, _this.videoInputEnabled) || other.videoInputEnabled == _this.videoInputEnabled)&&(identical(other.chatTemplateKwargsEnabled, _this.chatTemplateKwargsEnabled) || other.chatTemplateKwargsEnabled == _this.chatTemplateKwargsEnabled)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LlmEndpoint;
  return Object.hash(runtimeType,_this.id,_this.label,_this.baseUrl,_this.apiKey,_this.model,_this.enabled,_this.videoInputEnabled,_this.chatTemplateKwargsEnabled,_this.source,_this.createdAt);
}

@override
String toString() {
  final _this = this as LlmEndpoint;
  return 'LlmEndpoint(id: ${_this.id}, label: ${_this.label}, baseUrl: ${_this.baseUrl}, apiKey: ${_this.apiKey}, model: ${_this.model}, enabled: ${_this.enabled}, videoInputEnabled: ${_this.videoInputEnabled}, chatTemplateKwargsEnabled: ${_this.chatTemplateKwargsEnabled}, source: ${_this.source}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $LlmEndpointCopyWith<$Res>  {
  factory $LlmEndpointCopyWith(LlmEndpoint value, $Res Function(LlmEndpoint) _then) = _$LlmEndpointCopyWithImpl;
@useResult
$Res call({
 String id, String label, String baseUrl, String apiKey, String model, bool enabled, bool videoInputEnabled, bool chatTemplateKwargsEnabled,@JsonKey(unknownEnumValue: LlmEndpointSource.manual) LlmEndpointSource source, DateTime? createdAt
});




}
/// @nodoc
class _$LlmEndpointCopyWithImpl<$Res>
    implements $LlmEndpointCopyWith<$Res> {
  _$LlmEndpointCopyWithImpl(this._self, this._then);

  final LlmEndpoint _self;
  final $Res Function(LlmEndpoint) _then;

/// Create a copy of LlmEndpoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? baseUrl = null,Object? apiKey = null,Object? model = null,Object? enabled = null,Object? videoInputEnabled = null,Object? chatTemplateKwargsEnabled = null,Object? source = null,Object? createdAt = freezed,}) {
  return _then(LlmEndpoint(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,videoInputEnabled: null == videoInputEnabled ? _self.videoInputEnabled : videoInputEnabled // ignore: cast_nullable_to_non_nullable
as bool,chatTemplateKwargsEnabled: null == chatTemplateKwargsEnabled ? _self.chatTemplateKwargsEnabled : chatTemplateKwargsEnabled // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as LlmEndpointSource,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [LlmEndpoint].
extension LlmEndpointPatterns on LlmEndpoint {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LlmEndpoint value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LlmEndpoint() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LlmEndpoint value)  $default,){
final _that = this;
switch (_that) {
case _LlmEndpoint():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LlmEndpoint value)?  $default,){
final _that = this;
switch (_that) {
case _LlmEndpoint() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String baseUrl,  String apiKey,  String model,  bool enabled,  bool videoInputEnabled,  bool chatTemplateKwargsEnabled, @JsonKey(unknownEnumValue: LlmEndpointSource.manual)  LlmEndpointSource source,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LlmEndpoint() when $default != null:
return $default(_that.id,_that.label,_that.baseUrl,_that.apiKey,_that.model,_that.enabled,_that.videoInputEnabled,_that.chatTemplateKwargsEnabled,_that.source,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String baseUrl,  String apiKey,  String model,  bool enabled,  bool videoInputEnabled,  bool chatTemplateKwargsEnabled, @JsonKey(unknownEnumValue: LlmEndpointSource.manual)  LlmEndpointSource source,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _LlmEndpoint():
return $default(_that.id,_that.label,_that.baseUrl,_that.apiKey,_that.model,_that.enabled,_that.videoInputEnabled,_that.chatTemplateKwargsEnabled,_that.source,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String baseUrl,  String apiKey,  String model,  bool enabled,  bool videoInputEnabled,  bool chatTemplateKwargsEnabled, @JsonKey(unknownEnumValue: LlmEndpointSource.manual)  LlmEndpointSource source,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _LlmEndpoint() when $default != null:
return $default(_that.id,_that.label,_that.baseUrl,_that.apiKey,_that.model,_that.enabled,_that.videoInputEnabled,_that.chatTemplateKwargsEnabled,_that.source,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LlmEndpoint extends LlmEndpoint {
  const _LlmEndpoint({required this.id, this.label = '', this.baseUrl = '', this.apiKey = '', this.model = '', this.enabled = true, this.videoInputEnabled = false, this.chatTemplateKwargsEnabled = false, @JsonKey(unknownEnumValue: LlmEndpointSource.manual) this.source = LlmEndpointSource.manual, this.createdAt}): super._();
  factory _LlmEndpoint.fromJson(Map<String, dynamic> json) => _$LlmEndpointFromJson(json);

@override final  String id;
@override@JsonKey() final  String label;
@override@JsonKey() final  String baseUrl;
@override@JsonKey() final  String apiKey;
@override@JsonKey() final  String model;
@override@JsonKey() final  bool enabled;
/// Manual opt-in for video attachments.
///
/// The probe can only auto-detect endpoints that advertise their input
/// modalities. A proxy that rewrites requests for a video-capable server
/// usually advertises nothing, and there is no way to tell that apart from
/// a server that simply cannot take video -- so the person says.
@override@JsonKey() final  bool videoInputEnabled;
/// Manual opt-in for `chat_template_kwargs`, the llama.cpp chat-template
/// control that carries `enable_thinking`.
///
/// Like [videoInputEnabled], nothing advertises this: a server that has
/// never heard of the field and a server that honours it look identical
/// over the wire, so the person says. Off by default, because sending it
/// to an endpoint that does not know it is the outcome worth avoiding.
///
/// Until this existed, whether a request could suppress thinking was
/// decided by the model *name*, even though suppression is a fact about
/// the request: a local llama.cpp serving any unrecognised family got none
/// on its JSON utility calls, so goalSuggestion, memoryExtraction and
/// approvalAutoReview thought inside a 400-token budget and returned
/// nothing usable. This flag replaced that gate, so no model name takes
/// part in the decision any more.
@override@JsonKey() final  bool chatTemplateKwargsEnabled;
@override@JsonKey(unknownEnumValue: LlmEndpointSource.manual) final  LlmEndpointSource source;
@override final  DateTime? createdAt;

/// Create a copy of LlmEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LlmEndpointCopyWith<_LlmEndpoint> get copyWith => __$LlmEndpointCopyWithImpl<_LlmEndpoint>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LlmEndpointToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LlmEndpoint&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.model, model) || other.model == model)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.videoInputEnabled, videoInputEnabled) || other.videoInputEnabled == videoInputEnabled)&&(identical(other.chatTemplateKwargsEnabled, chatTemplateKwargsEnabled) || other.chatTemplateKwargsEnabled == chatTemplateKwargsEnabled)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,label,baseUrl,apiKey,model,enabled,videoInputEnabled,chatTemplateKwargsEnabled,source,createdAt);
}

@override
String toString() {
    return 'LlmEndpoint(id: $id, label: $label, baseUrl: $baseUrl, apiKey: $apiKey, model: $model, enabled: $enabled, videoInputEnabled: $videoInputEnabled, chatTemplateKwargsEnabled: $chatTemplateKwargsEnabled, source: $source, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$LlmEndpointCopyWith<$Res> implements $LlmEndpointCopyWith<$Res> {
  factory _$LlmEndpointCopyWith(_LlmEndpoint value, $Res Function(_LlmEndpoint) _then) = __$LlmEndpointCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String baseUrl, String apiKey, String model, bool enabled, bool videoInputEnabled, bool chatTemplateKwargsEnabled,@JsonKey(unknownEnumValue: LlmEndpointSource.manual) LlmEndpointSource source, DateTime? createdAt
});




}
/// @nodoc
class __$LlmEndpointCopyWithImpl<$Res>
    implements _$LlmEndpointCopyWith<$Res> {
  __$LlmEndpointCopyWithImpl(this._self, this._then);

  final _LlmEndpoint _self;
  final $Res Function(_LlmEndpoint) _then;

/// Create a copy of LlmEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? baseUrl = null,Object? apiKey = null,Object? model = null,Object? enabled = null,Object? videoInputEnabled = null,Object? chatTemplateKwargsEnabled = null,Object? source = null,Object? createdAt = freezed,}) {
  return _then(_LlmEndpoint(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,videoInputEnabled: null == videoInputEnabled ? _self.videoInputEnabled : videoInputEnabled // ignore: cast_nullable_to_non_nullable
as bool,chatTemplateKwargsEnabled: null == chatTemplateKwargsEnabled ? _self.chatTemplateKwargsEnabled : chatTemplateKwargsEnabled // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as LlmEndpointSource,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$AppSettings {

@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider get llmProvider; String get baseUrl; String get model; String get apiKey;@JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson) List<LlmEndpoint> get llmEndpoints; String get activeLlmEndpointId; double get temperature; int get maxTokens;@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference get reasoningEffort; bool? get enableThinking; bool get proReasoningEnabled;@JsonKey(unknownEnumValue: ProReasoningDepth.deep) ProReasoningDepth get proReasoningDepth;@JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh) ProReasoningCandidateRouting get proReasoningCandidateRouting; String get generalPrimaryModel; String get codingPrimaryModel; String get planPrimaryModel; String get generalPrimaryEndpointId; String get codingPrimaryEndpointId; String get planPrimaryEndpointId; String get memoryExtractionModel; String get subagentModel; String get goalSuggestionModel; String get approvalAutoReviewModel; String get planningModel; String get proReasoningModel; String get codeReviewModel; String get logAnalysisModel; String get memoryExtractionEndpointId; String get subagentEndpointId; String get goalSuggestionEndpointId; String get approvalAutoReviewEndpointId; String get planningEndpointId; String get proReasoningEndpointId; String get codeReviewEndpointId; String get logAnalysisEndpointId; String get googleChatWebhookUrl; String get mcpUrl; List<String> get mcpUrls; List<McpServerConfig> get mcpServers; bool get mcpEnabled; bool get externalSettingsSyncEnabled; String get externalSettingsPath; bool get externalToolHooksEnabled;@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> get externalToolHooks; bool get ttsEnabled; bool get autoReadEnabled; double get speechRate; bool get voiceModeAutoStop; String get whisperUrl; String get voicevoxUrl; int get voicevoxSpeakerId; String get language;@JsonKey(unknownEnumValue: AppThemePreference.dark) AppThemePreference get themePreference;@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode get assistantMode;@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode get codingApprovalMode;@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode get chatApprovalMode; bool get confirmFileMutations; bool get confirmLocalCommands; bool get confirmGitWrites; bool get enableCodingVerificationFeedback;@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) CodingVerificationTriggerPolicy get codingVerificationTriggerPolicy; int get codingVerificationTimeoutSeconds; int get codingVerificationMaxFailures; bool get enableAgentsMd; bool get composerShortcutsEnabled; bool get enablePrefixStableToolLoop; bool get enableSemanticSearch; String get embeddingsModel; String get embeddingsEndpointId; bool get showMemoryUpdates; bool get enableLlmSessionLogs; bool get enableAppLogFile; bool get feedbackUploadEnabled; String get feedbackEndpointUrl; String get feedbackEndpointAuthToken; bool get demoMode; bool get onboardingCompleted; bool get browserToolsEnabled; List<String> get disabledBuiltInTools; List<LocalCommandPermissionRule> get localCommandPermissionRules; List<RoutineComputerUseActionAllowlistEntry> get routineComputerUseActionAllowlist;@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> get modelCapabilityProfiles;@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> get modelHarnessConfigs;@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> get modelCapabilityProfileRevisions; bool get idleMaintenanceEnabled; int get idleMaintenanceWindowStartMinutes; int get idleMaintenanceWindowEndMinutes; int get idleMaintenanceMinIdleMinutes; bool get idleMaintenanceRequireAcPower;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AppSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.llmProvider, _this.llmProvider) || other.llmProvider == _this.llmProvider)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.apiKey, _this.apiKey) || other.apiKey == _this.apiKey)&&const DeepCollectionEquality().equals(other.llmEndpoints, _this.llmEndpoints)&&(identical(other.activeLlmEndpointId, _this.activeLlmEndpointId) || other.activeLlmEndpointId == _this.activeLlmEndpointId)&&(identical(other.temperature, _this.temperature) || other.temperature == _this.temperature)&&(identical(other.maxTokens, _this.maxTokens) || other.maxTokens == _this.maxTokens)&&(identical(other.reasoningEffort, _this.reasoningEffort) || other.reasoningEffort == _this.reasoningEffort)&&(identical(other.enableThinking, _this.enableThinking) || other.enableThinking == _this.enableThinking)&&(identical(other.proReasoningEnabled, _this.proReasoningEnabled) || other.proReasoningEnabled == _this.proReasoningEnabled)&&(identical(other.proReasoningDepth, _this.proReasoningDepth) || other.proReasoningDepth == _this.proReasoningDepth)&&(identical(other.proReasoningCandidateRouting, _this.proReasoningCandidateRouting) || other.proReasoningCandidateRouting == _this.proReasoningCandidateRouting)&&(identical(other.generalPrimaryModel, _this.generalPrimaryModel) || other.generalPrimaryModel == _this.generalPrimaryModel)&&(identical(other.codingPrimaryModel, _this.codingPrimaryModel) || other.codingPrimaryModel == _this.codingPrimaryModel)&&(identical(other.planPrimaryModel, _this.planPrimaryModel) || other.planPrimaryModel == _this.planPrimaryModel)&&(identical(other.generalPrimaryEndpointId, _this.generalPrimaryEndpointId) || other.generalPrimaryEndpointId == _this.generalPrimaryEndpointId)&&(identical(other.codingPrimaryEndpointId, _this.codingPrimaryEndpointId) || other.codingPrimaryEndpointId == _this.codingPrimaryEndpointId)&&(identical(other.planPrimaryEndpointId, _this.planPrimaryEndpointId) || other.planPrimaryEndpointId == _this.planPrimaryEndpointId)&&(identical(other.memoryExtractionModel, _this.memoryExtractionModel) || other.memoryExtractionModel == _this.memoryExtractionModel)&&(identical(other.subagentModel, _this.subagentModel) || other.subagentModel == _this.subagentModel)&&(identical(other.goalSuggestionModel, _this.goalSuggestionModel) || other.goalSuggestionModel == _this.goalSuggestionModel)&&(identical(other.approvalAutoReviewModel, _this.approvalAutoReviewModel) || other.approvalAutoReviewModel == _this.approvalAutoReviewModel)&&(identical(other.planningModel, _this.planningModel) || other.planningModel == _this.planningModel)&&(identical(other.proReasoningModel, _this.proReasoningModel) || other.proReasoningModel == _this.proReasoningModel)&&(identical(other.codeReviewModel, _this.codeReviewModel) || other.codeReviewModel == _this.codeReviewModel)&&(identical(other.logAnalysisModel, _this.logAnalysisModel) || other.logAnalysisModel == _this.logAnalysisModel)&&(identical(other.memoryExtractionEndpointId, _this.memoryExtractionEndpointId) || other.memoryExtractionEndpointId == _this.memoryExtractionEndpointId)&&(identical(other.subagentEndpointId, _this.subagentEndpointId) || other.subagentEndpointId == _this.subagentEndpointId)&&(identical(other.goalSuggestionEndpointId, _this.goalSuggestionEndpointId) || other.goalSuggestionEndpointId == _this.goalSuggestionEndpointId)&&(identical(other.approvalAutoReviewEndpointId, _this.approvalAutoReviewEndpointId) || other.approvalAutoReviewEndpointId == _this.approvalAutoReviewEndpointId)&&(identical(other.planningEndpointId, _this.planningEndpointId) || other.planningEndpointId == _this.planningEndpointId)&&(identical(other.proReasoningEndpointId, _this.proReasoningEndpointId) || other.proReasoningEndpointId == _this.proReasoningEndpointId)&&(identical(other.codeReviewEndpointId, _this.codeReviewEndpointId) || other.codeReviewEndpointId == _this.codeReviewEndpointId)&&(identical(other.logAnalysisEndpointId, _this.logAnalysisEndpointId) || other.logAnalysisEndpointId == _this.logAnalysisEndpointId)&&(identical(other.googleChatWebhookUrl, _this.googleChatWebhookUrl) || other.googleChatWebhookUrl == _this.googleChatWebhookUrl)&&(identical(other.mcpUrl, _this.mcpUrl) || other.mcpUrl == _this.mcpUrl)&&const DeepCollectionEquality().equals(other.mcpUrls, _this.mcpUrls)&&const DeepCollectionEquality().equals(other.mcpServers, _this.mcpServers)&&(identical(other.mcpEnabled, _this.mcpEnabled) || other.mcpEnabled == _this.mcpEnabled)&&(identical(other.externalSettingsSyncEnabled, _this.externalSettingsSyncEnabled) || other.externalSettingsSyncEnabled == _this.externalSettingsSyncEnabled)&&(identical(other.externalSettingsPath, _this.externalSettingsPath) || other.externalSettingsPath == _this.externalSettingsPath)&&(identical(other.externalToolHooksEnabled, _this.externalToolHooksEnabled) || other.externalToolHooksEnabled == _this.externalToolHooksEnabled)&&const DeepCollectionEquality().equals(other.externalToolHooks, _this.externalToolHooks)&&(identical(other.ttsEnabled, _this.ttsEnabled) || other.ttsEnabled == _this.ttsEnabled)&&(identical(other.autoReadEnabled, _this.autoReadEnabled) || other.autoReadEnabled == _this.autoReadEnabled)&&(identical(other.speechRate, _this.speechRate) || other.speechRate == _this.speechRate)&&(identical(other.voiceModeAutoStop, _this.voiceModeAutoStop) || other.voiceModeAutoStop == _this.voiceModeAutoStop)&&(identical(other.whisperUrl, _this.whisperUrl) || other.whisperUrl == _this.whisperUrl)&&(identical(other.voicevoxUrl, _this.voicevoxUrl) || other.voicevoxUrl == _this.voicevoxUrl)&&(identical(other.voicevoxSpeakerId, _this.voicevoxSpeakerId) || other.voicevoxSpeakerId == _this.voicevoxSpeakerId)&&(identical(other.language, _this.language) || other.language == _this.language)&&(identical(other.themePreference, _this.themePreference) || other.themePreference == _this.themePreference)&&(identical(other.assistantMode, _this.assistantMode) || other.assistantMode == _this.assistantMode)&&(identical(other.codingApprovalMode, _this.codingApprovalMode) || other.codingApprovalMode == _this.codingApprovalMode)&&(identical(other.chatApprovalMode, _this.chatApprovalMode) || other.chatApprovalMode == _this.chatApprovalMode)&&(identical(other.confirmFileMutations, _this.confirmFileMutations) || other.confirmFileMutations == _this.confirmFileMutations)&&(identical(other.confirmLocalCommands, _this.confirmLocalCommands) || other.confirmLocalCommands == _this.confirmLocalCommands)&&(identical(other.confirmGitWrites, _this.confirmGitWrites) || other.confirmGitWrites == _this.confirmGitWrites)&&(identical(other.enableCodingVerificationFeedback, _this.enableCodingVerificationFeedback) || other.enableCodingVerificationFeedback == _this.enableCodingVerificationFeedback)&&(identical(other.codingVerificationTriggerPolicy, _this.codingVerificationTriggerPolicy) || other.codingVerificationTriggerPolicy == _this.codingVerificationTriggerPolicy)&&(identical(other.codingVerificationTimeoutSeconds, _this.codingVerificationTimeoutSeconds) || other.codingVerificationTimeoutSeconds == _this.codingVerificationTimeoutSeconds)&&(identical(other.codingVerificationMaxFailures, _this.codingVerificationMaxFailures) || other.codingVerificationMaxFailures == _this.codingVerificationMaxFailures)&&(identical(other.enableAgentsMd, _this.enableAgentsMd) || other.enableAgentsMd == _this.enableAgentsMd)&&(identical(other.composerShortcutsEnabled, _this.composerShortcutsEnabled) || other.composerShortcutsEnabled == _this.composerShortcutsEnabled)&&(identical(other.enablePrefixStableToolLoop, _this.enablePrefixStableToolLoop) || other.enablePrefixStableToolLoop == _this.enablePrefixStableToolLoop)&&(identical(other.enableSemanticSearch, _this.enableSemanticSearch) || other.enableSemanticSearch == _this.enableSemanticSearch)&&(identical(other.embeddingsModel, _this.embeddingsModel) || other.embeddingsModel == _this.embeddingsModel)&&(identical(other.embeddingsEndpointId, _this.embeddingsEndpointId) || other.embeddingsEndpointId == _this.embeddingsEndpointId)&&(identical(other.showMemoryUpdates, _this.showMemoryUpdates) || other.showMemoryUpdates == _this.showMemoryUpdates)&&(identical(other.enableLlmSessionLogs, _this.enableLlmSessionLogs) || other.enableLlmSessionLogs == _this.enableLlmSessionLogs)&&(identical(other.enableAppLogFile, _this.enableAppLogFile) || other.enableAppLogFile == _this.enableAppLogFile)&&(identical(other.feedbackUploadEnabled, _this.feedbackUploadEnabled) || other.feedbackUploadEnabled == _this.feedbackUploadEnabled)&&(identical(other.feedbackEndpointUrl, _this.feedbackEndpointUrl) || other.feedbackEndpointUrl == _this.feedbackEndpointUrl)&&(identical(other.feedbackEndpointAuthToken, _this.feedbackEndpointAuthToken) || other.feedbackEndpointAuthToken == _this.feedbackEndpointAuthToken)&&(identical(other.demoMode, _this.demoMode) || other.demoMode == _this.demoMode)&&(identical(other.onboardingCompleted, _this.onboardingCompleted) || other.onboardingCompleted == _this.onboardingCompleted)&&(identical(other.browserToolsEnabled, _this.browserToolsEnabled) || other.browserToolsEnabled == _this.browserToolsEnabled)&&const DeepCollectionEquality().equals(other.disabledBuiltInTools, _this.disabledBuiltInTools)&&const DeepCollectionEquality().equals(other.localCommandPermissionRules, _this.localCommandPermissionRules)&&const DeepCollectionEquality().equals(other.routineComputerUseActionAllowlist, _this.routineComputerUseActionAllowlist)&&const DeepCollectionEquality().equals(other.modelCapabilityProfiles, _this.modelCapabilityProfiles)&&const DeepCollectionEquality().equals(other.modelHarnessConfigs, _this.modelHarnessConfigs)&&const DeepCollectionEquality().equals(other.modelCapabilityProfileRevisions, _this.modelCapabilityProfileRevisions)&&(identical(other.idleMaintenanceEnabled, _this.idleMaintenanceEnabled) || other.idleMaintenanceEnabled == _this.idleMaintenanceEnabled)&&(identical(other.idleMaintenanceWindowStartMinutes, _this.idleMaintenanceWindowStartMinutes) || other.idleMaintenanceWindowStartMinutes == _this.idleMaintenanceWindowStartMinutes)&&(identical(other.idleMaintenanceWindowEndMinutes, _this.idleMaintenanceWindowEndMinutes) || other.idleMaintenanceWindowEndMinutes == _this.idleMaintenanceWindowEndMinutes)&&(identical(other.idleMaintenanceMinIdleMinutes, _this.idleMaintenanceMinIdleMinutes) || other.idleMaintenanceMinIdleMinutes == _this.idleMaintenanceMinIdleMinutes)&&(identical(other.idleMaintenanceRequireAcPower, _this.idleMaintenanceRequireAcPower) || other.idleMaintenanceRequireAcPower == _this.idleMaintenanceRequireAcPower));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AppSettings;
  return Object.hashAll([runtimeType,_this.llmProvider,_this.baseUrl,_this.model,_this.apiKey,const DeepCollectionEquality().hash(_this.llmEndpoints),_this.activeLlmEndpointId,_this.temperature,_this.maxTokens,_this.reasoningEffort,_this.enableThinking,_this.proReasoningEnabled,_this.proReasoningDepth,_this.proReasoningCandidateRouting,_this.generalPrimaryModel,_this.codingPrimaryModel,_this.planPrimaryModel,_this.generalPrimaryEndpointId,_this.codingPrimaryEndpointId,_this.planPrimaryEndpointId,_this.memoryExtractionModel,_this.subagentModel,_this.goalSuggestionModel,_this.approvalAutoReviewModel,_this.planningModel,_this.proReasoningModel,_this.codeReviewModel,_this.logAnalysisModel,_this.memoryExtractionEndpointId,_this.subagentEndpointId,_this.goalSuggestionEndpointId,_this.approvalAutoReviewEndpointId,_this.planningEndpointId,_this.proReasoningEndpointId,_this.codeReviewEndpointId,_this.logAnalysisEndpointId,_this.googleChatWebhookUrl,_this.mcpUrl,const DeepCollectionEquality().hash(_this.mcpUrls),const DeepCollectionEquality().hash(_this.mcpServers),_this.mcpEnabled,_this.externalSettingsSyncEnabled,_this.externalSettingsPath,_this.externalToolHooksEnabled,const DeepCollectionEquality().hash(_this.externalToolHooks),_this.ttsEnabled,_this.autoReadEnabled,_this.speechRate,_this.voiceModeAutoStop,_this.whisperUrl,_this.voicevoxUrl,_this.voicevoxSpeakerId,_this.language,_this.themePreference,_this.assistantMode,_this.codingApprovalMode,_this.chatApprovalMode,_this.confirmFileMutations,_this.confirmLocalCommands,_this.confirmGitWrites,_this.enableCodingVerificationFeedback,_this.codingVerificationTriggerPolicy,_this.codingVerificationTimeoutSeconds,_this.codingVerificationMaxFailures,_this.enableAgentsMd,_this.composerShortcutsEnabled,_this.enablePrefixStableToolLoop,_this.enableSemanticSearch,_this.embeddingsModel,_this.embeddingsEndpointId,_this.showMemoryUpdates,_this.enableLlmSessionLogs,_this.enableAppLogFile,_this.feedbackUploadEnabled,_this.feedbackEndpointUrl,_this.feedbackEndpointAuthToken,_this.demoMode,_this.onboardingCompleted,_this.browserToolsEnabled,const DeepCollectionEquality().hash(_this.disabledBuiltInTools),const DeepCollectionEquality().hash(_this.localCommandPermissionRules),const DeepCollectionEquality().hash(_this.routineComputerUseActionAllowlist),const DeepCollectionEquality().hash(_this.modelCapabilityProfiles),const DeepCollectionEquality().hash(_this.modelHarnessConfigs),const DeepCollectionEquality().hash(_this.modelCapabilityProfileRevisions),_this.idleMaintenanceEnabled,_this.idleMaintenanceWindowStartMinutes,_this.idleMaintenanceWindowEndMinutes,_this.idleMaintenanceMinIdleMinutes,_this.idleMaintenanceRequireAcPower]);
}

@override
String toString() {
  final _this = this as AppSettings;
  return 'AppSettings(llmProvider: ${_this.llmProvider}, baseUrl: ${_this.baseUrl}, model: ${_this.model}, apiKey: ${_this.apiKey}, llmEndpoints: ${_this.llmEndpoints}, activeLlmEndpointId: ${_this.activeLlmEndpointId}, temperature: ${_this.temperature}, maxTokens: ${_this.maxTokens}, reasoningEffort: ${_this.reasoningEffort}, enableThinking: ${_this.enableThinking}, proReasoningEnabled: ${_this.proReasoningEnabled}, proReasoningDepth: ${_this.proReasoningDepth}, proReasoningCandidateRouting: ${_this.proReasoningCandidateRouting}, generalPrimaryModel: ${_this.generalPrimaryModel}, codingPrimaryModel: ${_this.codingPrimaryModel}, planPrimaryModel: ${_this.planPrimaryModel}, generalPrimaryEndpointId: ${_this.generalPrimaryEndpointId}, codingPrimaryEndpointId: ${_this.codingPrimaryEndpointId}, planPrimaryEndpointId: ${_this.planPrimaryEndpointId}, memoryExtractionModel: ${_this.memoryExtractionModel}, subagentModel: ${_this.subagentModel}, goalSuggestionModel: ${_this.goalSuggestionModel}, approvalAutoReviewModel: ${_this.approvalAutoReviewModel}, planningModel: ${_this.planningModel}, proReasoningModel: ${_this.proReasoningModel}, codeReviewModel: ${_this.codeReviewModel}, logAnalysisModel: ${_this.logAnalysisModel}, memoryExtractionEndpointId: ${_this.memoryExtractionEndpointId}, subagentEndpointId: ${_this.subagentEndpointId}, goalSuggestionEndpointId: ${_this.goalSuggestionEndpointId}, approvalAutoReviewEndpointId: ${_this.approvalAutoReviewEndpointId}, planningEndpointId: ${_this.planningEndpointId}, proReasoningEndpointId: ${_this.proReasoningEndpointId}, codeReviewEndpointId: ${_this.codeReviewEndpointId}, logAnalysisEndpointId: ${_this.logAnalysisEndpointId}, googleChatWebhookUrl: ${_this.googleChatWebhookUrl}, mcpUrl: ${_this.mcpUrl}, mcpUrls: ${_this.mcpUrls}, mcpServers: ${_this.mcpServers}, mcpEnabled: ${_this.mcpEnabled}, externalSettingsSyncEnabled: ${_this.externalSettingsSyncEnabled}, externalSettingsPath: ${_this.externalSettingsPath}, externalToolHooksEnabled: ${_this.externalToolHooksEnabled}, externalToolHooks: ${_this.externalToolHooks}, ttsEnabled: ${_this.ttsEnabled}, autoReadEnabled: ${_this.autoReadEnabled}, speechRate: ${_this.speechRate}, voiceModeAutoStop: ${_this.voiceModeAutoStop}, whisperUrl: ${_this.whisperUrl}, voicevoxUrl: ${_this.voicevoxUrl}, voicevoxSpeakerId: ${_this.voicevoxSpeakerId}, language: ${_this.language}, themePreference: ${_this.themePreference}, assistantMode: ${_this.assistantMode}, codingApprovalMode: ${_this.codingApprovalMode}, chatApprovalMode: ${_this.chatApprovalMode}, confirmFileMutations: ${_this.confirmFileMutations}, confirmLocalCommands: ${_this.confirmLocalCommands}, confirmGitWrites: ${_this.confirmGitWrites}, enableCodingVerificationFeedback: ${_this.enableCodingVerificationFeedback}, codingVerificationTriggerPolicy: ${_this.codingVerificationTriggerPolicy}, codingVerificationTimeoutSeconds: ${_this.codingVerificationTimeoutSeconds}, codingVerificationMaxFailures: ${_this.codingVerificationMaxFailures}, enableAgentsMd: ${_this.enableAgentsMd}, composerShortcutsEnabled: ${_this.composerShortcutsEnabled}, enablePrefixStableToolLoop: ${_this.enablePrefixStableToolLoop}, enableSemanticSearch: ${_this.enableSemanticSearch}, embeddingsModel: ${_this.embeddingsModel}, embeddingsEndpointId: ${_this.embeddingsEndpointId}, showMemoryUpdates: ${_this.showMemoryUpdates}, enableLlmSessionLogs: ${_this.enableLlmSessionLogs}, enableAppLogFile: ${_this.enableAppLogFile}, feedbackUploadEnabled: ${_this.feedbackUploadEnabled}, feedbackEndpointUrl: ${_this.feedbackEndpointUrl}, feedbackEndpointAuthToken: ${_this.feedbackEndpointAuthToken}, demoMode: ${_this.demoMode}, onboardingCompleted: ${_this.onboardingCompleted}, browserToolsEnabled: ${_this.browserToolsEnabled}, disabledBuiltInTools: ${_this.disabledBuiltInTools}, localCommandPermissionRules: ${_this.localCommandPermissionRules}, routineComputerUseActionAllowlist: ${_this.routineComputerUseActionAllowlist}, modelCapabilityProfiles: ${_this.modelCapabilityProfiles}, modelHarnessConfigs: ${_this.modelHarnessConfigs}, modelCapabilityProfileRevisions: ${_this.modelCapabilityProfileRevisions}, idleMaintenanceEnabled: ${_this.idleMaintenanceEnabled}, idleMaintenanceWindowStartMinutes: ${_this.idleMaintenanceWindowStartMinutes}, idleMaintenanceWindowEndMinutes: ${_this.idleMaintenanceWindowEndMinutes}, idleMaintenanceMinIdleMinutes: ${_this.idleMaintenanceMinIdleMinutes}, idleMaintenanceRequireAcPower: ${_this.idleMaintenanceRequireAcPower})';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider llmProvider, String baseUrl, String model, String apiKey,@JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson) List<LlmEndpoint> llmEndpoints, String activeLlmEndpointId, double temperature, int maxTokens,@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference reasoningEffort, bool? enableThinking, bool proReasoningEnabled,@JsonKey(unknownEnumValue: ProReasoningDepth.deep) ProReasoningDepth proReasoningDepth,@JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh) ProReasoningCandidateRouting proReasoningCandidateRouting, String generalPrimaryModel, String codingPrimaryModel, String planPrimaryModel, String generalPrimaryEndpointId, String codingPrimaryEndpointId, String planPrimaryEndpointId, String memoryExtractionModel, String subagentModel, String goalSuggestionModel, String approvalAutoReviewModel, String planningModel, String proReasoningModel, String codeReviewModel, String logAnalysisModel, String memoryExtractionEndpointId, String subagentEndpointId, String goalSuggestionEndpointId, String approvalAutoReviewEndpointId, String planningEndpointId, String proReasoningEndpointId, String codeReviewEndpointId, String logAnalysisEndpointId, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool externalSettingsSyncEnabled, String externalSettingsPath, bool externalToolHooksEnabled,@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> externalToolHooks, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AppThemePreference.dark) AppThemePreference themePreference,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode codingApprovalMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode chatApprovalMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool enableCodingVerificationFeedback,@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) CodingVerificationTriggerPolicy codingVerificationTriggerPolicy, int codingVerificationTimeoutSeconds, int codingVerificationMaxFailures, bool enableAgentsMd, bool composerShortcutsEnabled, bool enablePrefixStableToolLoop, bool enableSemanticSearch, String embeddingsModel, String embeddingsEndpointId, bool showMemoryUpdates, bool enableLlmSessionLogs, bool enableAppLogFile, bool feedbackUploadEnabled, String feedbackEndpointUrl, String feedbackEndpointAuthToken, bool demoMode, bool onboardingCompleted, bool browserToolsEnabled, List<String> disabledBuiltInTools, List<LocalCommandPermissionRule> localCommandPermissionRules, List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist,@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> modelCapabilityProfiles,@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> modelHarnessConfigs,@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions, bool idleMaintenanceEnabled, int idleMaintenanceWindowStartMinutes, int idleMaintenanceWindowEndMinutes, int idleMaintenanceMinIdleMinutes, bool idleMaintenanceRequireAcPower
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
@pragma('vm:prefer-inline') @override $Res call({Object? llmProvider = null,Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? llmEndpoints = null,Object? activeLlmEndpointId = null,Object? temperature = null,Object? maxTokens = null,Object? reasoningEffort = null,Object? enableThinking = freezed,Object? proReasoningEnabled = null,Object? proReasoningDepth = null,Object? proReasoningCandidateRouting = null,Object? generalPrimaryModel = null,Object? codingPrimaryModel = null,Object? planPrimaryModel = null,Object? generalPrimaryEndpointId = null,Object? codingPrimaryEndpointId = null,Object? planPrimaryEndpointId = null,Object? memoryExtractionModel = null,Object? subagentModel = null,Object? goalSuggestionModel = null,Object? approvalAutoReviewModel = null,Object? planningModel = null,Object? proReasoningModel = null,Object? codeReviewModel = null,Object? logAnalysisModel = null,Object? memoryExtractionEndpointId = null,Object? subagentEndpointId = null,Object? goalSuggestionEndpointId = null,Object? approvalAutoReviewEndpointId = null,Object? planningEndpointId = null,Object? proReasoningEndpointId = null,Object? codeReviewEndpointId = null,Object? logAnalysisEndpointId = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? externalSettingsSyncEnabled = null,Object? externalSettingsPath = null,Object? externalToolHooksEnabled = null,Object? externalToolHooks = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? themePreference = null,Object? assistantMode = null,Object? codingApprovalMode = null,Object? chatApprovalMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? enableCodingVerificationFeedback = null,Object? codingVerificationTriggerPolicy = null,Object? codingVerificationTimeoutSeconds = null,Object? codingVerificationMaxFailures = null,Object? enableAgentsMd = null,Object? composerShortcutsEnabled = null,Object? enablePrefixStableToolLoop = null,Object? enableSemanticSearch = null,Object? embeddingsModel = null,Object? embeddingsEndpointId = null,Object? showMemoryUpdates = null,Object? enableLlmSessionLogs = null,Object? enableAppLogFile = null,Object? feedbackUploadEnabled = null,Object? feedbackEndpointUrl = null,Object? feedbackEndpointAuthToken = null,Object? demoMode = null,Object? onboardingCompleted = null,Object? browserToolsEnabled = null,Object? disabledBuiltInTools = null,Object? localCommandPermissionRules = null,Object? routineComputerUseActionAllowlist = null,Object? modelCapabilityProfiles = null,Object? modelHarnessConfigs = null,Object? modelCapabilityProfileRevisions = null,Object? idleMaintenanceEnabled = null,Object? idleMaintenanceWindowStartMinutes = null,Object? idleMaintenanceWindowEndMinutes = null,Object? idleMaintenanceMinIdleMinutes = null,Object? idleMaintenanceRequireAcPower = null,}) {
  return _then(AppSettings(
llmProvider: null == llmProvider ? _self.llmProvider : llmProvider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,llmEndpoints: null == llmEndpoints ? _self.llmEndpoints : llmEndpoints // ignore: cast_nullable_to_non_nullable
as List<LlmEndpoint>,activeLlmEndpointId: null == activeLlmEndpointId ? _self.activeLlmEndpointId : activeLlmEndpointId // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningEffort: null == reasoningEffort ? _self.reasoningEffort : reasoningEffort // ignore: cast_nullable_to_non_nullable
as ReasoningEffortPreference,enableThinking: freezed == enableThinking ? _self.enableThinking : enableThinking // ignore: cast_nullable_to_non_nullable
as bool?,proReasoningEnabled: null == proReasoningEnabled ? _self.proReasoningEnabled : proReasoningEnabled // ignore: cast_nullable_to_non_nullable
as bool,proReasoningDepth: null == proReasoningDepth ? _self.proReasoningDepth : proReasoningDepth // ignore: cast_nullable_to_non_nullable
as ProReasoningDepth,proReasoningCandidateRouting: null == proReasoningCandidateRouting ? _self.proReasoningCandidateRouting : proReasoningCandidateRouting // ignore: cast_nullable_to_non_nullable
as ProReasoningCandidateRouting,generalPrimaryModel: null == generalPrimaryModel ? _self.generalPrimaryModel : generalPrimaryModel // ignore: cast_nullable_to_non_nullable
as String,codingPrimaryModel: null == codingPrimaryModel ? _self.codingPrimaryModel : codingPrimaryModel // ignore: cast_nullable_to_non_nullable
as String,planPrimaryModel: null == planPrimaryModel ? _self.planPrimaryModel : planPrimaryModel // ignore: cast_nullable_to_non_nullable
as String,generalPrimaryEndpointId: null == generalPrimaryEndpointId ? _self.generalPrimaryEndpointId : generalPrimaryEndpointId // ignore: cast_nullable_to_non_nullable
as String,codingPrimaryEndpointId: null == codingPrimaryEndpointId ? _self.codingPrimaryEndpointId : codingPrimaryEndpointId // ignore: cast_nullable_to_non_nullable
as String,planPrimaryEndpointId: null == planPrimaryEndpointId ? _self.planPrimaryEndpointId : planPrimaryEndpointId // ignore: cast_nullable_to_non_nullable
as String,memoryExtractionModel: null == memoryExtractionModel ? _self.memoryExtractionModel : memoryExtractionModel // ignore: cast_nullable_to_non_nullable
as String,subagentModel: null == subagentModel ? _self.subagentModel : subagentModel // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionModel: null == goalSuggestionModel ? _self.goalSuggestionModel : goalSuggestionModel // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewModel: null == approvalAutoReviewModel ? _self.approvalAutoReviewModel : approvalAutoReviewModel // ignore: cast_nullable_to_non_nullable
as String,planningModel: null == planningModel ? _self.planningModel : planningModel // ignore: cast_nullable_to_non_nullable
as String,proReasoningModel: null == proReasoningModel ? _self.proReasoningModel : proReasoningModel // ignore: cast_nullable_to_non_nullable
as String,codeReviewModel: null == codeReviewModel ? _self.codeReviewModel : codeReviewModel // ignore: cast_nullable_to_non_nullable
as String,logAnalysisModel: null == logAnalysisModel ? _self.logAnalysisModel : logAnalysisModel // ignore: cast_nullable_to_non_nullable
as String,memoryExtractionEndpointId: null == memoryExtractionEndpointId ? _self.memoryExtractionEndpointId : memoryExtractionEndpointId // ignore: cast_nullable_to_non_nullable
as String,subagentEndpointId: null == subagentEndpointId ? _self.subagentEndpointId : subagentEndpointId // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionEndpointId: null == goalSuggestionEndpointId ? _self.goalSuggestionEndpointId : goalSuggestionEndpointId // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewEndpointId: null == approvalAutoReviewEndpointId ? _self.approvalAutoReviewEndpointId : approvalAutoReviewEndpointId // ignore: cast_nullable_to_non_nullable
as String,planningEndpointId: null == planningEndpointId ? _self.planningEndpointId : planningEndpointId // ignore: cast_nullable_to_non_nullable
as String,proReasoningEndpointId: null == proReasoningEndpointId ? _self.proReasoningEndpointId : proReasoningEndpointId // ignore: cast_nullable_to_non_nullable
as String,codeReviewEndpointId: null == codeReviewEndpointId ? _self.codeReviewEndpointId : codeReviewEndpointId // ignore: cast_nullable_to_non_nullable
as String,logAnalysisEndpointId: null == logAnalysisEndpointId ? _self.logAnalysisEndpointId : logAnalysisEndpointId // ignore: cast_nullable_to_non_nullable
as String,googleChatWebhookUrl: null == googleChatWebhookUrl ? _self.googleChatWebhookUrl : googleChatWebhookUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrl: null == mcpUrl ? _self.mcpUrl : mcpUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrls: null == mcpUrls ? _self.mcpUrls : mcpUrls // ignore: cast_nullable_to_non_nullable
as List<String>,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServerConfig>,mcpEnabled: null == mcpEnabled ? _self.mcpEnabled : mcpEnabled // ignore: cast_nullable_to_non_nullable
as bool,externalSettingsSyncEnabled: null == externalSettingsSyncEnabled ? _self.externalSettingsSyncEnabled : externalSettingsSyncEnabled // ignore: cast_nullable_to_non_nullable
as bool,externalSettingsPath: null == externalSettingsPath ? _self.externalSettingsPath : externalSettingsPath // ignore: cast_nullable_to_non_nullable
as String,externalToolHooksEnabled: null == externalToolHooksEnabled ? _self.externalToolHooksEnabled : externalToolHooksEnabled // ignore: cast_nullable_to_non_nullable
as bool,externalToolHooks: null == externalToolHooks ? _self.externalToolHooks : externalToolHooks // ignore: cast_nullable_to_non_nullable
as List<ExternalToolHook>,ttsEnabled: null == ttsEnabled ? _self.ttsEnabled : ttsEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoReadEnabled: null == autoReadEnabled ? _self.autoReadEnabled : autoReadEnabled // ignore: cast_nullable_to_non_nullable
as bool,speechRate: null == speechRate ? _self.speechRate : speechRate // ignore: cast_nullable_to_non_nullable
as double,voiceModeAutoStop: null == voiceModeAutoStop ? _self.voiceModeAutoStop : voiceModeAutoStop // ignore: cast_nullable_to_non_nullable
as bool,whisperUrl: null == whisperUrl ? _self.whisperUrl : whisperUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxUrl: null == voicevoxUrl ? _self.voicevoxUrl : voicevoxUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxSpeakerId: null == voicevoxSpeakerId ? _self.voicevoxSpeakerId : voicevoxSpeakerId // ignore: cast_nullable_to_non_nullable
as int,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,themePreference: null == themePreference ? _self.themePreference : themePreference // ignore: cast_nullable_to_non_nullable
as AppThemePreference,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
as AssistantMode,codingApprovalMode: null == codingApprovalMode ? _self.codingApprovalMode : codingApprovalMode // ignore: cast_nullable_to_non_nullable
as ToolApprovalMode,chatApprovalMode: null == chatApprovalMode ? _self.chatApprovalMode : chatApprovalMode // ignore: cast_nullable_to_non_nullable
as ToolApprovalMode,confirmFileMutations: null == confirmFileMutations ? _self.confirmFileMutations : confirmFileMutations // ignore: cast_nullable_to_non_nullable
as bool,confirmLocalCommands: null == confirmLocalCommands ? _self.confirmLocalCommands : confirmLocalCommands // ignore: cast_nullable_to_non_nullable
as bool,confirmGitWrites: null == confirmGitWrites ? _self.confirmGitWrites : confirmGitWrites // ignore: cast_nullable_to_non_nullable
as bool,enableCodingVerificationFeedback: null == enableCodingVerificationFeedback ? _self.enableCodingVerificationFeedback : enableCodingVerificationFeedback // ignore: cast_nullable_to_non_nullable
as bool,codingVerificationTriggerPolicy: null == codingVerificationTriggerPolicy ? _self.codingVerificationTriggerPolicy : codingVerificationTriggerPolicy // ignore: cast_nullable_to_non_nullable
as CodingVerificationTriggerPolicy,codingVerificationTimeoutSeconds: null == codingVerificationTimeoutSeconds ? _self.codingVerificationTimeoutSeconds : codingVerificationTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,codingVerificationMaxFailures: null == codingVerificationMaxFailures ? _self.codingVerificationMaxFailures : codingVerificationMaxFailures // ignore: cast_nullable_to_non_nullable
as int,enableAgentsMd: null == enableAgentsMd ? _self.enableAgentsMd : enableAgentsMd // ignore: cast_nullable_to_non_nullable
as bool,composerShortcutsEnabled: null == composerShortcutsEnabled ? _self.composerShortcutsEnabled : composerShortcutsEnabled // ignore: cast_nullable_to_non_nullable
as bool,enablePrefixStableToolLoop: null == enablePrefixStableToolLoop ? _self.enablePrefixStableToolLoop : enablePrefixStableToolLoop // ignore: cast_nullable_to_non_nullable
as bool,enableSemanticSearch: null == enableSemanticSearch ? _self.enableSemanticSearch : enableSemanticSearch // ignore: cast_nullable_to_non_nullable
as bool,embeddingsModel: null == embeddingsModel ? _self.embeddingsModel : embeddingsModel // ignore: cast_nullable_to_non_nullable
as String,embeddingsEndpointId: null == embeddingsEndpointId ? _self.embeddingsEndpointId : embeddingsEndpointId // ignore: cast_nullable_to_non_nullable
as String,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,enableLlmSessionLogs: null == enableLlmSessionLogs ? _self.enableLlmSessionLogs : enableLlmSessionLogs // ignore: cast_nullable_to_non_nullable
as bool,enableAppLogFile: null == enableAppLogFile ? _self.enableAppLogFile : enableAppLogFile // ignore: cast_nullable_to_non_nullable
as bool,feedbackUploadEnabled: null == feedbackUploadEnabled ? _self.feedbackUploadEnabled : feedbackUploadEnabled // ignore: cast_nullable_to_non_nullable
as bool,feedbackEndpointUrl: null == feedbackEndpointUrl ? _self.feedbackEndpointUrl : feedbackEndpointUrl // ignore: cast_nullable_to_non_nullable
as String,feedbackEndpointAuthToken: null == feedbackEndpointAuthToken ? _self.feedbackEndpointAuthToken : feedbackEndpointAuthToken // ignore: cast_nullable_to_non_nullable
as String,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,onboardingCompleted: null == onboardingCompleted ? _self.onboardingCompleted : onboardingCompleted // ignore: cast_nullable_to_non_nullable
as bool,browserToolsEnabled: null == browserToolsEnabled ? _self.browserToolsEnabled : browserToolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self.disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,localCommandPermissionRules: null == localCommandPermissionRules ? _self.localCommandPermissionRules : localCommandPermissionRules // ignore: cast_nullable_to_non_nullable
as List<LocalCommandPermissionRule>,routineComputerUseActionAllowlist: null == routineComputerUseActionAllowlist ? _self.routineComputerUseActionAllowlist : routineComputerUseActionAllowlist // ignore: cast_nullable_to_non_nullable
as List<RoutineComputerUseActionAllowlistEntry>,modelCapabilityProfiles: null == modelCapabilityProfiles ? _self.modelCapabilityProfiles : modelCapabilityProfiles // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfile>,modelHarnessConfigs: null == modelHarnessConfigs ? _self.modelHarnessConfigs : modelHarnessConfigs // ignore: cast_nullable_to_non_nullable
as List<ModelHarnessConfig>,modelCapabilityProfileRevisions: null == modelCapabilityProfileRevisions ? _self.modelCapabilityProfileRevisions : modelCapabilityProfileRevisions // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfileRevision>,idleMaintenanceEnabled: null == idleMaintenanceEnabled ? _self.idleMaintenanceEnabled : idleMaintenanceEnabled // ignore: cast_nullable_to_non_nullable
as bool,idleMaintenanceWindowStartMinutes: null == idleMaintenanceWindowStartMinutes ? _self.idleMaintenanceWindowStartMinutes : idleMaintenanceWindowStartMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceWindowEndMinutes: null == idleMaintenanceWindowEndMinutes ? _self.idleMaintenanceWindowEndMinutes : idleMaintenanceWindowEndMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceMinIdleMinutes: null == idleMaintenanceMinIdleMinutes ? _self.idleMaintenanceMinIdleMinutes : idleMaintenanceMinIdleMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceRequireAcPower: null == idleMaintenanceRequireAcPower ? _self.idleMaintenanceRequireAcPower : idleMaintenanceRequireAcPower // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider llmProvider,  String baseUrl,  String model,  String apiKey, @JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson)  List<LlmEndpoint> llmEndpoints,  String activeLlmEndpointId,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  bool? enableThinking,  bool proReasoningEnabled, @JsonKey(unknownEnumValue: ProReasoningDepth.deep)  ProReasoningDepth proReasoningDepth, @JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh)  ProReasoningCandidateRouting proReasoningCandidateRouting,  String generalPrimaryModel,  String codingPrimaryModel,  String planPrimaryModel,  String generalPrimaryEndpointId,  String codingPrimaryEndpointId,  String planPrimaryEndpointId,  String memoryExtractionModel,  String subagentModel,  String goalSuggestionModel,  String approvalAutoReviewModel,  String planningModel,  String proReasoningModel,  String codeReviewModel,  String logAnalysisModel,  String memoryExtractionEndpointId,  String subagentEndpointId,  String goalSuggestionEndpointId,  String approvalAutoReviewEndpointId,  String planningEndpointId,  String proReasoningEndpointId,  String codeReviewEndpointId,  String logAnalysisEndpointId,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool externalSettingsSyncEnabled,  String externalSettingsPath,  bool externalToolHooksEnabled, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AppThemePreference.dark)  AppThemePreference themePreference, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode codingApprovalMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode chatApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool enableCodingVerificationFeedback, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim)  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,  int codingVerificationTimeoutSeconds,  int codingVerificationMaxFailures,  bool enableAgentsMd,  bool composerShortcutsEnabled,  bool enablePrefixStableToolLoop,  bool enableSemanticSearch,  String embeddingsModel,  String embeddingsEndpointId,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool enableAppLogFile,  bool feedbackUploadEnabled,  String feedbackEndpointUrl,  String feedbackEndpointAuthToken,  bool demoMode,  bool onboardingCompleted,  bool browserToolsEnabled,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist, @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles, @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs, @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions,  bool idleMaintenanceEnabled,  int idleMaintenanceWindowStartMinutes,  int idleMaintenanceWindowEndMinutes,  int idleMaintenanceMinIdleMinutes,  bool idleMaintenanceRequireAcPower)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.llmProvider,_that.baseUrl,_that.model,_that.apiKey,_that.llmEndpoints,_that.activeLlmEndpointId,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.enableThinking,_that.proReasoningEnabled,_that.proReasoningDepth,_that.proReasoningCandidateRouting,_that.generalPrimaryModel,_that.codingPrimaryModel,_that.planPrimaryModel,_that.generalPrimaryEndpointId,_that.codingPrimaryEndpointId,_that.planPrimaryEndpointId,_that.memoryExtractionModel,_that.subagentModel,_that.goalSuggestionModel,_that.approvalAutoReviewModel,_that.planningModel,_that.proReasoningModel,_that.codeReviewModel,_that.logAnalysisModel,_that.memoryExtractionEndpointId,_that.subagentEndpointId,_that.goalSuggestionEndpointId,_that.approvalAutoReviewEndpointId,_that.planningEndpointId,_that.proReasoningEndpointId,_that.codeReviewEndpointId,_that.logAnalysisEndpointId,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.externalSettingsSyncEnabled,_that.externalSettingsPath,_that.externalToolHooksEnabled,_that.externalToolHooks,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.themePreference,_that.assistantMode,_that.codingApprovalMode,_that.chatApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.enableCodingVerificationFeedback,_that.codingVerificationTriggerPolicy,_that.codingVerificationTimeoutSeconds,_that.codingVerificationMaxFailures,_that.enableAgentsMd,_that.composerShortcutsEnabled,_that.enablePrefixStableToolLoop,_that.enableSemanticSearch,_that.embeddingsModel,_that.embeddingsEndpointId,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.enableAppLogFile,_that.feedbackUploadEnabled,_that.feedbackEndpointUrl,_that.feedbackEndpointAuthToken,_that.demoMode,_that.onboardingCompleted,_that.browserToolsEnabled,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist,_that.modelCapabilityProfiles,_that.modelHarnessConfigs,_that.modelCapabilityProfileRevisions,_that.idleMaintenanceEnabled,_that.idleMaintenanceWindowStartMinutes,_that.idleMaintenanceWindowEndMinutes,_that.idleMaintenanceMinIdleMinutes,_that.idleMaintenanceRequireAcPower);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider llmProvider,  String baseUrl,  String model,  String apiKey, @JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson)  List<LlmEndpoint> llmEndpoints,  String activeLlmEndpointId,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  bool? enableThinking,  bool proReasoningEnabled, @JsonKey(unknownEnumValue: ProReasoningDepth.deep)  ProReasoningDepth proReasoningDepth, @JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh)  ProReasoningCandidateRouting proReasoningCandidateRouting,  String generalPrimaryModel,  String codingPrimaryModel,  String planPrimaryModel,  String generalPrimaryEndpointId,  String codingPrimaryEndpointId,  String planPrimaryEndpointId,  String memoryExtractionModel,  String subagentModel,  String goalSuggestionModel,  String approvalAutoReviewModel,  String planningModel,  String proReasoningModel,  String codeReviewModel,  String logAnalysisModel,  String memoryExtractionEndpointId,  String subagentEndpointId,  String goalSuggestionEndpointId,  String approvalAutoReviewEndpointId,  String planningEndpointId,  String proReasoningEndpointId,  String codeReviewEndpointId,  String logAnalysisEndpointId,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool externalSettingsSyncEnabled,  String externalSettingsPath,  bool externalToolHooksEnabled, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AppThemePreference.dark)  AppThemePreference themePreference, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode codingApprovalMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode chatApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool enableCodingVerificationFeedback, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim)  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,  int codingVerificationTimeoutSeconds,  int codingVerificationMaxFailures,  bool enableAgentsMd,  bool composerShortcutsEnabled,  bool enablePrefixStableToolLoop,  bool enableSemanticSearch,  String embeddingsModel,  String embeddingsEndpointId,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool enableAppLogFile,  bool feedbackUploadEnabled,  String feedbackEndpointUrl,  String feedbackEndpointAuthToken,  bool demoMode,  bool onboardingCompleted,  bool browserToolsEnabled,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist, @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles, @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs, @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions,  bool idleMaintenanceEnabled,  int idleMaintenanceWindowStartMinutes,  int idleMaintenanceWindowEndMinutes,  int idleMaintenanceMinIdleMinutes,  bool idleMaintenanceRequireAcPower)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.llmProvider,_that.baseUrl,_that.model,_that.apiKey,_that.llmEndpoints,_that.activeLlmEndpointId,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.enableThinking,_that.proReasoningEnabled,_that.proReasoningDepth,_that.proReasoningCandidateRouting,_that.generalPrimaryModel,_that.codingPrimaryModel,_that.planPrimaryModel,_that.generalPrimaryEndpointId,_that.codingPrimaryEndpointId,_that.planPrimaryEndpointId,_that.memoryExtractionModel,_that.subagentModel,_that.goalSuggestionModel,_that.approvalAutoReviewModel,_that.planningModel,_that.proReasoningModel,_that.codeReviewModel,_that.logAnalysisModel,_that.memoryExtractionEndpointId,_that.subagentEndpointId,_that.goalSuggestionEndpointId,_that.approvalAutoReviewEndpointId,_that.planningEndpointId,_that.proReasoningEndpointId,_that.codeReviewEndpointId,_that.logAnalysisEndpointId,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.externalSettingsSyncEnabled,_that.externalSettingsPath,_that.externalToolHooksEnabled,_that.externalToolHooks,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.themePreference,_that.assistantMode,_that.codingApprovalMode,_that.chatApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.enableCodingVerificationFeedback,_that.codingVerificationTriggerPolicy,_that.codingVerificationTimeoutSeconds,_that.codingVerificationMaxFailures,_that.enableAgentsMd,_that.composerShortcutsEnabled,_that.enablePrefixStableToolLoop,_that.enableSemanticSearch,_that.embeddingsModel,_that.embeddingsEndpointId,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.enableAppLogFile,_that.feedbackUploadEnabled,_that.feedbackEndpointUrl,_that.feedbackEndpointAuthToken,_that.demoMode,_that.onboardingCompleted,_that.browserToolsEnabled,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist,_that.modelCapabilityProfiles,_that.modelHarnessConfigs,_that.modelCapabilityProfileRevisions,_that.idleMaintenanceEnabled,_that.idleMaintenanceWindowStartMinutes,_that.idleMaintenanceWindowEndMinutes,_that.idleMaintenanceMinIdleMinutes,_that.idleMaintenanceRequireAcPower);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider llmProvider,  String baseUrl,  String model,  String apiKey, @JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson)  List<LlmEndpoint> llmEndpoints,  String activeLlmEndpointId,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  bool? enableThinking,  bool proReasoningEnabled, @JsonKey(unknownEnumValue: ProReasoningDepth.deep)  ProReasoningDepth proReasoningDepth, @JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh)  ProReasoningCandidateRouting proReasoningCandidateRouting,  String generalPrimaryModel,  String codingPrimaryModel,  String planPrimaryModel,  String generalPrimaryEndpointId,  String codingPrimaryEndpointId,  String planPrimaryEndpointId,  String memoryExtractionModel,  String subagentModel,  String goalSuggestionModel,  String approvalAutoReviewModel,  String planningModel,  String proReasoningModel,  String codeReviewModel,  String logAnalysisModel,  String memoryExtractionEndpointId,  String subagentEndpointId,  String goalSuggestionEndpointId,  String approvalAutoReviewEndpointId,  String planningEndpointId,  String proReasoningEndpointId,  String codeReviewEndpointId,  String logAnalysisEndpointId,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool externalSettingsSyncEnabled,  String externalSettingsPath,  bool externalToolHooksEnabled, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AppThemePreference.dark)  AppThemePreference themePreference, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode codingApprovalMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode chatApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool enableCodingVerificationFeedback, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim)  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,  int codingVerificationTimeoutSeconds,  int codingVerificationMaxFailures,  bool enableAgentsMd,  bool composerShortcutsEnabled,  bool enablePrefixStableToolLoop,  bool enableSemanticSearch,  String embeddingsModel,  String embeddingsEndpointId,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool enableAppLogFile,  bool feedbackUploadEnabled,  String feedbackEndpointUrl,  String feedbackEndpointAuthToken,  bool demoMode,  bool onboardingCompleted,  bool browserToolsEnabled,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist, @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles, @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs, @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions,  bool idleMaintenanceEnabled,  int idleMaintenanceWindowStartMinutes,  int idleMaintenanceWindowEndMinutes,  int idleMaintenanceMinIdleMinutes,  bool idleMaintenanceRequireAcPower)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.llmProvider,_that.baseUrl,_that.model,_that.apiKey,_that.llmEndpoints,_that.activeLlmEndpointId,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.enableThinking,_that.proReasoningEnabled,_that.proReasoningDepth,_that.proReasoningCandidateRouting,_that.generalPrimaryModel,_that.codingPrimaryModel,_that.planPrimaryModel,_that.generalPrimaryEndpointId,_that.codingPrimaryEndpointId,_that.planPrimaryEndpointId,_that.memoryExtractionModel,_that.subagentModel,_that.goalSuggestionModel,_that.approvalAutoReviewModel,_that.planningModel,_that.proReasoningModel,_that.codeReviewModel,_that.logAnalysisModel,_that.memoryExtractionEndpointId,_that.subagentEndpointId,_that.goalSuggestionEndpointId,_that.approvalAutoReviewEndpointId,_that.planningEndpointId,_that.proReasoningEndpointId,_that.codeReviewEndpointId,_that.logAnalysisEndpointId,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.externalSettingsSyncEnabled,_that.externalSettingsPath,_that.externalToolHooksEnabled,_that.externalToolHooks,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.themePreference,_that.assistantMode,_that.codingApprovalMode,_that.chatApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.enableCodingVerificationFeedback,_that.codingVerificationTriggerPolicy,_that.codingVerificationTimeoutSeconds,_that.codingVerificationMaxFailures,_that.enableAgentsMd,_that.composerShortcutsEnabled,_that.enablePrefixStableToolLoop,_that.enableSemanticSearch,_that.embeddingsModel,_that.embeddingsEndpointId,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.enableAppLogFile,_that.feedbackUploadEnabled,_that.feedbackEndpointUrl,_that.feedbackEndpointAuthToken,_that.demoMode,_that.onboardingCompleted,_that.browserToolsEnabled,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist,_that.modelCapabilityProfiles,_that.modelHarnessConfigs,_that.modelCapabilityProfileRevisions,_that.idleMaintenanceEnabled,_that.idleMaintenanceWindowStartMinutes,_that.idleMaintenanceWindowEndMinutes,_that.idleMaintenanceMinIdleMinutes,_that.idleMaintenanceRequireAcPower);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppSettings extends AppSettings {
  const _AppSettings({@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) this.llmProvider = LlmProvider.openAiCompatible, required this.baseUrl, required this.model, required this.apiKey, @JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson)  List<LlmEndpoint> llmEndpoints = const <LlmEndpoint>[], this.activeLlmEndpointId = '', required this.temperature, required this.maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) this.reasoningEffort = ReasoningEffortPreference.automatic, this.enableThinking, this.proReasoningEnabled = false, @JsonKey(unknownEnumValue: ProReasoningDepth.deep) this.proReasoningDepth = ProReasoningDepth.deep, @JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh) this.proReasoningCandidateRouting = ProReasoningCandidateRouting.mesh, this.generalPrimaryModel = '', this.codingPrimaryModel = '', this.planPrimaryModel = '', this.generalPrimaryEndpointId = '', this.codingPrimaryEndpointId = '', this.planPrimaryEndpointId = '', this.memoryExtractionModel = '', this.subagentModel = '', this.goalSuggestionModel = '', this.approvalAutoReviewModel = '', this.planningModel = '', this.proReasoningModel = '', this.codeReviewModel = '', this.logAnalysisModel = '', this.memoryExtractionEndpointId = '', this.subagentEndpointId = '', this.goalSuggestionEndpointId = '', this.approvalAutoReviewEndpointId = '', this.planningEndpointId = '', this.proReasoningEndpointId = '', this.codeReviewEndpointId = '', this.logAnalysisEndpointId = '', this.googleChatWebhookUrl = '', this.mcpUrl = '',  List<String> mcpUrls = const <String>[],  List<McpServerConfig> mcpServers = const <McpServerConfig>[], this.mcpEnabled = false, this.externalSettingsSyncEnabled = false, this.externalSettingsPath = '~/.caverno/config.json', this.externalToolHooksEnabled = false, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks = const <ExternalToolHook>[], this.ttsEnabled = true, this.autoReadEnabled = false, this.speechRate = 0.5, this.voiceModeAutoStop = true, this.whisperUrl = 'http://localhost:8080', this.voicevoxUrl = 'http://localhost:50021', this.voicevoxSpeakerId = 0, this.language = 'system', @JsonKey(unknownEnumValue: AppThemePreference.dark) this.themePreference = AppThemePreference.dark, @JsonKey(unknownEnumValue: AssistantMode.general) this.assistantMode = AssistantMode.general, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) this.codingApprovalMode = ToolApprovalMode.defaultPermissions, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) this.chatApprovalMode = ToolApprovalMode.defaultPermissions, this.confirmFileMutations = true, this.confirmLocalCommands = true, this.confirmGitWrites = true, this.enableCodingVerificationFeedback = true, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) this.codingVerificationTriggerPolicy = CodingVerificationTriggerPolicy.onCompletionClaim, this.codingVerificationTimeoutSeconds = 90, this.codingVerificationMaxFailures = 5, this.enableAgentsMd = true, this.composerShortcutsEnabled = true, this.enablePrefixStableToolLoop = false, this.enableSemanticSearch = false, this.embeddingsModel = '', this.embeddingsEndpointId = '', this.showMemoryUpdates = false, this.enableLlmSessionLogs = isDebugBuild, this.enableAppLogFile = isDebugBuild, this.feedbackUploadEnabled = true, this.feedbackEndpointUrl = defaultFeedbackEndpointUrl, this.feedbackEndpointAuthToken = '', this.demoMode = false, this.onboardingCompleted = false, this.browserToolsEnabled = false,  List<String> disabledBuiltInTools = const <String>[],  List<LocalCommandPermissionRule> localCommandPermissionRules = const <LocalCommandPermissionRule>[],  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist = const <RoutineComputerUseActionAllowlistEntry>[], @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles = const <ModelCapabilityProfile>[], @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs = const <ModelHarnessConfig>[], @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions = const <ModelCapabilityProfileRevision>[], this.idleMaintenanceEnabled = false, this.idleMaintenanceWindowStartMinutes = 120, this.idleMaintenanceWindowEndMinutes = 360, this.idleMaintenanceMinIdleMinutes = 10, this.idleMaintenanceRequireAcPower = true}): _llmEndpoints = llmEndpoints,_mcpUrls = mcpUrls,_mcpServers = mcpServers,_externalToolHooks = externalToolHooks,_disabledBuiltInTools = disabledBuiltInTools,_localCommandPermissionRules = localCommandPermissionRules,_routineComputerUseActionAllowlist = routineComputerUseActionAllowlist,_modelCapabilityProfiles = modelCapabilityProfiles,_modelHarnessConfigs = modelHarnessConfigs,_modelCapabilityProfileRevisions = modelCapabilityProfileRevisions,super._();
  factory _AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);

@override@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) final  LlmProvider llmProvider;
@override final  String baseUrl;
@override final  String model;
@override final  String apiKey;
 final  List<LlmEndpoint> _llmEndpoints;
@override@JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson) List<LlmEndpoint> get llmEndpoints {
  if (_llmEndpoints is EqualUnmodifiableListView) return _llmEndpoints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_llmEndpoints);
}

@override@JsonKey() final  String activeLlmEndpointId;
@override final  double temperature;
@override final  int maxTokens;
@override@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) final  ReasoningEffortPreference reasoningEffort;
@override final  bool? enableThinking;
@override@JsonKey() final  bool proReasoningEnabled;
@override@JsonKey(unknownEnumValue: ProReasoningDepth.deep) final  ProReasoningDepth proReasoningDepth;
@override@JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh) final  ProReasoningCandidateRouting proReasoningCandidateRouting;
@override@JsonKey() final  String generalPrimaryModel;
@override@JsonKey() final  String codingPrimaryModel;
@override@JsonKey() final  String planPrimaryModel;
@override@JsonKey() final  String generalPrimaryEndpointId;
@override@JsonKey() final  String codingPrimaryEndpointId;
@override@JsonKey() final  String planPrimaryEndpointId;
@override@JsonKey() final  String memoryExtractionModel;
@override@JsonKey() final  String subagentModel;
@override@JsonKey() final  String goalSuggestionModel;
@override@JsonKey() final  String approvalAutoReviewModel;
@override@JsonKey() final  String planningModel;
@override@JsonKey() final  String proReasoningModel;
@override@JsonKey() final  String codeReviewModel;
@override@JsonKey() final  String logAnalysisModel;
@override@JsonKey() final  String memoryExtractionEndpointId;
@override@JsonKey() final  String subagentEndpointId;
@override@JsonKey() final  String goalSuggestionEndpointId;
@override@JsonKey() final  String approvalAutoReviewEndpointId;
@override@JsonKey() final  String planningEndpointId;
@override@JsonKey() final  String proReasoningEndpointId;
@override@JsonKey() final  String codeReviewEndpointId;
@override@JsonKey() final  String logAnalysisEndpointId;
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
@override@JsonKey() final  bool externalSettingsSyncEnabled;
@override@JsonKey() final  String externalSettingsPath;
@override@JsonKey() final  bool externalToolHooksEnabled;
 final  List<ExternalToolHook> _externalToolHooks;
@override@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> get externalToolHooks {
  if (_externalToolHooks is EqualUnmodifiableListView) return _externalToolHooks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_externalToolHooks);
}

@override@JsonKey() final  bool ttsEnabled;
@override@JsonKey() final  bool autoReadEnabled;
@override@JsonKey() final  double speechRate;
@override@JsonKey() final  bool voiceModeAutoStop;
@override@JsonKey() final  String whisperUrl;
@override@JsonKey() final  String voicevoxUrl;
@override@JsonKey() final  int voicevoxSpeakerId;
@override@JsonKey() final  String language;
@override@JsonKey(unknownEnumValue: AppThemePreference.dark) final  AppThemePreference themePreference;
@override@JsonKey(unknownEnumValue: AssistantMode.general) final  AssistantMode assistantMode;
@override@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) final  ToolApprovalMode codingApprovalMode;
@override@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) final  ToolApprovalMode chatApprovalMode;
@override@JsonKey() final  bool confirmFileMutations;
@override@JsonKey() final  bool confirmLocalCommands;
@override@JsonKey() final  bool confirmGitWrites;
@override@JsonKey() final  bool enableCodingVerificationFeedback;
@override@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) final  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy;
@override@JsonKey() final  int codingVerificationTimeoutSeconds;
@override@JsonKey() final  int codingVerificationMaxFailures;
@override@JsonKey() final  bool enableAgentsMd;
@override@JsonKey() final  bool composerShortcutsEnabled;
@override@JsonKey() final  bool enablePrefixStableToolLoop;
@override@JsonKey() final  bool enableSemanticSearch;
@override@JsonKey() final  String embeddingsModel;
@override@JsonKey() final  String embeddingsEndpointId;
@override@JsonKey() final  bool showMemoryUpdates;
@override@JsonKey() final  bool enableLlmSessionLogs;
@override@JsonKey() final  bool enableAppLogFile;
@override@JsonKey() final  bool feedbackUploadEnabled;
@override@JsonKey() final  String feedbackEndpointUrl;
@override@JsonKey() final  String feedbackEndpointAuthToken;
@override@JsonKey() final  bool demoMode;
@override@JsonKey() final  bool onboardingCompleted;
@override@JsonKey() final  bool browserToolsEnabled;
 final  List<String> _disabledBuiltInTools;
@override@JsonKey() List<String> get disabledBuiltInTools {
  if (_disabledBuiltInTools is EqualUnmodifiableListView) return _disabledBuiltInTools;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_disabledBuiltInTools);
}

 final  List<LocalCommandPermissionRule> _localCommandPermissionRules;
@override@JsonKey() List<LocalCommandPermissionRule> get localCommandPermissionRules {
  if (_localCommandPermissionRules is EqualUnmodifiableListView) return _localCommandPermissionRules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_localCommandPermissionRules);
}

 final  List<RoutineComputerUseActionAllowlistEntry> _routineComputerUseActionAllowlist;
@override@JsonKey() List<RoutineComputerUseActionAllowlistEntry> get routineComputerUseActionAllowlist {
  if (_routineComputerUseActionAllowlist is EqualUnmodifiableListView) return _routineComputerUseActionAllowlist;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_routineComputerUseActionAllowlist);
}

 final  List<ModelCapabilityProfile> _modelCapabilityProfiles;
@override@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> get modelCapabilityProfiles {
  if (_modelCapabilityProfiles is EqualUnmodifiableListView) return _modelCapabilityProfiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modelCapabilityProfiles);
}

 final  List<ModelHarnessConfig> _modelHarnessConfigs;
@override@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> get modelHarnessConfigs {
  if (_modelHarnessConfigs is EqualUnmodifiableListView) return _modelHarnessConfigs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modelHarnessConfigs);
}

 final  List<ModelCapabilityProfileRevision> _modelCapabilityProfileRevisions;
@override@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> get modelCapabilityProfileRevisions {
  if (_modelCapabilityProfileRevisions is EqualUnmodifiableListView) return _modelCapabilityProfileRevisions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modelCapabilityProfileRevisions);
}

@override@JsonKey() final  bool idleMaintenanceEnabled;
@override@JsonKey() final  int idleMaintenanceWindowStartMinutes;
@override@JsonKey() final  int idleMaintenanceWindowEndMinutes;
@override@JsonKey() final  int idleMaintenanceMinIdleMinutes;
@override@JsonKey() final  bool idleMaintenanceRequireAcPower;

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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.llmProvider, llmProvider) || other.llmProvider == llmProvider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&const DeepCollectionEquality().equals(other.llmEndpoints, _llmEndpoints)&&(identical(other.activeLlmEndpointId, activeLlmEndpointId) || other.activeLlmEndpointId == activeLlmEndpointId)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.reasoningEffort, reasoningEffort) || other.reasoningEffort == reasoningEffort)&&(identical(other.enableThinking, enableThinking) || other.enableThinking == enableThinking)&&(identical(other.proReasoningEnabled, proReasoningEnabled) || other.proReasoningEnabled == proReasoningEnabled)&&(identical(other.proReasoningDepth, proReasoningDepth) || other.proReasoningDepth == proReasoningDepth)&&(identical(other.proReasoningCandidateRouting, proReasoningCandidateRouting) || other.proReasoningCandidateRouting == proReasoningCandidateRouting)&&(identical(other.generalPrimaryModel, generalPrimaryModel) || other.generalPrimaryModel == generalPrimaryModel)&&(identical(other.codingPrimaryModel, codingPrimaryModel) || other.codingPrimaryModel == codingPrimaryModel)&&(identical(other.planPrimaryModel, planPrimaryModel) || other.planPrimaryModel == planPrimaryModel)&&(identical(other.generalPrimaryEndpointId, generalPrimaryEndpointId) || other.generalPrimaryEndpointId == generalPrimaryEndpointId)&&(identical(other.codingPrimaryEndpointId, codingPrimaryEndpointId) || other.codingPrimaryEndpointId == codingPrimaryEndpointId)&&(identical(other.planPrimaryEndpointId, planPrimaryEndpointId) || other.planPrimaryEndpointId == planPrimaryEndpointId)&&(identical(other.memoryExtractionModel, memoryExtractionModel) || other.memoryExtractionModel == memoryExtractionModel)&&(identical(other.subagentModel, subagentModel) || other.subagentModel == subagentModel)&&(identical(other.goalSuggestionModel, goalSuggestionModel) || other.goalSuggestionModel == goalSuggestionModel)&&(identical(other.approvalAutoReviewModel, approvalAutoReviewModel) || other.approvalAutoReviewModel == approvalAutoReviewModel)&&(identical(other.planningModel, planningModel) || other.planningModel == planningModel)&&(identical(other.proReasoningModel, proReasoningModel) || other.proReasoningModel == proReasoningModel)&&(identical(other.codeReviewModel, codeReviewModel) || other.codeReviewModel == codeReviewModel)&&(identical(other.logAnalysisModel, logAnalysisModel) || other.logAnalysisModel == logAnalysisModel)&&(identical(other.memoryExtractionEndpointId, memoryExtractionEndpointId) || other.memoryExtractionEndpointId == memoryExtractionEndpointId)&&(identical(other.subagentEndpointId, subagentEndpointId) || other.subagentEndpointId == subagentEndpointId)&&(identical(other.goalSuggestionEndpointId, goalSuggestionEndpointId) || other.goalSuggestionEndpointId == goalSuggestionEndpointId)&&(identical(other.approvalAutoReviewEndpointId, approvalAutoReviewEndpointId) || other.approvalAutoReviewEndpointId == approvalAutoReviewEndpointId)&&(identical(other.planningEndpointId, planningEndpointId) || other.planningEndpointId == planningEndpointId)&&(identical(other.proReasoningEndpointId, proReasoningEndpointId) || other.proReasoningEndpointId == proReasoningEndpointId)&&(identical(other.codeReviewEndpointId, codeReviewEndpointId) || other.codeReviewEndpointId == codeReviewEndpointId)&&(identical(other.logAnalysisEndpointId, logAnalysisEndpointId) || other.logAnalysisEndpointId == logAnalysisEndpointId)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other.mcpUrls, _mcpUrls)&&const DeepCollectionEquality().equals(other.mcpServers, _mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.externalSettingsSyncEnabled, externalSettingsSyncEnabled) || other.externalSettingsSyncEnabled == externalSettingsSyncEnabled)&&(identical(other.externalSettingsPath, externalSettingsPath) || other.externalSettingsPath == externalSettingsPath)&&(identical(other.externalToolHooksEnabled, externalToolHooksEnabled) || other.externalToolHooksEnabled == externalToolHooksEnabled)&&const DeepCollectionEquality().equals(other.externalToolHooks, _externalToolHooks)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.themePreference, themePreference) || other.themePreference == themePreference)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.codingApprovalMode, codingApprovalMode) || other.codingApprovalMode == codingApprovalMode)&&(identical(other.chatApprovalMode, chatApprovalMode) || other.chatApprovalMode == chatApprovalMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.enableCodingVerificationFeedback, enableCodingVerificationFeedback) || other.enableCodingVerificationFeedback == enableCodingVerificationFeedback)&&(identical(other.codingVerificationTriggerPolicy, codingVerificationTriggerPolicy) || other.codingVerificationTriggerPolicy == codingVerificationTriggerPolicy)&&(identical(other.codingVerificationTimeoutSeconds, codingVerificationTimeoutSeconds) || other.codingVerificationTimeoutSeconds == codingVerificationTimeoutSeconds)&&(identical(other.codingVerificationMaxFailures, codingVerificationMaxFailures) || other.codingVerificationMaxFailures == codingVerificationMaxFailures)&&(identical(other.enableAgentsMd, enableAgentsMd) || other.enableAgentsMd == enableAgentsMd)&&(identical(other.composerShortcutsEnabled, composerShortcutsEnabled) || other.composerShortcutsEnabled == composerShortcutsEnabled)&&(identical(other.enablePrefixStableToolLoop, enablePrefixStableToolLoop) || other.enablePrefixStableToolLoop == enablePrefixStableToolLoop)&&(identical(other.enableSemanticSearch, enableSemanticSearch) || other.enableSemanticSearch == enableSemanticSearch)&&(identical(other.embeddingsModel, embeddingsModel) || other.embeddingsModel == embeddingsModel)&&(identical(other.embeddingsEndpointId, embeddingsEndpointId) || other.embeddingsEndpointId == embeddingsEndpointId)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.enableLlmSessionLogs, enableLlmSessionLogs) || other.enableLlmSessionLogs == enableLlmSessionLogs)&&(identical(other.enableAppLogFile, enableAppLogFile) || other.enableAppLogFile == enableAppLogFile)&&(identical(other.feedbackUploadEnabled, feedbackUploadEnabled) || other.feedbackUploadEnabled == feedbackUploadEnabled)&&(identical(other.feedbackEndpointUrl, feedbackEndpointUrl) || other.feedbackEndpointUrl == feedbackEndpointUrl)&&(identical(other.feedbackEndpointAuthToken, feedbackEndpointAuthToken) || other.feedbackEndpointAuthToken == feedbackEndpointAuthToken)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&(identical(other.onboardingCompleted, onboardingCompleted) || other.onboardingCompleted == onboardingCompleted)&&(identical(other.browserToolsEnabled, browserToolsEnabled) || other.browserToolsEnabled == browserToolsEnabled)&&const DeepCollectionEquality().equals(other.disabledBuiltInTools, _disabledBuiltInTools)&&const DeepCollectionEquality().equals(other.localCommandPermissionRules, _localCommandPermissionRules)&&const DeepCollectionEquality().equals(other.routineComputerUseActionAllowlist, _routineComputerUseActionAllowlist)&&const DeepCollectionEquality().equals(other.modelCapabilityProfiles, _modelCapabilityProfiles)&&const DeepCollectionEquality().equals(other.modelHarnessConfigs, _modelHarnessConfigs)&&const DeepCollectionEquality().equals(other.modelCapabilityProfileRevisions, _modelCapabilityProfileRevisions)&&(identical(other.idleMaintenanceEnabled, idleMaintenanceEnabled) || other.idleMaintenanceEnabled == idleMaintenanceEnabled)&&(identical(other.idleMaintenanceWindowStartMinutes, idleMaintenanceWindowStartMinutes) || other.idleMaintenanceWindowStartMinutes == idleMaintenanceWindowStartMinutes)&&(identical(other.idleMaintenanceWindowEndMinutes, idleMaintenanceWindowEndMinutes) || other.idleMaintenanceWindowEndMinutes == idleMaintenanceWindowEndMinutes)&&(identical(other.idleMaintenanceMinIdleMinutes, idleMaintenanceMinIdleMinutes) || other.idleMaintenanceMinIdleMinutes == idleMaintenanceMinIdleMinutes)&&(identical(other.idleMaintenanceRequireAcPower, idleMaintenanceRequireAcPower) || other.idleMaintenanceRequireAcPower == idleMaintenanceRequireAcPower));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,llmProvider,baseUrl,model,apiKey,const DeepCollectionEquality().hash(_llmEndpoints),activeLlmEndpointId,temperature,maxTokens,reasoningEffort,enableThinking,proReasoningEnabled,proReasoningDepth,proReasoningCandidateRouting,generalPrimaryModel,codingPrimaryModel,planPrimaryModel,generalPrimaryEndpointId,codingPrimaryEndpointId,planPrimaryEndpointId,memoryExtractionModel,subagentModel,goalSuggestionModel,approvalAutoReviewModel,planningModel,proReasoningModel,codeReviewModel,logAnalysisModel,memoryExtractionEndpointId,subagentEndpointId,goalSuggestionEndpointId,approvalAutoReviewEndpointId,planningEndpointId,proReasoningEndpointId,codeReviewEndpointId,logAnalysisEndpointId,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(_mcpUrls),const DeepCollectionEquality().hash(_mcpServers),mcpEnabled,externalSettingsSyncEnabled,externalSettingsPath,externalToolHooksEnabled,const DeepCollectionEquality().hash(_externalToolHooks),ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,themePreference,assistantMode,codingApprovalMode,chatApprovalMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,enableCodingVerificationFeedback,codingVerificationTriggerPolicy,codingVerificationTimeoutSeconds,codingVerificationMaxFailures,enableAgentsMd,composerShortcutsEnabled,enablePrefixStableToolLoop,enableSemanticSearch,embeddingsModel,embeddingsEndpointId,showMemoryUpdates,enableLlmSessionLogs,enableAppLogFile,feedbackUploadEnabled,feedbackEndpointUrl,feedbackEndpointAuthToken,demoMode,onboardingCompleted,browserToolsEnabled,const DeepCollectionEquality().hash(_disabledBuiltInTools),const DeepCollectionEquality().hash(_localCommandPermissionRules),const DeepCollectionEquality().hash(_routineComputerUseActionAllowlist),const DeepCollectionEquality().hash(_modelCapabilityProfiles),const DeepCollectionEquality().hash(_modelHarnessConfigs),const DeepCollectionEquality().hash(_modelCapabilityProfileRevisions),idleMaintenanceEnabled,idleMaintenanceWindowStartMinutes,idleMaintenanceWindowEndMinutes,idleMaintenanceMinIdleMinutes,idleMaintenanceRequireAcPower]);
}

@override
String toString() {
    return 'AppSettings(llmProvider: $llmProvider, baseUrl: $baseUrl, model: $model, apiKey: $apiKey, llmEndpoints: $llmEndpoints, activeLlmEndpointId: $activeLlmEndpointId, temperature: $temperature, maxTokens: $maxTokens, reasoningEffort: $reasoningEffort, enableThinking: $enableThinking, proReasoningEnabled: $proReasoningEnabled, proReasoningDepth: $proReasoningDepth, proReasoningCandidateRouting: $proReasoningCandidateRouting, generalPrimaryModel: $generalPrimaryModel, codingPrimaryModel: $codingPrimaryModel, planPrimaryModel: $planPrimaryModel, generalPrimaryEndpointId: $generalPrimaryEndpointId, codingPrimaryEndpointId: $codingPrimaryEndpointId, planPrimaryEndpointId: $planPrimaryEndpointId, memoryExtractionModel: $memoryExtractionModel, subagentModel: $subagentModel, goalSuggestionModel: $goalSuggestionModel, approvalAutoReviewModel: $approvalAutoReviewModel, planningModel: $planningModel, proReasoningModel: $proReasoningModel, codeReviewModel: $codeReviewModel, logAnalysisModel: $logAnalysisModel, memoryExtractionEndpointId: $memoryExtractionEndpointId, subagentEndpointId: $subagentEndpointId, goalSuggestionEndpointId: $goalSuggestionEndpointId, approvalAutoReviewEndpointId: $approvalAutoReviewEndpointId, planningEndpointId: $planningEndpointId, proReasoningEndpointId: $proReasoningEndpointId, codeReviewEndpointId: $codeReviewEndpointId, logAnalysisEndpointId: $logAnalysisEndpointId, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, externalSettingsSyncEnabled: $externalSettingsSyncEnabled, externalSettingsPath: $externalSettingsPath, externalToolHooksEnabled: $externalToolHooksEnabled, externalToolHooks: $externalToolHooks, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, themePreference: $themePreference, assistantMode: $assistantMode, codingApprovalMode: $codingApprovalMode, chatApprovalMode: $chatApprovalMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, enableCodingVerificationFeedback: $enableCodingVerificationFeedback, codingVerificationTriggerPolicy: $codingVerificationTriggerPolicy, codingVerificationTimeoutSeconds: $codingVerificationTimeoutSeconds, codingVerificationMaxFailures: $codingVerificationMaxFailures, enableAgentsMd: $enableAgentsMd, composerShortcutsEnabled: $composerShortcutsEnabled, enablePrefixStableToolLoop: $enablePrefixStableToolLoop, enableSemanticSearch: $enableSemanticSearch, embeddingsModel: $embeddingsModel, embeddingsEndpointId: $embeddingsEndpointId, showMemoryUpdates: $showMemoryUpdates, enableLlmSessionLogs: $enableLlmSessionLogs, enableAppLogFile: $enableAppLogFile, feedbackUploadEnabled: $feedbackUploadEnabled, feedbackEndpointUrl: $feedbackEndpointUrl, feedbackEndpointAuthToken: $feedbackEndpointAuthToken, demoMode: $demoMode, onboardingCompleted: $onboardingCompleted, browserToolsEnabled: $browserToolsEnabled, disabledBuiltInTools: $disabledBuiltInTools, localCommandPermissionRules: $localCommandPermissionRules, routineComputerUseActionAllowlist: $routineComputerUseActionAllowlist, modelCapabilityProfiles: $modelCapabilityProfiles, modelHarnessConfigs: $modelHarnessConfigs, modelCapabilityProfileRevisions: $modelCapabilityProfileRevisions, idleMaintenanceEnabled: $idleMaintenanceEnabled, idleMaintenanceWindowStartMinutes: $idleMaintenanceWindowStartMinutes, idleMaintenanceWindowEndMinutes: $idleMaintenanceWindowEndMinutes, idleMaintenanceMinIdleMinutes: $idleMaintenanceMinIdleMinutes, idleMaintenanceRequireAcPower: $idleMaintenanceRequireAcPower)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider llmProvider, String baseUrl, String model, String apiKey,@JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson) List<LlmEndpoint> llmEndpoints, String activeLlmEndpointId, double temperature, int maxTokens,@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference reasoningEffort, bool? enableThinking, bool proReasoningEnabled,@JsonKey(unknownEnumValue: ProReasoningDepth.deep) ProReasoningDepth proReasoningDepth,@JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh) ProReasoningCandidateRouting proReasoningCandidateRouting, String generalPrimaryModel, String codingPrimaryModel, String planPrimaryModel, String generalPrimaryEndpointId, String codingPrimaryEndpointId, String planPrimaryEndpointId, String memoryExtractionModel, String subagentModel, String goalSuggestionModel, String approvalAutoReviewModel, String planningModel, String proReasoningModel, String codeReviewModel, String logAnalysisModel, String memoryExtractionEndpointId, String subagentEndpointId, String goalSuggestionEndpointId, String approvalAutoReviewEndpointId, String planningEndpointId, String proReasoningEndpointId, String codeReviewEndpointId, String logAnalysisEndpointId, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool externalSettingsSyncEnabled, String externalSettingsPath, bool externalToolHooksEnabled,@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> externalToolHooks, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AppThemePreference.dark) AppThemePreference themePreference,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode codingApprovalMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode chatApprovalMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool enableCodingVerificationFeedback,@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) CodingVerificationTriggerPolicy codingVerificationTriggerPolicy, int codingVerificationTimeoutSeconds, int codingVerificationMaxFailures, bool enableAgentsMd, bool composerShortcutsEnabled, bool enablePrefixStableToolLoop, bool enableSemanticSearch, String embeddingsModel, String embeddingsEndpointId, bool showMemoryUpdates, bool enableLlmSessionLogs, bool enableAppLogFile, bool feedbackUploadEnabled, String feedbackEndpointUrl, String feedbackEndpointAuthToken, bool demoMode, bool onboardingCompleted, bool browserToolsEnabled, List<String> disabledBuiltInTools, List<LocalCommandPermissionRule> localCommandPermissionRules, List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist,@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> modelCapabilityProfiles,@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> modelHarnessConfigs,@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions, bool idleMaintenanceEnabled, int idleMaintenanceWindowStartMinutes, int idleMaintenanceWindowEndMinutes, int idleMaintenanceMinIdleMinutes, bool idleMaintenanceRequireAcPower
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
@override @pragma('vm:prefer-inline') $Res call({Object? llmProvider = null,Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? llmEndpoints = null,Object? activeLlmEndpointId = null,Object? temperature = null,Object? maxTokens = null,Object? reasoningEffort = null,Object? enableThinking = freezed,Object? proReasoningEnabled = null,Object? proReasoningDepth = null,Object? proReasoningCandidateRouting = null,Object? generalPrimaryModel = null,Object? codingPrimaryModel = null,Object? planPrimaryModel = null,Object? generalPrimaryEndpointId = null,Object? codingPrimaryEndpointId = null,Object? planPrimaryEndpointId = null,Object? memoryExtractionModel = null,Object? subagentModel = null,Object? goalSuggestionModel = null,Object? approvalAutoReviewModel = null,Object? planningModel = null,Object? proReasoningModel = null,Object? codeReviewModel = null,Object? logAnalysisModel = null,Object? memoryExtractionEndpointId = null,Object? subagentEndpointId = null,Object? goalSuggestionEndpointId = null,Object? approvalAutoReviewEndpointId = null,Object? planningEndpointId = null,Object? proReasoningEndpointId = null,Object? codeReviewEndpointId = null,Object? logAnalysisEndpointId = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? externalSettingsSyncEnabled = null,Object? externalSettingsPath = null,Object? externalToolHooksEnabled = null,Object? externalToolHooks = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? themePreference = null,Object? assistantMode = null,Object? codingApprovalMode = null,Object? chatApprovalMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? enableCodingVerificationFeedback = null,Object? codingVerificationTriggerPolicy = null,Object? codingVerificationTimeoutSeconds = null,Object? codingVerificationMaxFailures = null,Object? enableAgentsMd = null,Object? composerShortcutsEnabled = null,Object? enablePrefixStableToolLoop = null,Object? enableSemanticSearch = null,Object? embeddingsModel = null,Object? embeddingsEndpointId = null,Object? showMemoryUpdates = null,Object? enableLlmSessionLogs = null,Object? enableAppLogFile = null,Object? feedbackUploadEnabled = null,Object? feedbackEndpointUrl = null,Object? feedbackEndpointAuthToken = null,Object? demoMode = null,Object? onboardingCompleted = null,Object? browserToolsEnabled = null,Object? disabledBuiltInTools = null,Object? localCommandPermissionRules = null,Object? routineComputerUseActionAllowlist = null,Object? modelCapabilityProfiles = null,Object? modelHarnessConfigs = null,Object? modelCapabilityProfileRevisions = null,Object? idleMaintenanceEnabled = null,Object? idleMaintenanceWindowStartMinutes = null,Object? idleMaintenanceWindowEndMinutes = null,Object? idleMaintenanceMinIdleMinutes = null,Object? idleMaintenanceRequireAcPower = null,}) {
  return _then(_AppSettings(
llmProvider: null == llmProvider ? _self.llmProvider : llmProvider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,llmEndpoints: null == llmEndpoints ? _self._llmEndpoints : llmEndpoints // ignore: cast_nullable_to_non_nullable
as List<LlmEndpoint>,activeLlmEndpointId: null == activeLlmEndpointId ? _self.activeLlmEndpointId : activeLlmEndpointId // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningEffort: null == reasoningEffort ? _self.reasoningEffort : reasoningEffort // ignore: cast_nullable_to_non_nullable
as ReasoningEffortPreference,enableThinking: freezed == enableThinking ? _self.enableThinking : enableThinking // ignore: cast_nullable_to_non_nullable
as bool?,proReasoningEnabled: null == proReasoningEnabled ? _self.proReasoningEnabled : proReasoningEnabled // ignore: cast_nullable_to_non_nullable
as bool,proReasoningDepth: null == proReasoningDepth ? _self.proReasoningDepth : proReasoningDepth // ignore: cast_nullable_to_non_nullable
as ProReasoningDepth,proReasoningCandidateRouting: null == proReasoningCandidateRouting ? _self.proReasoningCandidateRouting : proReasoningCandidateRouting // ignore: cast_nullable_to_non_nullable
as ProReasoningCandidateRouting,generalPrimaryModel: null == generalPrimaryModel ? _self.generalPrimaryModel : generalPrimaryModel // ignore: cast_nullable_to_non_nullable
as String,codingPrimaryModel: null == codingPrimaryModel ? _self.codingPrimaryModel : codingPrimaryModel // ignore: cast_nullable_to_non_nullable
as String,planPrimaryModel: null == planPrimaryModel ? _self.planPrimaryModel : planPrimaryModel // ignore: cast_nullable_to_non_nullable
as String,generalPrimaryEndpointId: null == generalPrimaryEndpointId ? _self.generalPrimaryEndpointId : generalPrimaryEndpointId // ignore: cast_nullable_to_non_nullable
as String,codingPrimaryEndpointId: null == codingPrimaryEndpointId ? _self.codingPrimaryEndpointId : codingPrimaryEndpointId // ignore: cast_nullable_to_non_nullable
as String,planPrimaryEndpointId: null == planPrimaryEndpointId ? _self.planPrimaryEndpointId : planPrimaryEndpointId // ignore: cast_nullable_to_non_nullable
as String,memoryExtractionModel: null == memoryExtractionModel ? _self.memoryExtractionModel : memoryExtractionModel // ignore: cast_nullable_to_non_nullable
as String,subagentModel: null == subagentModel ? _self.subagentModel : subagentModel // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionModel: null == goalSuggestionModel ? _self.goalSuggestionModel : goalSuggestionModel // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewModel: null == approvalAutoReviewModel ? _self.approvalAutoReviewModel : approvalAutoReviewModel // ignore: cast_nullable_to_non_nullable
as String,planningModel: null == planningModel ? _self.planningModel : planningModel // ignore: cast_nullable_to_non_nullable
as String,proReasoningModel: null == proReasoningModel ? _self.proReasoningModel : proReasoningModel // ignore: cast_nullable_to_non_nullable
as String,codeReviewModel: null == codeReviewModel ? _self.codeReviewModel : codeReviewModel // ignore: cast_nullable_to_non_nullable
as String,logAnalysisModel: null == logAnalysisModel ? _self.logAnalysisModel : logAnalysisModel // ignore: cast_nullable_to_non_nullable
as String,memoryExtractionEndpointId: null == memoryExtractionEndpointId ? _self.memoryExtractionEndpointId : memoryExtractionEndpointId // ignore: cast_nullable_to_non_nullable
as String,subagentEndpointId: null == subagentEndpointId ? _self.subagentEndpointId : subagentEndpointId // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionEndpointId: null == goalSuggestionEndpointId ? _self.goalSuggestionEndpointId : goalSuggestionEndpointId // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewEndpointId: null == approvalAutoReviewEndpointId ? _self.approvalAutoReviewEndpointId : approvalAutoReviewEndpointId // ignore: cast_nullable_to_non_nullable
as String,planningEndpointId: null == planningEndpointId ? _self.planningEndpointId : planningEndpointId // ignore: cast_nullable_to_non_nullable
as String,proReasoningEndpointId: null == proReasoningEndpointId ? _self.proReasoningEndpointId : proReasoningEndpointId // ignore: cast_nullable_to_non_nullable
as String,codeReviewEndpointId: null == codeReviewEndpointId ? _self.codeReviewEndpointId : codeReviewEndpointId // ignore: cast_nullable_to_non_nullable
as String,logAnalysisEndpointId: null == logAnalysisEndpointId ? _self.logAnalysisEndpointId : logAnalysisEndpointId // ignore: cast_nullable_to_non_nullable
as String,googleChatWebhookUrl: null == googleChatWebhookUrl ? _self.googleChatWebhookUrl : googleChatWebhookUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrl: null == mcpUrl ? _self.mcpUrl : mcpUrl // ignore: cast_nullable_to_non_nullable
as String,mcpUrls: null == mcpUrls ? _self._mcpUrls : mcpUrls // ignore: cast_nullable_to_non_nullable
as List<String>,mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServerConfig>,mcpEnabled: null == mcpEnabled ? _self.mcpEnabled : mcpEnabled // ignore: cast_nullable_to_non_nullable
as bool,externalSettingsSyncEnabled: null == externalSettingsSyncEnabled ? _self.externalSettingsSyncEnabled : externalSettingsSyncEnabled // ignore: cast_nullable_to_non_nullable
as bool,externalSettingsPath: null == externalSettingsPath ? _self.externalSettingsPath : externalSettingsPath // ignore: cast_nullable_to_non_nullable
as String,externalToolHooksEnabled: null == externalToolHooksEnabled ? _self.externalToolHooksEnabled : externalToolHooksEnabled // ignore: cast_nullable_to_non_nullable
as bool,externalToolHooks: null == externalToolHooks ? _self._externalToolHooks : externalToolHooks // ignore: cast_nullable_to_non_nullable
as List<ExternalToolHook>,ttsEnabled: null == ttsEnabled ? _self.ttsEnabled : ttsEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoReadEnabled: null == autoReadEnabled ? _self.autoReadEnabled : autoReadEnabled // ignore: cast_nullable_to_non_nullable
as bool,speechRate: null == speechRate ? _self.speechRate : speechRate // ignore: cast_nullable_to_non_nullable
as double,voiceModeAutoStop: null == voiceModeAutoStop ? _self.voiceModeAutoStop : voiceModeAutoStop // ignore: cast_nullable_to_non_nullable
as bool,whisperUrl: null == whisperUrl ? _self.whisperUrl : whisperUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxUrl: null == voicevoxUrl ? _self.voicevoxUrl : voicevoxUrl // ignore: cast_nullable_to_non_nullable
as String,voicevoxSpeakerId: null == voicevoxSpeakerId ? _self.voicevoxSpeakerId : voicevoxSpeakerId // ignore: cast_nullable_to_non_nullable
as int,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,themePreference: null == themePreference ? _self.themePreference : themePreference // ignore: cast_nullable_to_non_nullable
as AppThemePreference,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
as AssistantMode,codingApprovalMode: null == codingApprovalMode ? _self.codingApprovalMode : codingApprovalMode // ignore: cast_nullable_to_non_nullable
as ToolApprovalMode,chatApprovalMode: null == chatApprovalMode ? _self.chatApprovalMode : chatApprovalMode // ignore: cast_nullable_to_non_nullable
as ToolApprovalMode,confirmFileMutations: null == confirmFileMutations ? _self.confirmFileMutations : confirmFileMutations // ignore: cast_nullable_to_non_nullable
as bool,confirmLocalCommands: null == confirmLocalCommands ? _self.confirmLocalCommands : confirmLocalCommands // ignore: cast_nullable_to_non_nullable
as bool,confirmGitWrites: null == confirmGitWrites ? _self.confirmGitWrites : confirmGitWrites // ignore: cast_nullable_to_non_nullable
as bool,enableCodingVerificationFeedback: null == enableCodingVerificationFeedback ? _self.enableCodingVerificationFeedback : enableCodingVerificationFeedback // ignore: cast_nullable_to_non_nullable
as bool,codingVerificationTriggerPolicy: null == codingVerificationTriggerPolicy ? _self.codingVerificationTriggerPolicy : codingVerificationTriggerPolicy // ignore: cast_nullable_to_non_nullable
as CodingVerificationTriggerPolicy,codingVerificationTimeoutSeconds: null == codingVerificationTimeoutSeconds ? _self.codingVerificationTimeoutSeconds : codingVerificationTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,codingVerificationMaxFailures: null == codingVerificationMaxFailures ? _self.codingVerificationMaxFailures : codingVerificationMaxFailures // ignore: cast_nullable_to_non_nullable
as int,enableAgentsMd: null == enableAgentsMd ? _self.enableAgentsMd : enableAgentsMd // ignore: cast_nullable_to_non_nullable
as bool,composerShortcutsEnabled: null == composerShortcutsEnabled ? _self.composerShortcutsEnabled : composerShortcutsEnabled // ignore: cast_nullable_to_non_nullable
as bool,enablePrefixStableToolLoop: null == enablePrefixStableToolLoop ? _self.enablePrefixStableToolLoop : enablePrefixStableToolLoop // ignore: cast_nullable_to_non_nullable
as bool,enableSemanticSearch: null == enableSemanticSearch ? _self.enableSemanticSearch : enableSemanticSearch // ignore: cast_nullable_to_non_nullable
as bool,embeddingsModel: null == embeddingsModel ? _self.embeddingsModel : embeddingsModel // ignore: cast_nullable_to_non_nullable
as String,embeddingsEndpointId: null == embeddingsEndpointId ? _self.embeddingsEndpointId : embeddingsEndpointId // ignore: cast_nullable_to_non_nullable
as String,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,enableLlmSessionLogs: null == enableLlmSessionLogs ? _self.enableLlmSessionLogs : enableLlmSessionLogs // ignore: cast_nullable_to_non_nullable
as bool,enableAppLogFile: null == enableAppLogFile ? _self.enableAppLogFile : enableAppLogFile // ignore: cast_nullable_to_non_nullable
as bool,feedbackUploadEnabled: null == feedbackUploadEnabled ? _self.feedbackUploadEnabled : feedbackUploadEnabled // ignore: cast_nullable_to_non_nullable
as bool,feedbackEndpointUrl: null == feedbackEndpointUrl ? _self.feedbackEndpointUrl : feedbackEndpointUrl // ignore: cast_nullable_to_non_nullable
as String,feedbackEndpointAuthToken: null == feedbackEndpointAuthToken ? _self.feedbackEndpointAuthToken : feedbackEndpointAuthToken // ignore: cast_nullable_to_non_nullable
as String,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,onboardingCompleted: null == onboardingCompleted ? _self.onboardingCompleted : onboardingCompleted // ignore: cast_nullable_to_non_nullable
as bool,browserToolsEnabled: null == browserToolsEnabled ? _self.browserToolsEnabled : browserToolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self._disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,localCommandPermissionRules: null == localCommandPermissionRules ? _self._localCommandPermissionRules : localCommandPermissionRules // ignore: cast_nullable_to_non_nullable
as List<LocalCommandPermissionRule>,routineComputerUseActionAllowlist: null == routineComputerUseActionAllowlist ? _self._routineComputerUseActionAllowlist : routineComputerUseActionAllowlist // ignore: cast_nullable_to_non_nullable
as List<RoutineComputerUseActionAllowlistEntry>,modelCapabilityProfiles: null == modelCapabilityProfiles ? _self._modelCapabilityProfiles : modelCapabilityProfiles // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfile>,modelHarnessConfigs: null == modelHarnessConfigs ? _self._modelHarnessConfigs : modelHarnessConfigs // ignore: cast_nullable_to_non_nullable
as List<ModelHarnessConfig>,modelCapabilityProfileRevisions: null == modelCapabilityProfileRevisions ? _self._modelCapabilityProfileRevisions : modelCapabilityProfileRevisions // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfileRevision>,idleMaintenanceEnabled: null == idleMaintenanceEnabled ? _self.idleMaintenanceEnabled : idleMaintenanceEnabled // ignore: cast_nullable_to_non_nullable
as bool,idleMaintenanceWindowStartMinutes: null == idleMaintenanceWindowStartMinutes ? _self.idleMaintenanceWindowStartMinutes : idleMaintenanceWindowStartMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceWindowEndMinutes: null == idleMaintenanceWindowEndMinutes ? _self.idleMaintenanceWindowEndMinutes : idleMaintenanceWindowEndMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceMinIdleMinutes: null == idleMaintenanceMinIdleMinutes ? _self.idleMaintenanceMinIdleMinutes : idleMaintenanceMinIdleMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceRequireAcPower: null == idleMaintenanceRequireAcPower ? _self.idleMaintenanceRequireAcPower : idleMaintenanceRequireAcPower // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
