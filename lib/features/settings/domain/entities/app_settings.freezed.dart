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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalCommandPermissionRule&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.action, action) || other.action == action)&&(identical(other.match, match) || other.match == match)&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,enabled,action,match,pattern,workingDirectory,createdAt);

@override
String toString() {
  return 'LocalCommandPermissionRule(id: $id, enabled: $enabled, action: $action, match: $match, pattern: $pattern, workingDirectory: $workingDirectory, createdAt: $createdAt)';
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
  return _then(_self.copyWith(
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
int get hashCode => Object.hash(runtimeType,id,enabled,action,match,pattern,workingDirectory,createdAt);

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineComputerUseActionAllowlistEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.label, label) || other.label == label)&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.targetLabelContains, targetLabelContains) || other.targetLabelContains == targetLabelContains)&&(identical(other.targetRole, targetRole) || other.targetRole == targetRole)&&(identical(other.targetAction, targetAction) || other.targetAction == targetAction)&&(identical(other.targetRisk, targetRisk) || other.targetRisk == targetRisk)&&(identical(other.appNameContains, appNameContains) || other.appNameContains == appNameContains)&&(identical(other.appBundleId, appBundleId) || other.appBundleId == appBundleId)&&(identical(other.windowTitleContains, windowTitleContains) || other.windowTitleContains == windowTitleContains)&&(identical(other.urlHost, urlHost) || other.urlHost == urlHost)&&(identical(other.urlStartsWith, urlStartsWith) || other.urlStartsWith == urlStartsWith)&&(identical(other.exactText, exactText) || other.exactText == exactText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,enabled,label,toolName,targetLabelContains,targetRole,targetAction,targetRisk,appNameContains,appBundleId,windowTitleContains,urlHost,urlStartsWith,exactText);

@override
String toString() {
  return 'RoutineComputerUseActionAllowlistEntry(id: $id, enabled: $enabled, label: $label, toolName: $toolName, targetLabelContains: $targetLabelContains, targetRole: $targetRole, targetAction: $targetAction, targetRisk: $targetRisk, appNameContains: $appNameContains, appBundleId: $appBundleId, windowTitleContains: $windowTitleContains, urlHost: $urlHost, urlStartsWith: $urlStartsWith, exactText: $exactText)';
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
  return _then(_self.copyWith(
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
int get hashCode => Object.hash(runtimeType,id,enabled,label,toolName,targetLabelContains,targetRole,targetAction,targetRisk,appNameContains,appBundleId,windowTitleContains,urlHost,urlStartsWith,exactText);

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

 String get baseUrl; String get model; String get apiKey; double get temperature; int get maxTokens;@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference get reasoningEffort; String get googleChatWebhookUrl; String get mcpUrl; List<String> get mcpUrls; List<McpServerConfig> get mcpServers; bool get mcpEnabled;// Voice settings
 bool get ttsEnabled; bool get autoReadEnabled; double get speechRate;// Voice mode (Whisper + VOICEVOX)
 bool get voiceModeAutoStop; String get whisperUrl; String get voicevoxUrl; int get voicevoxSpeakerId; String get language;@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode get assistantMode;@JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions) CodingApprovalMode get codingApprovalMode; bool get confirmFileMutations; bool get confirmLocalCommands; bool get confirmGitWrites; bool get showMemoryUpdates; bool get enableLlmSessionLogs; bool get demoMode; List<String> get disabledBuiltInTools; List<LocalCommandPermissionRule> get localCommandPermissionRules; List<RoutineComputerUseActionAllowlistEntry> get routineComputerUseActionAllowlist;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.reasoningEffort, reasoningEffort) || other.reasoningEffort == reasoningEffort)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other.mcpUrls, mcpUrls)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.codingApprovalMode, codingApprovalMode) || other.codingApprovalMode == codingApprovalMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.enableLlmSessionLogs, enableLlmSessionLogs) || other.enableLlmSessionLogs == enableLlmSessionLogs)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&const DeepCollectionEquality().equals(other.disabledBuiltInTools, disabledBuiltInTools)&&const DeepCollectionEquality().equals(other.localCommandPermissionRules, localCommandPermissionRules)&&const DeepCollectionEquality().equals(other.routineComputerUseActionAllowlist, routineComputerUseActionAllowlist));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,baseUrl,model,apiKey,temperature,maxTokens,reasoningEffort,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(mcpUrls),const DeepCollectionEquality().hash(mcpServers),mcpEnabled,ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,codingApprovalMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,showMemoryUpdates,enableLlmSessionLogs,demoMode,const DeepCollectionEquality().hash(disabledBuiltInTools),const DeepCollectionEquality().hash(localCommandPermissionRules),const DeepCollectionEquality().hash(routineComputerUseActionAllowlist)]);

@override
String toString() {
  return 'AppSettings(baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, reasoningEffort: $reasoningEffort, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, codingApprovalMode: $codingApprovalMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, showMemoryUpdates: $showMemoryUpdates, enableLlmSessionLogs: $enableLlmSessionLogs, demoMode: $demoMode, disabledBuiltInTools: $disabledBuiltInTools, localCommandPermissionRules: $localCommandPermissionRules, routineComputerUseActionAllowlist: $routineComputerUseActionAllowlist)';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
 String baseUrl, String model, String apiKey, double temperature, int maxTokens,@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference reasoningEffort, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode,@JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions) CodingApprovalMode codingApprovalMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool showMemoryUpdates, bool enableLlmSessionLogs, bool demoMode, List<String> disabledBuiltInTools, List<LocalCommandPermissionRule> localCommandPermissionRules, List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist
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
@pragma('vm:prefer-inline') @override $Res call({Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? reasoningEffort = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? codingApprovalMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? showMemoryUpdates = null,Object? enableLlmSessionLogs = null,Object? demoMode = null,Object? disabledBuiltInTools = null,Object? localCommandPermissionRules = null,Object? routineComputerUseActionAllowlist = null,}) {
  return _then(_self.copyWith(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningEffort: null == reasoningEffort ? _self.reasoningEffort : reasoningEffort // ignore: cast_nullable_to_non_nullable
as ReasoningEffortPreference,googleChatWebhookUrl: null == googleChatWebhookUrl ? _self.googleChatWebhookUrl : googleChatWebhookUrl // ignore: cast_nullable_to_non_nullable
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
as AssistantMode,codingApprovalMode: null == codingApprovalMode ? _self.codingApprovalMode : codingApprovalMode // ignore: cast_nullable_to_non_nullable
as CodingApprovalMode,confirmFileMutations: null == confirmFileMutations ? _self.confirmFileMutations : confirmFileMutations // ignore: cast_nullable_to_non_nullable
as bool,confirmLocalCommands: null == confirmLocalCommands ? _self.confirmLocalCommands : confirmLocalCommands // ignore: cast_nullable_to_non_nullable
as bool,confirmGitWrites: null == confirmGitWrites ? _self.confirmGitWrites : confirmGitWrites // ignore: cast_nullable_to_non_nullable
as bool,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,enableLlmSessionLogs: null == enableLlmSessionLogs ? _self.enableLlmSessionLogs : enableLlmSessionLogs // ignore: cast_nullable_to_non_nullable
as bool,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self.disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,localCommandPermissionRules: null == localCommandPermissionRules ? _self.localCommandPermissionRules : localCommandPermissionRules // ignore: cast_nullable_to_non_nullable
as List<LocalCommandPermissionRule>,routineComputerUseActionAllowlist: null == routineComputerUseActionAllowlist ? _self.routineComputerUseActionAllowlist : routineComputerUseActionAllowlist // ignore: cast_nullable_to_non_nullable
as List<RoutineComputerUseActionAllowlistEntry>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions)  CodingApprovalMode codingApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool demoMode,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.codingApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.demoMode,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions)  CodingApprovalMode codingApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool demoMode,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.codingApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.demoMode,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions)  CodingApprovalMode codingApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool demoMode,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.codingApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.demoMode,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppSettings extends AppSettings {
  const _AppSettings({required this.baseUrl, required this.model, required this.apiKey, required this.temperature, required this.maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) this.reasoningEffort = ReasoningEffortPreference.automatic, this.googleChatWebhookUrl = '', this.mcpUrl = '', final  List<String> mcpUrls = const <String>[], final  List<McpServerConfig> mcpServers = const <McpServerConfig>[], this.mcpEnabled = false, this.ttsEnabled = true, this.autoReadEnabled = false, this.speechRate = 0.5, this.voiceModeAutoStop = true, this.whisperUrl = 'http://localhost:8080', this.voicevoxUrl = 'http://localhost:50021', this.voicevoxSpeakerId = 0, this.language = 'system', @JsonKey(unknownEnumValue: AssistantMode.general) this.assistantMode = AssistantMode.general, @JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions) this.codingApprovalMode = CodingApprovalMode.defaultPermissions, this.confirmFileMutations = true, this.confirmLocalCommands = true, this.confirmGitWrites = true, this.showMemoryUpdates = false, this.enableLlmSessionLogs = false, this.demoMode = false, final  List<String> disabledBuiltInTools = const <String>[], final  List<LocalCommandPermissionRule> localCommandPermissionRules = const <LocalCommandPermissionRule>[], final  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist = const <RoutineComputerUseActionAllowlistEntry>[]}): _mcpUrls = mcpUrls,_mcpServers = mcpServers,_disabledBuiltInTools = disabledBuiltInTools,_localCommandPermissionRules = localCommandPermissionRules,_routineComputerUseActionAllowlist = routineComputerUseActionAllowlist,super._();
  factory _AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);

@override final  String baseUrl;
@override final  String model;
@override final  String apiKey;
@override final  double temperature;
@override final  int maxTokens;
@override@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) final  ReasoningEffortPreference reasoningEffort;
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
@override@JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions) final  CodingApprovalMode codingApprovalMode;
@override@JsonKey() final  bool confirmFileMutations;
@override@JsonKey() final  bool confirmLocalCommands;
@override@JsonKey() final  bool confirmGitWrites;
@override@JsonKey() final  bool showMemoryUpdates;
@override@JsonKey() final  bool enableLlmSessionLogs;
@override@JsonKey() final  bool demoMode;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.reasoningEffort, reasoningEffort) || other.reasoningEffort == reasoningEffort)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other._mcpUrls, _mcpUrls)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.codingApprovalMode, codingApprovalMode) || other.codingApprovalMode == codingApprovalMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.enableLlmSessionLogs, enableLlmSessionLogs) || other.enableLlmSessionLogs == enableLlmSessionLogs)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&const DeepCollectionEquality().equals(other._disabledBuiltInTools, _disabledBuiltInTools)&&const DeepCollectionEquality().equals(other._localCommandPermissionRules, _localCommandPermissionRules)&&const DeepCollectionEquality().equals(other._routineComputerUseActionAllowlist, _routineComputerUseActionAllowlist));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,baseUrl,model,apiKey,temperature,maxTokens,reasoningEffort,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(_mcpUrls),const DeepCollectionEquality().hash(_mcpServers),mcpEnabled,ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,codingApprovalMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,showMemoryUpdates,enableLlmSessionLogs,demoMode,const DeepCollectionEquality().hash(_disabledBuiltInTools),const DeepCollectionEquality().hash(_localCommandPermissionRules),const DeepCollectionEquality().hash(_routineComputerUseActionAllowlist)]);

@override
String toString() {
  return 'AppSettings(baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, reasoningEffort: $reasoningEffort, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, codingApprovalMode: $codingApprovalMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, showMemoryUpdates: $showMemoryUpdates, enableLlmSessionLogs: $enableLlmSessionLogs, demoMode: $demoMode, disabledBuiltInTools: $disabledBuiltInTools, localCommandPermissionRules: $localCommandPermissionRules, routineComputerUseActionAllowlist: $routineComputerUseActionAllowlist)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
 String baseUrl, String model, String apiKey, double temperature, int maxTokens,@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference reasoningEffort, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode,@JsonKey(unknownEnumValue: CodingApprovalMode.defaultPermissions) CodingApprovalMode codingApprovalMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool showMemoryUpdates, bool enableLlmSessionLogs, bool demoMode, List<String> disabledBuiltInTools, List<LocalCommandPermissionRule> localCommandPermissionRules, List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist
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
@override @pragma('vm:prefer-inline') $Res call({Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? reasoningEffort = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? codingApprovalMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? showMemoryUpdates = null,Object? enableLlmSessionLogs = null,Object? demoMode = null,Object? disabledBuiltInTools = null,Object? localCommandPermissionRules = null,Object? routineComputerUseActionAllowlist = null,}) {
  return _then(_AppSettings(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningEffort: null == reasoningEffort ? _self.reasoningEffort : reasoningEffort // ignore: cast_nullable_to_non_nullable
as ReasoningEffortPreference,googleChatWebhookUrl: null == googleChatWebhookUrl ? _self.googleChatWebhookUrl : googleChatWebhookUrl // ignore: cast_nullable_to_non_nullable
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
as AssistantMode,codingApprovalMode: null == codingApprovalMode ? _self.codingApprovalMode : codingApprovalMode // ignore: cast_nullable_to_non_nullable
as CodingApprovalMode,confirmFileMutations: null == confirmFileMutations ? _self.confirmFileMutations : confirmFileMutations // ignore: cast_nullable_to_non_nullable
as bool,confirmLocalCommands: null == confirmLocalCommands ? _self.confirmLocalCommands : confirmLocalCommands // ignore: cast_nullable_to_non_nullable
as bool,confirmGitWrites: null == confirmGitWrites ? _self.confirmGitWrites : confirmGitWrites // ignore: cast_nullable_to_non_nullable
as bool,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,enableLlmSessionLogs: null == enableLlmSessionLogs ? _self.enableLlmSessionLogs : enableLlmSessionLogs // ignore: cast_nullable_to_non_nullable
as bool,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self._disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,localCommandPermissionRules: null == localCommandPermissionRules ? _self._localCommandPermissionRules : localCommandPermissionRules // ignore: cast_nullable_to_non_nullable
as List<LocalCommandPermissionRule>,routineComputerUseActionAllowlist: null == routineComputerUseActionAllowlist ? _self._routineComputerUseActionAllowlist : routineComputerUseActionAllowlist // ignore: cast_nullable_to_non_nullable
as List<RoutineComputerUseActionAllowlistEntry>,
  ));
}


}

// dart format on
