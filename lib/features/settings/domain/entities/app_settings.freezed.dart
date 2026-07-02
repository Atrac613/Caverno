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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.type, type) || other.type == type)&&(identical(other.trustState, trustState) || other.trustState == trustState)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, args)&&const DeepCollectionEquality().equals(other.env, env)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.trustedAt, trustedAt) || other.trustedAt == trustedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,enabled,type,trustState,command,const DeepCollectionEquality().hash(args),const DeepCollectionEquality().hash(env),sourceId,trustedAt);

@override
String toString() {
  return 'McpServerConfig(url: $url, enabled: $enabled, type: $type, trustState: $trustState, command: $command, args: $args, env: $env, sourceId: $sourceId, trustedAt: $trustedAt)';
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
  return _then(_self.copyWith(
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
  const _McpServerConfig({this.url = '', this.enabled = true, @JsonKey(unknownEnumValue: McpServerType.http) this.type = McpServerType.http, @JsonKey(unknownEnumValue: McpServerTrustState.trusted) this.trustState = McpServerTrustState.trusted, this.command = '', final  List<String> args = const <String>[], final  Map<String, String> env = const <String, String>{}, this.sourceId = '', this.trustedAt}): _args = args,_env = env,super._();
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpServerConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.type, type) || other.type == type)&&(identical(other.trustState, trustState) || other.trustState == trustState)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&const DeepCollectionEquality().equals(other._env, _env)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.trustedAt, trustedAt) || other.trustedAt == trustedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,enabled,type,trustState,command,const DeepCollectionEquality().hash(_args),const DeepCollectionEquality().hash(_env),sourceId,trustedAt);

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

 String get id; bool get enabled; String get event; String get command; List<String> get args; Map<String, String> get env; String get sourceId;
/// Create a copy of ExternalToolHook
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExternalToolHookCopyWith<ExternalToolHook> get copyWith => _$ExternalToolHookCopyWithImpl<ExternalToolHook>(this as ExternalToolHook, _$identity);

  /// Serializes this ExternalToolHook to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExternalToolHook&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.event, event) || other.event == event)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, args)&&const DeepCollectionEquality().equals(other.env, env)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,enabled,event,command,const DeepCollectionEquality().hash(args),const DeepCollectionEquality().hash(env),sourceId);

@override
String toString() {
  return 'ExternalToolHook(id: $id, enabled: $enabled, event: $event, command: $command, args: $args, env: $env, sourceId: $sourceId)';
}


}

/// @nodoc
abstract mixin class $ExternalToolHookCopyWith<$Res>  {
  factory $ExternalToolHookCopyWith(ExternalToolHook value, $Res Function(ExternalToolHook) _then) = _$ExternalToolHookCopyWithImpl;
@useResult
$Res call({
 String id, bool enabled, String event, String command, List<String> args, Map<String, String> env, String sourceId
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? enabled = null,Object? event = null,Object? command = null,Object? args = null,Object? env = null,Object? sourceId = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  bool enabled,  String event,  String command,  List<String> args,  Map<String, String> env,  String sourceId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExternalToolHook() when $default != null:
return $default(_that.id,_that.enabled,_that.event,_that.command,_that.args,_that.env,_that.sourceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  bool enabled,  String event,  String command,  List<String> args,  Map<String, String> env,  String sourceId)  $default,) {final _that = this;
switch (_that) {
case _ExternalToolHook():
return $default(_that.id,_that.enabled,_that.event,_that.command,_that.args,_that.env,_that.sourceId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  bool enabled,  String event,  String command,  List<String> args,  Map<String, String> env,  String sourceId)?  $default,) {final _that = this;
switch (_that) {
case _ExternalToolHook() when $default != null:
return $default(_that.id,_that.enabled,_that.event,_that.command,_that.args,_that.env,_that.sourceId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExternalToolHook extends ExternalToolHook {
  const _ExternalToolHook({required this.id, this.enabled = true, this.event = '', this.command = '', final  List<String> args = const <String>[], final  Map<String, String> env = const <String, String>{}, this.sourceId = ''}): _args = args,_env = env,super._();
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExternalToolHook&&(identical(other.id, id) || other.id == id)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.event, event) || other.event == event)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&const DeepCollectionEquality().equals(other._env, _env)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,enabled,event,command,const DeepCollectionEquality().hash(_args),const DeepCollectionEquality().hash(_env),sourceId);

@override
String toString() {
  return 'ExternalToolHook(id: $id, enabled: $enabled, event: $event, command: $command, args: $args, env: $env, sourceId: $sourceId)';
}


}

/// @nodoc
abstract mixin class _$ExternalToolHookCopyWith<$Res> implements $ExternalToolHookCopyWith<$Res> {
  factory _$ExternalToolHookCopyWith(_ExternalToolHook value, $Res Function(_ExternalToolHook) _then) = __$ExternalToolHookCopyWithImpl;
@override @useResult
$Res call({
 String id, bool enabled, String event, String command, List<String> args, Map<String, String> env, String sourceId
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? enabled = null,Object? event = null,Object? command = null,Object? args = null,Object? env = null,Object? sourceId = null,}) {
  return _then(_ExternalToolHook(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ModelCapabilityProfile {

 String get id;@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider get provider; String get baseUrl; String get model;@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle get toolCallStyle;@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport get structuredOutputSupport;@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference get editFormatPreference; int get usableContextTokens; DateTime? get probedAt; String get probeSummary; Map<String, String> get probeMetadata;
/// Create a copy of ModelCapabilityProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCapabilityProfileCopyWith<ModelCapabilityProfile> get copyWith => _$ModelCapabilityProfileCopyWithImpl<ModelCapabilityProfile>(this as ModelCapabilityProfile, _$identity);

  /// Serializes this ModelCapabilityProfile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCapabilityProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.toolCallStyle, toolCallStyle) || other.toolCallStyle == toolCallStyle)&&(identical(other.structuredOutputSupport, structuredOutputSupport) || other.structuredOutputSupport == structuredOutputSupport)&&(identical(other.editFormatPreference, editFormatPreference) || other.editFormatPreference == editFormatPreference)&&(identical(other.usableContextTokens, usableContextTokens) || other.usableContextTokens == usableContextTokens)&&(identical(other.probedAt, probedAt) || other.probedAt == probedAt)&&(identical(other.probeSummary, probeSummary) || other.probeSummary == probeSummary)&&const DeepCollectionEquality().equals(other.probeMetadata, probeMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,provider,baseUrl,model,toolCallStyle,structuredOutputSupport,editFormatPreference,usableContextTokens,probedAt,probeSummary,const DeepCollectionEquality().hash(probeMetadata));

@override
String toString() {
  return 'ModelCapabilityProfile(id: $id, provider: $provider, baseUrl: $baseUrl, model: $model, toolCallStyle: $toolCallStyle, structuredOutputSupport: $structuredOutputSupport, editFormatPreference: $editFormatPreference, usableContextTokens: $usableContextTokens, probedAt: $probedAt, probeSummary: $probeSummary, probeMetadata: $probeMetadata)';
}


}

/// @nodoc
abstract mixin class $ModelCapabilityProfileCopyWith<$Res>  {
  factory $ModelCapabilityProfileCopyWith(ModelCapabilityProfile value, $Res Function(ModelCapabilityProfile) _then) = _$ModelCapabilityProfileCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference, int usableContextTokens, DateTime? probedAt, String probeSummary, Map<String, String> probeMetadata
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? editFormatPreference = null,Object? usableContextTokens = null,Object? probedAt = freezed,Object? probeSummary = null,Object? probeMetadata = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,probedAt: freezed == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference,  int usableContextTokens,  DateTime? probedAt,  String probeSummary,  Map<String, String> probeMetadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCapabilityProfile() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.toolCallStyle,_that.structuredOutputSupport,_that.editFormatPreference,_that.usableContextTokens,_that.probedAt,_that.probeSummary,_that.probeMetadata);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference,  int usableContextTokens,  DateTime? probedAt,  String probeSummary,  Map<String, String> probeMetadata)  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfile():
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.toolCallStyle,_that.structuredOutputSupport,_that.editFormatPreference,_that.usableContextTokens,_that.probedAt,_that.probeSummary,_that.probeMetadata);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference,  int usableContextTokens,  DateTime? probedAt,  String probeSummary,  Map<String, String> probeMetadata)?  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfile() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.toolCallStyle,_that.structuredOutputSupport,_that.editFormatPreference,_that.usableContextTokens,_that.probedAt,_that.probeSummary,_that.probeMetadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelCapabilityProfile extends ModelCapabilityProfile {
  const _ModelCapabilityProfile({required this.id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) this.provider = LlmProvider.openAiCompatible, this.baseUrl = '', required this.model, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) this.toolCallStyle = ModelToolCallStyle.unknown, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) this.structuredOutputSupport = ModelStructuredOutputSupport.unknown, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) this.editFormatPreference = ModelEditFormatPreference.unknown, this.usableContextTokens = 0, this.probedAt, this.probeSummary = '', final  Map<String, String> probeMetadata = const <String, String>{}}): _probeMetadata = probeMetadata,super._();
  factory _ModelCapabilityProfile.fromJson(Map<String, dynamic> json) => _$ModelCapabilityProfileFromJson(json);

@override final  String id;
@override@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) final  LlmProvider provider;
@override@JsonKey() final  String baseUrl;
@override final  String model;
@override@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) final  ModelToolCallStyle toolCallStyle;
@override@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) final  ModelStructuredOutputSupport structuredOutputSupport;
@override@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) final  ModelEditFormatPreference editFormatPreference;
@override@JsonKey() final  int usableContextTokens;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCapabilityProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.toolCallStyle, toolCallStyle) || other.toolCallStyle == toolCallStyle)&&(identical(other.structuredOutputSupport, structuredOutputSupport) || other.structuredOutputSupport == structuredOutputSupport)&&(identical(other.editFormatPreference, editFormatPreference) || other.editFormatPreference == editFormatPreference)&&(identical(other.usableContextTokens, usableContextTokens) || other.usableContextTokens == usableContextTokens)&&(identical(other.probedAt, probedAt) || other.probedAt == probedAt)&&(identical(other.probeSummary, probeSummary) || other.probeSummary == probeSummary)&&const DeepCollectionEquality().equals(other._probeMetadata, _probeMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,provider,baseUrl,model,toolCallStyle,structuredOutputSupport,editFormatPreference,usableContextTokens,probedAt,probeSummary,const DeepCollectionEquality().hash(_probeMetadata));

@override
String toString() {
  return 'ModelCapabilityProfile(id: $id, provider: $provider, baseUrl: $baseUrl, model: $model, toolCallStyle: $toolCallStyle, structuredOutputSupport: $structuredOutputSupport, editFormatPreference: $editFormatPreference, usableContextTokens: $usableContextTokens, probedAt: $probedAt, probeSummary: $probeSummary, probeMetadata: $probeMetadata)';
}


}

/// @nodoc
abstract mixin class _$ModelCapabilityProfileCopyWith<$Res> implements $ModelCapabilityProfileCopyWith<$Res> {
  factory _$ModelCapabilityProfileCopyWith(_ModelCapabilityProfile value, $Res Function(_ModelCapabilityProfile) _then) = __$ModelCapabilityProfileCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference, int usableContextTokens, DateTime? probedAt, String probeSummary, Map<String, String> probeMetadata
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? editFormatPreference = null,Object? usableContextTokens = null,Object? probedAt = freezed,Object? probeSummary = null,Object? probeMetadata = null,}) {
  return _then(_ModelCapabilityProfile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,probedAt: freezed == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,probeMetadata: null == probeMetadata ? _self._probeMetadata : probeMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}


/// @nodoc
mixin _$ModelHarnessConfig {

 String get id;@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider get provider; String get baseUrl; String get model;// Instruction surfaces. An empty string falls back to the built-in
// SystemPromptBuilder guidance for that surface.
 String get bootstrapInstruction; String get executionInstruction; String get verificationInstruction; String get failureRecoveryInstruction;// Runtime control policy. Zero / false means "use the existing harness
// default" so the config never silently weakens current behaviour.
 int get toolLoopMaxIterations; bool get recoveryMiddlewareEnabled; bool get explorationToEditNudgeEnabled;
/// Create a copy of ModelHarnessConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelHarnessConfigCopyWith<ModelHarnessConfig> get copyWith => _$ModelHarnessConfigCopyWithImpl<ModelHarnessConfig>(this as ModelHarnessConfig, _$identity);

  /// Serializes this ModelHarnessConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelHarnessConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.bootstrapInstruction, bootstrapInstruction) || other.bootstrapInstruction == bootstrapInstruction)&&(identical(other.executionInstruction, executionInstruction) || other.executionInstruction == executionInstruction)&&(identical(other.verificationInstruction, verificationInstruction) || other.verificationInstruction == verificationInstruction)&&(identical(other.failureRecoveryInstruction, failureRecoveryInstruction) || other.failureRecoveryInstruction == failureRecoveryInstruction)&&(identical(other.toolLoopMaxIterations, toolLoopMaxIterations) || other.toolLoopMaxIterations == toolLoopMaxIterations)&&(identical(other.recoveryMiddlewareEnabled, recoveryMiddlewareEnabled) || other.recoveryMiddlewareEnabled == recoveryMiddlewareEnabled)&&(identical(other.explorationToEditNudgeEnabled, explorationToEditNudgeEnabled) || other.explorationToEditNudgeEnabled == explorationToEditNudgeEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,provider,baseUrl,model,bootstrapInstruction,executionInstruction,verificationInstruction,failureRecoveryInstruction,toolLoopMaxIterations,recoveryMiddlewareEnabled,explorationToEditNudgeEnabled);

@override
String toString() {
  return 'ModelHarnessConfig(id: $id, provider: $provider, baseUrl: $baseUrl, model: $model, bootstrapInstruction: $bootstrapInstruction, executionInstruction: $executionInstruction, verificationInstruction: $verificationInstruction, failureRecoveryInstruction: $failureRecoveryInstruction, toolLoopMaxIterations: $toolLoopMaxIterations, recoveryMiddlewareEnabled: $recoveryMiddlewareEnabled, explorationToEditNudgeEnabled: $explorationToEditNudgeEnabled)';
}


}

/// @nodoc
abstract mixin class $ModelHarnessConfigCopyWith<$Res>  {
  factory $ModelHarnessConfigCopyWith(ModelHarnessConfig value, $Res Function(ModelHarnessConfig) _then) = _$ModelHarnessConfigCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model, String bootstrapInstruction, String executionInstruction, String verificationInstruction, String failureRecoveryInstruction, int toolLoopMaxIterations, bool recoveryMiddlewareEnabled, bool explorationToEditNudgeEnabled
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? bootstrapInstruction = null,Object? executionInstruction = null,Object? verificationInstruction = null,Object? failureRecoveryInstruction = null,Object? toolLoopMaxIterations = null,Object? recoveryMiddlewareEnabled = null,Object? explorationToEditNudgeEnabled = null,}) {
  return _then(_self.copyWith(
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
as bool,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model,  String bootstrapInstruction,  String executionInstruction,  String verificationInstruction,  String failureRecoveryInstruction,  int toolLoopMaxIterations,  bool recoveryMiddlewareEnabled,  bool explorationToEditNudgeEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelHarnessConfig() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.bootstrapInstruction,_that.executionInstruction,_that.verificationInstruction,_that.failureRecoveryInstruction,_that.toolLoopMaxIterations,_that.recoveryMiddlewareEnabled,_that.explorationToEditNudgeEnabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model,  String bootstrapInstruction,  String executionInstruction,  String verificationInstruction,  String failureRecoveryInstruction,  int toolLoopMaxIterations,  bool recoveryMiddlewareEnabled,  bool explorationToEditNudgeEnabled)  $default,) {final _that = this;
switch (_that) {
case _ModelHarnessConfig():
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.bootstrapInstruction,_that.executionInstruction,_that.verificationInstruction,_that.failureRecoveryInstruction,_that.toolLoopMaxIterations,_that.recoveryMiddlewareEnabled,_that.explorationToEditNudgeEnabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider provider,  String baseUrl,  String model,  String bootstrapInstruction,  String executionInstruction,  String verificationInstruction,  String failureRecoveryInstruction,  int toolLoopMaxIterations,  bool recoveryMiddlewareEnabled,  bool explorationToEditNudgeEnabled)?  $default,) {final _that = this;
switch (_that) {
case _ModelHarnessConfig() when $default != null:
return $default(_that.id,_that.provider,_that.baseUrl,_that.model,_that.bootstrapInstruction,_that.executionInstruction,_that.verificationInstruction,_that.failureRecoveryInstruction,_that.toolLoopMaxIterations,_that.recoveryMiddlewareEnabled,_that.explorationToEditNudgeEnabled);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelHarnessConfig extends ModelHarnessConfig {
  const _ModelHarnessConfig({required this.id, @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) this.provider = LlmProvider.openAiCompatible, this.baseUrl = '', required this.model, this.bootstrapInstruction = '', this.executionInstruction = '', this.verificationInstruction = '', this.failureRecoveryInstruction = '', this.toolLoopMaxIterations = 0, this.recoveryMiddlewareEnabled = false, this.explorationToEditNudgeEnabled = false}): super._();
  factory _ModelHarnessConfig.fromJson(Map<String, dynamic> json) => _$ModelHarnessConfigFromJson(json);

@override final  String id;
@override@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) final  LlmProvider provider;
@override@JsonKey() final  String baseUrl;
@override final  String model;
// Instruction surfaces. An empty string falls back to the built-in
// SystemPromptBuilder guidance for that surface.
@override@JsonKey() final  String bootstrapInstruction;
@override@JsonKey() final  String executionInstruction;
@override@JsonKey() final  String verificationInstruction;
@override@JsonKey() final  String failureRecoveryInstruction;
// Runtime control policy. Zero / false means "use the existing harness
// default" so the config never silently weakens current behaviour.
@override@JsonKey() final  int toolLoopMaxIterations;
@override@JsonKey() final  bool recoveryMiddlewareEnabled;
@override@JsonKey() final  bool explorationToEditNudgeEnabled;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelHarnessConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.bootstrapInstruction, bootstrapInstruction) || other.bootstrapInstruction == bootstrapInstruction)&&(identical(other.executionInstruction, executionInstruction) || other.executionInstruction == executionInstruction)&&(identical(other.verificationInstruction, verificationInstruction) || other.verificationInstruction == verificationInstruction)&&(identical(other.failureRecoveryInstruction, failureRecoveryInstruction) || other.failureRecoveryInstruction == failureRecoveryInstruction)&&(identical(other.toolLoopMaxIterations, toolLoopMaxIterations) || other.toolLoopMaxIterations == toolLoopMaxIterations)&&(identical(other.recoveryMiddlewareEnabled, recoveryMiddlewareEnabled) || other.recoveryMiddlewareEnabled == recoveryMiddlewareEnabled)&&(identical(other.explorationToEditNudgeEnabled, explorationToEditNudgeEnabled) || other.explorationToEditNudgeEnabled == explorationToEditNudgeEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,provider,baseUrl,model,bootstrapInstruction,executionInstruction,verificationInstruction,failureRecoveryInstruction,toolLoopMaxIterations,recoveryMiddlewareEnabled,explorationToEditNudgeEnabled);

@override
String toString() {
  return 'ModelHarnessConfig(id: $id, provider: $provider, baseUrl: $baseUrl, model: $model, bootstrapInstruction: $bootstrapInstruction, executionInstruction: $executionInstruction, verificationInstruction: $verificationInstruction, failureRecoveryInstruction: $failureRecoveryInstruction, toolLoopMaxIterations: $toolLoopMaxIterations, recoveryMiddlewareEnabled: $recoveryMiddlewareEnabled, explorationToEditNudgeEnabled: $explorationToEditNudgeEnabled)';
}


}

/// @nodoc
abstract mixin class _$ModelHarnessConfigCopyWith<$Res> implements $ModelHarnessConfigCopyWith<$Res> {
  factory _$ModelHarnessConfigCopyWith(_ModelHarnessConfig value, $Res Function(_ModelHarnessConfig) _then) = __$ModelHarnessConfigCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider provider, String baseUrl, String model, String bootstrapInstruction, String executionInstruction, String verificationInstruction, String failureRecoveryInstruction, int toolLoopMaxIterations, bool recoveryMiddlewareEnabled, bool explorationToEditNudgeEnabled
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? provider = null,Object? baseUrl = null,Object? model = null,Object? bootstrapInstruction = null,Object? executionInstruction = null,Object? verificationInstruction = null,Object? failureRecoveryInstruction = null,Object? toolLoopMaxIterations = null,Object? recoveryMiddlewareEnabled = null,Object? explorationToEditNudgeEnabled = null,}) {
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
as bool,
  ));
}


}


/// @nodoc
mixin _$ModelCapabilityProfileRevision {

 String get profileId; DateTime get probedAt;@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle get toolCallStyle;@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport get structuredOutputSupport;@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference get editFormatPreference; int get usableContextTokens; String get probeSummary;/// How this revision was triggered. Known values: 'initial', 'idle_re_probe',
/// 'calibrate', 'manual', 'probe'.
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCapabilityProfileRevision&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.probedAt, probedAt) || other.probedAt == probedAt)&&(identical(other.toolCallStyle, toolCallStyle) || other.toolCallStyle == toolCallStyle)&&(identical(other.structuredOutputSupport, structuredOutputSupport) || other.structuredOutputSupport == structuredOutputSupport)&&(identical(other.editFormatPreference, editFormatPreference) || other.editFormatPreference == editFormatPreference)&&(identical(other.usableContextTokens, usableContextTokens) || other.usableContextTokens == usableContextTokens)&&(identical(other.probeSummary, probeSummary) || other.probeSummary == probeSummary)&&(identical(other.source, source) || other.source == source)&&(identical(other.capabilityChangeDetected, capabilityChangeDetected) || other.capabilityChangeDetected == capabilityChangeDetected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,profileId,probedAt,toolCallStyle,structuredOutputSupport,editFormatPreference,usableContextTokens,probeSummary,source,capabilityChangeDetected);

@override
String toString() {
  return 'ModelCapabilityProfileRevision(profileId: $profileId, probedAt: $probedAt, toolCallStyle: $toolCallStyle, structuredOutputSupport: $structuredOutputSupport, editFormatPreference: $editFormatPreference, usableContextTokens: $usableContextTokens, probeSummary: $probeSummary, source: $source, capabilityChangeDetected: $capabilityChangeDetected)';
}


}

/// @nodoc
abstract mixin class $ModelCapabilityProfileRevisionCopyWith<$Res>  {
  factory $ModelCapabilityProfileRevisionCopyWith(ModelCapabilityProfileRevision value, $Res Function(ModelCapabilityProfileRevision) _then) = _$ModelCapabilityProfileRevisionCopyWithImpl;
@useResult
$Res call({
 String profileId, DateTime probedAt,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference, int usableContextTokens, String probeSummary, String source, bool capabilityChangeDetected
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
@pragma('vm:prefer-inline') @override $Res call({Object? profileId = null,Object? probedAt = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? editFormatPreference = null,Object? usableContextTokens = null,Object? probeSummary = null,Object? source = null,Object? capabilityChangeDetected = null,}) {
  return _then(_self.copyWith(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,probedAt: null == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String profileId,  DateTime probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference,  int usableContextTokens,  String probeSummary,  String source,  bool capabilityChangeDetected)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision() when $default != null:
return $default(_that.profileId,_that.probedAt,_that.toolCallStyle,_that.structuredOutputSupport,_that.editFormatPreference,_that.usableContextTokens,_that.probeSummary,_that.source,_that.capabilityChangeDetected);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String profileId,  DateTime probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference,  int usableContextTokens,  String probeSummary,  String source,  bool capabilityChangeDetected)  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision():
return $default(_that.profileId,_that.probedAt,_that.toolCallStyle,_that.structuredOutputSupport,_that.editFormatPreference,_that.usableContextTokens,_that.probeSummary,_that.source,_that.capabilityChangeDetected);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String profileId,  DateTime probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)  ModelToolCallStyle toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)  ModelStructuredOutputSupport structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)  ModelEditFormatPreference editFormatPreference,  int usableContextTokens,  String probeSummary,  String source,  bool capabilityChangeDetected)?  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilityProfileRevision() when $default != null:
return $default(_that.profileId,_that.probedAt,_that.toolCallStyle,_that.structuredOutputSupport,_that.editFormatPreference,_that.usableContextTokens,_that.probeSummary,_that.source,_that.capabilityChangeDetected);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelCapabilityProfileRevision extends ModelCapabilityProfileRevision {
  const _ModelCapabilityProfileRevision({required this.profileId, required this.probedAt, @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) required this.toolCallStyle, @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) required this.structuredOutputSupport, @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) required this.editFormatPreference, required this.usableContextTokens, this.probeSummary = '', this.source = 'probe', this.capabilityChangeDetected = false}): super._();
  factory _ModelCapabilityProfileRevision.fromJson(Map<String, dynamic> json) => _$ModelCapabilityProfileRevisionFromJson(json);

@override final  String profileId;
@override final  DateTime probedAt;
@override@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) final  ModelToolCallStyle toolCallStyle;
@override@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) final  ModelStructuredOutputSupport structuredOutputSupport;
@override@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) final  ModelEditFormatPreference editFormatPreference;
@override final  int usableContextTokens;
@override@JsonKey() final  String probeSummary;
/// How this revision was triggered. Known values: 'initial', 'idle_re_probe',
/// 'calibrate', 'manual', 'probe'.
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCapabilityProfileRevision&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.probedAt, probedAt) || other.probedAt == probedAt)&&(identical(other.toolCallStyle, toolCallStyle) || other.toolCallStyle == toolCallStyle)&&(identical(other.structuredOutputSupport, structuredOutputSupport) || other.structuredOutputSupport == structuredOutputSupport)&&(identical(other.editFormatPreference, editFormatPreference) || other.editFormatPreference == editFormatPreference)&&(identical(other.usableContextTokens, usableContextTokens) || other.usableContextTokens == usableContextTokens)&&(identical(other.probeSummary, probeSummary) || other.probeSummary == probeSummary)&&(identical(other.source, source) || other.source == source)&&(identical(other.capabilityChangeDetected, capabilityChangeDetected) || other.capabilityChangeDetected == capabilityChangeDetected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,profileId,probedAt,toolCallStyle,structuredOutputSupport,editFormatPreference,usableContextTokens,probeSummary,source,capabilityChangeDetected);

@override
String toString() {
  return 'ModelCapabilityProfileRevision(profileId: $profileId, probedAt: $probedAt, toolCallStyle: $toolCallStyle, structuredOutputSupport: $structuredOutputSupport, editFormatPreference: $editFormatPreference, usableContextTokens: $usableContextTokens, probeSummary: $probeSummary, source: $source, capabilityChangeDetected: $capabilityChangeDetected)';
}


}

/// @nodoc
abstract mixin class _$ModelCapabilityProfileRevisionCopyWith<$Res> implements $ModelCapabilityProfileRevisionCopyWith<$Res> {
  factory _$ModelCapabilityProfileRevisionCopyWith(_ModelCapabilityProfileRevision value, $Res Function(_ModelCapabilityProfileRevision) _then) = __$ModelCapabilityProfileRevisionCopyWithImpl;
@override @useResult
$Res call({
 String profileId, DateTime probedAt,@JsonKey(unknownEnumValue: ModelToolCallStyle.unknown) ModelToolCallStyle toolCallStyle,@JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown) ModelStructuredOutputSupport structuredOutputSupport,@JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown) ModelEditFormatPreference editFormatPreference, int usableContextTokens, String probeSummary, String source, bool capabilityChangeDetected
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
@override @pragma('vm:prefer-inline') $Res call({Object? profileId = null,Object? probedAt = null,Object? toolCallStyle = null,Object? structuredOutputSupport = null,Object? editFormatPreference = null,Object? usableContextTokens = null,Object? probeSummary = null,Object? source = null,Object? capabilityChangeDetected = null,}) {
  return _then(_ModelCapabilityProfileRevision(
profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,probedAt: null == probedAt ? _self.probedAt : probedAt // ignore: cast_nullable_to_non_nullable
as DateTime,toolCallStyle: null == toolCallStyle ? _self.toolCallStyle : toolCallStyle // ignore: cast_nullable_to_non_nullable
as ModelToolCallStyle,structuredOutputSupport: null == structuredOutputSupport ? _self.structuredOutputSupport : structuredOutputSupport // ignore: cast_nullable_to_non_nullable
as ModelStructuredOutputSupport,editFormatPreference: null == editFormatPreference ? _self.editFormatPreference : editFormatPreference // ignore: cast_nullable_to_non_nullable
as ModelEditFormatPreference,usableContextTokens: null == usableContextTokens ? _self.usableContextTokens : usableContextTokens // ignore: cast_nullable_to_non_nullable
as int,probeSummary: null == probeSummary ? _self.probeSummary : probeSummary // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,capabilityChangeDetected: null == capabilityChangeDetected ? _self.capabilityChangeDetected : capabilityChangeDetected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$NamedEndpoint {

 String get id; String get label; String get baseUrl; String get apiKey; bool get enabled; DateTime? get createdAt;
/// Create a copy of NamedEndpoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NamedEndpointCopyWith<NamedEndpoint> get copyWith => _$NamedEndpointCopyWithImpl<NamedEndpoint>(this as NamedEndpoint, _$identity);

  /// Serializes this NamedEndpoint to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NamedEndpoint&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,baseUrl,apiKey,enabled,createdAt);

@override
String toString() {
  return 'NamedEndpoint(id: $id, label: $label, baseUrl: $baseUrl, apiKey: $apiKey, enabled: $enabled, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $NamedEndpointCopyWith<$Res>  {
  factory $NamedEndpointCopyWith(NamedEndpoint value, $Res Function(NamedEndpoint) _then) = _$NamedEndpointCopyWithImpl;
@useResult
$Res call({
 String id, String label, String baseUrl, String apiKey, bool enabled, DateTime? createdAt
});




}
/// @nodoc
class _$NamedEndpointCopyWithImpl<$Res>
    implements $NamedEndpointCopyWith<$Res> {
  _$NamedEndpointCopyWithImpl(this._self, this._then);

  final NamedEndpoint _self;
  final $Res Function(NamedEndpoint) _then;

/// Create a copy of NamedEndpoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? baseUrl = null,Object? apiKey = null,Object? enabled = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [NamedEndpoint].
extension NamedEndpointPatterns on NamedEndpoint {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NamedEndpoint value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NamedEndpoint() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NamedEndpoint value)  $default,){
final _that = this;
switch (_that) {
case _NamedEndpoint():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NamedEndpoint value)?  $default,){
final _that = this;
switch (_that) {
case _NamedEndpoint() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String baseUrl,  String apiKey,  bool enabled,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NamedEndpoint() when $default != null:
return $default(_that.id,_that.label,_that.baseUrl,_that.apiKey,_that.enabled,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String baseUrl,  String apiKey,  bool enabled,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _NamedEndpoint():
return $default(_that.id,_that.label,_that.baseUrl,_that.apiKey,_that.enabled,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String baseUrl,  String apiKey,  bool enabled,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _NamedEndpoint() when $default != null:
return $default(_that.id,_that.label,_that.baseUrl,_that.apiKey,_that.enabled,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NamedEndpoint extends NamedEndpoint {
  const _NamedEndpoint({required this.id, this.label = '', this.baseUrl = '', this.apiKey = '', this.enabled = true, this.createdAt}): super._();
  factory _NamedEndpoint.fromJson(Map<String, dynamic> json) => _$NamedEndpointFromJson(json);

@override final  String id;
@override@JsonKey() final  String label;
@override@JsonKey() final  String baseUrl;
@override@JsonKey() final  String apiKey;
@override@JsonKey() final  bool enabled;
@override final  DateTime? createdAt;

/// Create a copy of NamedEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NamedEndpointCopyWith<_NamedEndpoint> get copyWith => __$NamedEndpointCopyWithImpl<_NamedEndpoint>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NamedEndpointToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NamedEndpoint&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,baseUrl,apiKey,enabled,createdAt);

@override
String toString() {
  return 'NamedEndpoint(id: $id, label: $label, baseUrl: $baseUrl, apiKey: $apiKey, enabled: $enabled, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$NamedEndpointCopyWith<$Res> implements $NamedEndpointCopyWith<$Res> {
  factory _$NamedEndpointCopyWith(_NamedEndpoint value, $Res Function(_NamedEndpoint) _then) = __$NamedEndpointCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String baseUrl, String apiKey, bool enabled, DateTime? createdAt
});




}
/// @nodoc
class __$NamedEndpointCopyWithImpl<$Res>
    implements _$NamedEndpointCopyWith<$Res> {
  __$NamedEndpointCopyWithImpl(this._self, this._then);

  final _NamedEndpoint _self;
  final $Res Function(_NamedEndpoint) _then;

/// Create a copy of NamedEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? baseUrl = null,Object? apiKey = null,Object? enabled = null,Object? createdAt = freezed,}) {
  return _then(_NamedEndpoint(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$AppSettings {

@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider get llmProvider; String get baseUrl; String get model; String get apiKey; double get temperature; int get maxTokens;@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference get reasoningEffort;// Per-role model routing (LL1). Empty string means "use the main model".
// Lets secondary LLM calls run on a smaller, faster local model.
 String get memoryExtractionModel; String get subagentModel; String get goalSuggestionModel; String get approvalAutoReviewModel;// LL8 per-role endpoint routing. Empty string means "use the primary
// endpoint". A non-empty value is a NamedEndpoint id; an unreachable mesh
// endpoint falls back to the primary at call time (MeshEndpointRouter).
 String get memoryExtractionEndpointId; String get subagentEndpointId; String get goalSuggestionEndpointId; String get approvalAutoReviewEndpointId; String get googleChatWebhookUrl; String get mcpUrl; List<String> get mcpUrls; List<McpServerConfig> get mcpServers; bool get mcpEnabled; bool get externalSettingsSyncEnabled; String get externalSettingsPath; bool get externalToolHooksEnabled;@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> get externalToolHooks;// Voice settings
 bool get ttsEnabled; bool get autoReadEnabled; double get speechRate;// Voice mode (Whisper + VOICEVOX)
 bool get voiceModeAutoStop; String get whisperUrl; String get voicevoxUrl; int get voicevoxSpeakerId; String get language;@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode get assistantMode;@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode get codingApprovalMode;// Approval policy for chat-mode built-in browser automation. Reuses the
// shared [ToolApprovalMode] levels but is independent from coding writes.
@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode get chatApprovalMode; bool get confirmFileMutations; bool get confirmLocalCommands; bool get confirmGitWrites; bool get enableCodingVerificationFeedback;@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) CodingVerificationTriggerPolicy get codingVerificationTriggerPolicy; int get codingVerificationTimeoutSeconds; int get codingVerificationMaxFailures; bool get enableAgentsMd; bool get enablePrefixStableToolLoop;// LL5: opt-in local semantic search. When enabled and an embeddings model
// is configured, conversation history is embedded for semantic search;
// otherwise search degrades to lexical FTS.
 bool get enableSemanticSearch; String get embeddingsModel; bool get showMemoryUpdates; bool get enableLlmSessionLogs; bool get feedbackUploadEnabled; String get feedbackEndpointUrl; bool get demoMode; bool get onboardingCompleted; bool get browserToolsEnabled; List<String> get disabledBuiltInTools; List<LocalCommandPermissionRule> get localCommandPermissionRules; List<RoutineComputerUseActionAllowlistEntry> get routineComputerUseActionAllowlist;@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> get modelCapabilityProfiles;@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> get modelHarnessConfigs;@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> get modelCapabilityProfileRevisions;// LL8: user-registered LAN inference endpoints (the mesh). Discovery only
// proposes candidates; entries here are explicitly registered.
@JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson) List<NamedEndpoint> get namedEndpoints;// LL18 idle/overnight maintenance gating (consumed via the maintenance
// feature's IdleMaintenanceConfig; minutes are since local midnight).
 bool get idleMaintenanceEnabled; int get idleMaintenanceWindowStartMinutes; int get idleMaintenanceWindowEndMinutes; int get idleMaintenanceMinIdleMinutes; bool get idleMaintenanceRequireAcPower;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.llmProvider, llmProvider) || other.llmProvider == llmProvider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.reasoningEffort, reasoningEffort) || other.reasoningEffort == reasoningEffort)&&(identical(other.memoryExtractionModel, memoryExtractionModel) || other.memoryExtractionModel == memoryExtractionModel)&&(identical(other.subagentModel, subagentModel) || other.subagentModel == subagentModel)&&(identical(other.goalSuggestionModel, goalSuggestionModel) || other.goalSuggestionModel == goalSuggestionModel)&&(identical(other.approvalAutoReviewModel, approvalAutoReviewModel) || other.approvalAutoReviewModel == approvalAutoReviewModel)&&(identical(other.memoryExtractionEndpointId, memoryExtractionEndpointId) || other.memoryExtractionEndpointId == memoryExtractionEndpointId)&&(identical(other.subagentEndpointId, subagentEndpointId) || other.subagentEndpointId == subagentEndpointId)&&(identical(other.goalSuggestionEndpointId, goalSuggestionEndpointId) || other.goalSuggestionEndpointId == goalSuggestionEndpointId)&&(identical(other.approvalAutoReviewEndpointId, approvalAutoReviewEndpointId) || other.approvalAutoReviewEndpointId == approvalAutoReviewEndpointId)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other.mcpUrls, mcpUrls)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.externalSettingsSyncEnabled, externalSettingsSyncEnabled) || other.externalSettingsSyncEnabled == externalSettingsSyncEnabled)&&(identical(other.externalSettingsPath, externalSettingsPath) || other.externalSettingsPath == externalSettingsPath)&&(identical(other.externalToolHooksEnabled, externalToolHooksEnabled) || other.externalToolHooksEnabled == externalToolHooksEnabled)&&const DeepCollectionEquality().equals(other.externalToolHooks, externalToolHooks)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.codingApprovalMode, codingApprovalMode) || other.codingApprovalMode == codingApprovalMode)&&(identical(other.chatApprovalMode, chatApprovalMode) || other.chatApprovalMode == chatApprovalMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.enableCodingVerificationFeedback, enableCodingVerificationFeedback) || other.enableCodingVerificationFeedback == enableCodingVerificationFeedback)&&(identical(other.codingVerificationTriggerPolicy, codingVerificationTriggerPolicy) || other.codingVerificationTriggerPolicy == codingVerificationTriggerPolicy)&&(identical(other.codingVerificationTimeoutSeconds, codingVerificationTimeoutSeconds) || other.codingVerificationTimeoutSeconds == codingVerificationTimeoutSeconds)&&(identical(other.codingVerificationMaxFailures, codingVerificationMaxFailures) || other.codingVerificationMaxFailures == codingVerificationMaxFailures)&&(identical(other.enableAgentsMd, enableAgentsMd) || other.enableAgentsMd == enableAgentsMd)&&(identical(other.enablePrefixStableToolLoop, enablePrefixStableToolLoop) || other.enablePrefixStableToolLoop == enablePrefixStableToolLoop)&&(identical(other.enableSemanticSearch, enableSemanticSearch) || other.enableSemanticSearch == enableSemanticSearch)&&(identical(other.embeddingsModel, embeddingsModel) || other.embeddingsModel == embeddingsModel)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.enableLlmSessionLogs, enableLlmSessionLogs) || other.enableLlmSessionLogs == enableLlmSessionLogs)&&(identical(other.feedbackUploadEnabled, feedbackUploadEnabled) || other.feedbackUploadEnabled == feedbackUploadEnabled)&&(identical(other.feedbackEndpointUrl, feedbackEndpointUrl) || other.feedbackEndpointUrl == feedbackEndpointUrl)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&(identical(other.onboardingCompleted, onboardingCompleted) || other.onboardingCompleted == onboardingCompleted)&&(identical(other.browserToolsEnabled, browserToolsEnabled) || other.browserToolsEnabled == browserToolsEnabled)&&const DeepCollectionEquality().equals(other.disabledBuiltInTools, disabledBuiltInTools)&&const DeepCollectionEquality().equals(other.localCommandPermissionRules, localCommandPermissionRules)&&const DeepCollectionEquality().equals(other.routineComputerUseActionAllowlist, routineComputerUseActionAllowlist)&&const DeepCollectionEquality().equals(other.modelCapabilityProfiles, modelCapabilityProfiles)&&const DeepCollectionEquality().equals(other.modelHarnessConfigs, modelHarnessConfigs)&&const DeepCollectionEquality().equals(other.modelCapabilityProfileRevisions, modelCapabilityProfileRevisions)&&const DeepCollectionEquality().equals(other.namedEndpoints, namedEndpoints)&&(identical(other.idleMaintenanceEnabled, idleMaintenanceEnabled) || other.idleMaintenanceEnabled == idleMaintenanceEnabled)&&(identical(other.idleMaintenanceWindowStartMinutes, idleMaintenanceWindowStartMinutes) || other.idleMaintenanceWindowStartMinutes == idleMaintenanceWindowStartMinutes)&&(identical(other.idleMaintenanceWindowEndMinutes, idleMaintenanceWindowEndMinutes) || other.idleMaintenanceWindowEndMinutes == idleMaintenanceWindowEndMinutes)&&(identical(other.idleMaintenanceMinIdleMinutes, idleMaintenanceMinIdleMinutes) || other.idleMaintenanceMinIdleMinutes == idleMaintenanceMinIdleMinutes)&&(identical(other.idleMaintenanceRequireAcPower, idleMaintenanceRequireAcPower) || other.idleMaintenanceRequireAcPower == idleMaintenanceRequireAcPower));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,llmProvider,baseUrl,model,apiKey,temperature,maxTokens,reasoningEffort,memoryExtractionModel,subagentModel,goalSuggestionModel,approvalAutoReviewModel,memoryExtractionEndpointId,subagentEndpointId,goalSuggestionEndpointId,approvalAutoReviewEndpointId,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(mcpUrls),const DeepCollectionEquality().hash(mcpServers),mcpEnabled,externalSettingsSyncEnabled,externalSettingsPath,externalToolHooksEnabled,const DeepCollectionEquality().hash(externalToolHooks),ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,codingApprovalMode,chatApprovalMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,enableCodingVerificationFeedback,codingVerificationTriggerPolicy,codingVerificationTimeoutSeconds,codingVerificationMaxFailures,enableAgentsMd,enablePrefixStableToolLoop,enableSemanticSearch,embeddingsModel,showMemoryUpdates,enableLlmSessionLogs,feedbackUploadEnabled,feedbackEndpointUrl,demoMode,onboardingCompleted,browserToolsEnabled,const DeepCollectionEquality().hash(disabledBuiltInTools),const DeepCollectionEquality().hash(localCommandPermissionRules),const DeepCollectionEquality().hash(routineComputerUseActionAllowlist),const DeepCollectionEquality().hash(modelCapabilityProfiles),const DeepCollectionEquality().hash(modelHarnessConfigs),const DeepCollectionEquality().hash(modelCapabilityProfileRevisions),const DeepCollectionEquality().hash(namedEndpoints),idleMaintenanceEnabled,idleMaintenanceWindowStartMinutes,idleMaintenanceWindowEndMinutes,idleMaintenanceMinIdleMinutes,idleMaintenanceRequireAcPower]);

@override
String toString() {
  return 'AppSettings(llmProvider: $llmProvider, baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, reasoningEffort: $reasoningEffort, memoryExtractionModel: $memoryExtractionModel, subagentModel: $subagentModel, goalSuggestionModel: $goalSuggestionModel, approvalAutoReviewModel: $approvalAutoReviewModel, memoryExtractionEndpointId: $memoryExtractionEndpointId, subagentEndpointId: $subagentEndpointId, goalSuggestionEndpointId: $goalSuggestionEndpointId, approvalAutoReviewEndpointId: $approvalAutoReviewEndpointId, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, externalSettingsSyncEnabled: $externalSettingsSyncEnabled, externalSettingsPath: $externalSettingsPath, externalToolHooksEnabled: $externalToolHooksEnabled, externalToolHooks: $externalToolHooks, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, codingApprovalMode: $codingApprovalMode, chatApprovalMode: $chatApprovalMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, enableCodingVerificationFeedback: $enableCodingVerificationFeedback, codingVerificationTriggerPolicy: $codingVerificationTriggerPolicy, codingVerificationTimeoutSeconds: $codingVerificationTimeoutSeconds, codingVerificationMaxFailures: $codingVerificationMaxFailures, enableAgentsMd: $enableAgentsMd, enablePrefixStableToolLoop: $enablePrefixStableToolLoop, enableSemanticSearch: $enableSemanticSearch, embeddingsModel: $embeddingsModel, showMemoryUpdates: $showMemoryUpdates, enableLlmSessionLogs: $enableLlmSessionLogs, feedbackUploadEnabled: $feedbackUploadEnabled, feedbackEndpointUrl: $feedbackEndpointUrl, demoMode: $demoMode, onboardingCompleted: $onboardingCompleted, browserToolsEnabled: $browserToolsEnabled, disabledBuiltInTools: $disabledBuiltInTools, localCommandPermissionRules: $localCommandPermissionRules, routineComputerUseActionAllowlist: $routineComputerUseActionAllowlist, modelCapabilityProfiles: $modelCapabilityProfiles, modelHarnessConfigs: $modelHarnessConfigs, modelCapabilityProfileRevisions: $modelCapabilityProfileRevisions, namedEndpoints: $namedEndpoints, idleMaintenanceEnabled: $idleMaintenanceEnabled, idleMaintenanceWindowStartMinutes: $idleMaintenanceWindowStartMinutes, idleMaintenanceWindowEndMinutes: $idleMaintenanceWindowEndMinutes, idleMaintenanceMinIdleMinutes: $idleMaintenanceMinIdleMinutes, idleMaintenanceRequireAcPower: $idleMaintenanceRequireAcPower)';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider llmProvider, String baseUrl, String model, String apiKey, double temperature, int maxTokens,@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference reasoningEffort, String memoryExtractionModel, String subagentModel, String goalSuggestionModel, String approvalAutoReviewModel, String memoryExtractionEndpointId, String subagentEndpointId, String goalSuggestionEndpointId, String approvalAutoReviewEndpointId, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool externalSettingsSyncEnabled, String externalSettingsPath, bool externalToolHooksEnabled,@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> externalToolHooks, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode codingApprovalMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode chatApprovalMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool enableCodingVerificationFeedback,@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) CodingVerificationTriggerPolicy codingVerificationTriggerPolicy, int codingVerificationTimeoutSeconds, int codingVerificationMaxFailures, bool enableAgentsMd, bool enablePrefixStableToolLoop, bool enableSemanticSearch, String embeddingsModel, bool showMemoryUpdates, bool enableLlmSessionLogs, bool feedbackUploadEnabled, String feedbackEndpointUrl, bool demoMode, bool onboardingCompleted, bool browserToolsEnabled, List<String> disabledBuiltInTools, List<LocalCommandPermissionRule> localCommandPermissionRules, List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist,@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> modelCapabilityProfiles,@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> modelHarnessConfigs,@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions,@JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson) List<NamedEndpoint> namedEndpoints, bool idleMaintenanceEnabled, int idleMaintenanceWindowStartMinutes, int idleMaintenanceWindowEndMinutes, int idleMaintenanceMinIdleMinutes, bool idleMaintenanceRequireAcPower
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
@pragma('vm:prefer-inline') @override $Res call({Object? llmProvider = null,Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? reasoningEffort = null,Object? memoryExtractionModel = null,Object? subagentModel = null,Object? goalSuggestionModel = null,Object? approvalAutoReviewModel = null,Object? memoryExtractionEndpointId = null,Object? subagentEndpointId = null,Object? goalSuggestionEndpointId = null,Object? approvalAutoReviewEndpointId = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? externalSettingsSyncEnabled = null,Object? externalSettingsPath = null,Object? externalToolHooksEnabled = null,Object? externalToolHooks = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? codingApprovalMode = null,Object? chatApprovalMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? enableCodingVerificationFeedback = null,Object? codingVerificationTriggerPolicy = null,Object? codingVerificationTimeoutSeconds = null,Object? codingVerificationMaxFailures = null,Object? enableAgentsMd = null,Object? enablePrefixStableToolLoop = null,Object? enableSemanticSearch = null,Object? embeddingsModel = null,Object? showMemoryUpdates = null,Object? enableLlmSessionLogs = null,Object? feedbackUploadEnabled = null,Object? feedbackEndpointUrl = null,Object? demoMode = null,Object? onboardingCompleted = null,Object? browserToolsEnabled = null,Object? disabledBuiltInTools = null,Object? localCommandPermissionRules = null,Object? routineComputerUseActionAllowlist = null,Object? modelCapabilityProfiles = null,Object? modelHarnessConfigs = null,Object? modelCapabilityProfileRevisions = null,Object? namedEndpoints = null,Object? idleMaintenanceEnabled = null,Object? idleMaintenanceWindowStartMinutes = null,Object? idleMaintenanceWindowEndMinutes = null,Object? idleMaintenanceMinIdleMinutes = null,Object? idleMaintenanceRequireAcPower = null,}) {
  return _then(_self.copyWith(
llmProvider: null == llmProvider ? _self.llmProvider : llmProvider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningEffort: null == reasoningEffort ? _self.reasoningEffort : reasoningEffort // ignore: cast_nullable_to_non_nullable
as ReasoningEffortPreference,memoryExtractionModel: null == memoryExtractionModel ? _self.memoryExtractionModel : memoryExtractionModel // ignore: cast_nullable_to_non_nullable
as String,subagentModel: null == subagentModel ? _self.subagentModel : subagentModel // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionModel: null == goalSuggestionModel ? _self.goalSuggestionModel : goalSuggestionModel // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewModel: null == approvalAutoReviewModel ? _self.approvalAutoReviewModel : approvalAutoReviewModel // ignore: cast_nullable_to_non_nullable
as String,memoryExtractionEndpointId: null == memoryExtractionEndpointId ? _self.memoryExtractionEndpointId : memoryExtractionEndpointId // ignore: cast_nullable_to_non_nullable
as String,subagentEndpointId: null == subagentEndpointId ? _self.subagentEndpointId : subagentEndpointId // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionEndpointId: null == goalSuggestionEndpointId ? _self.goalSuggestionEndpointId : goalSuggestionEndpointId // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewEndpointId: null == approvalAutoReviewEndpointId ? _self.approvalAutoReviewEndpointId : approvalAutoReviewEndpointId // ignore: cast_nullable_to_non_nullable
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
as String,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
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
as bool,enablePrefixStableToolLoop: null == enablePrefixStableToolLoop ? _self.enablePrefixStableToolLoop : enablePrefixStableToolLoop // ignore: cast_nullable_to_non_nullable
as bool,enableSemanticSearch: null == enableSemanticSearch ? _self.enableSemanticSearch : enableSemanticSearch // ignore: cast_nullable_to_non_nullable
as bool,embeddingsModel: null == embeddingsModel ? _self.embeddingsModel : embeddingsModel // ignore: cast_nullable_to_non_nullable
as String,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,enableLlmSessionLogs: null == enableLlmSessionLogs ? _self.enableLlmSessionLogs : enableLlmSessionLogs // ignore: cast_nullable_to_non_nullable
as bool,feedbackUploadEnabled: null == feedbackUploadEnabled ? _self.feedbackUploadEnabled : feedbackUploadEnabled // ignore: cast_nullable_to_non_nullable
as bool,feedbackEndpointUrl: null == feedbackEndpointUrl ? _self.feedbackEndpointUrl : feedbackEndpointUrl // ignore: cast_nullable_to_non_nullable
as String,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,onboardingCompleted: null == onboardingCompleted ? _self.onboardingCompleted : onboardingCompleted // ignore: cast_nullable_to_non_nullable
as bool,browserToolsEnabled: null == browserToolsEnabled ? _self.browserToolsEnabled : browserToolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self.disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,localCommandPermissionRules: null == localCommandPermissionRules ? _self.localCommandPermissionRules : localCommandPermissionRules // ignore: cast_nullable_to_non_nullable
as List<LocalCommandPermissionRule>,routineComputerUseActionAllowlist: null == routineComputerUseActionAllowlist ? _self.routineComputerUseActionAllowlist : routineComputerUseActionAllowlist // ignore: cast_nullable_to_non_nullable
as List<RoutineComputerUseActionAllowlistEntry>,modelCapabilityProfiles: null == modelCapabilityProfiles ? _self.modelCapabilityProfiles : modelCapabilityProfiles // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfile>,modelHarnessConfigs: null == modelHarnessConfigs ? _self.modelHarnessConfigs : modelHarnessConfigs // ignore: cast_nullable_to_non_nullable
as List<ModelHarnessConfig>,modelCapabilityProfileRevisions: null == modelCapabilityProfileRevisions ? _self.modelCapabilityProfileRevisions : modelCapabilityProfileRevisions // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfileRevision>,namedEndpoints: null == namedEndpoints ? _self.namedEndpoints : namedEndpoints // ignore: cast_nullable_to_non_nullable
as List<NamedEndpoint>,idleMaintenanceEnabled: null == idleMaintenanceEnabled ? _self.idleMaintenanceEnabled : idleMaintenanceEnabled // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider llmProvider,  String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  String memoryExtractionModel,  String subagentModel,  String goalSuggestionModel,  String approvalAutoReviewModel,  String memoryExtractionEndpointId,  String subagentEndpointId,  String goalSuggestionEndpointId,  String approvalAutoReviewEndpointId,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool externalSettingsSyncEnabled,  String externalSettingsPath,  bool externalToolHooksEnabled, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode codingApprovalMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode chatApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool enableCodingVerificationFeedback, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim)  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,  int codingVerificationTimeoutSeconds,  int codingVerificationMaxFailures,  bool enableAgentsMd,  bool enablePrefixStableToolLoop,  bool enableSemanticSearch,  String embeddingsModel,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool feedbackUploadEnabled,  String feedbackEndpointUrl,  bool demoMode,  bool onboardingCompleted,  bool browserToolsEnabled,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist, @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles, @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs, @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions, @JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson)  List<NamedEndpoint> namedEndpoints,  bool idleMaintenanceEnabled,  int idleMaintenanceWindowStartMinutes,  int idleMaintenanceWindowEndMinutes,  int idleMaintenanceMinIdleMinutes,  bool idleMaintenanceRequireAcPower)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.llmProvider,_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.memoryExtractionModel,_that.subagentModel,_that.goalSuggestionModel,_that.approvalAutoReviewModel,_that.memoryExtractionEndpointId,_that.subagentEndpointId,_that.goalSuggestionEndpointId,_that.approvalAutoReviewEndpointId,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.externalSettingsSyncEnabled,_that.externalSettingsPath,_that.externalToolHooksEnabled,_that.externalToolHooks,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.codingApprovalMode,_that.chatApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.enableCodingVerificationFeedback,_that.codingVerificationTriggerPolicy,_that.codingVerificationTimeoutSeconds,_that.codingVerificationMaxFailures,_that.enableAgentsMd,_that.enablePrefixStableToolLoop,_that.enableSemanticSearch,_that.embeddingsModel,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.feedbackUploadEnabled,_that.feedbackEndpointUrl,_that.demoMode,_that.onboardingCompleted,_that.browserToolsEnabled,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist,_that.modelCapabilityProfiles,_that.modelHarnessConfigs,_that.modelCapabilityProfileRevisions,_that.namedEndpoints,_that.idleMaintenanceEnabled,_that.idleMaintenanceWindowStartMinutes,_that.idleMaintenanceWindowEndMinutes,_that.idleMaintenanceMinIdleMinutes,_that.idleMaintenanceRequireAcPower);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider llmProvider,  String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  String memoryExtractionModel,  String subagentModel,  String goalSuggestionModel,  String approvalAutoReviewModel,  String memoryExtractionEndpointId,  String subagentEndpointId,  String goalSuggestionEndpointId,  String approvalAutoReviewEndpointId,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool externalSettingsSyncEnabled,  String externalSettingsPath,  bool externalToolHooksEnabled, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode codingApprovalMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode chatApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool enableCodingVerificationFeedback, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim)  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,  int codingVerificationTimeoutSeconds,  int codingVerificationMaxFailures,  bool enableAgentsMd,  bool enablePrefixStableToolLoop,  bool enableSemanticSearch,  String embeddingsModel,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool feedbackUploadEnabled,  String feedbackEndpointUrl,  bool demoMode,  bool onboardingCompleted,  bool browserToolsEnabled,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist, @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles, @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs, @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions, @JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson)  List<NamedEndpoint> namedEndpoints,  bool idleMaintenanceEnabled,  int idleMaintenanceWindowStartMinutes,  int idleMaintenanceWindowEndMinutes,  int idleMaintenanceMinIdleMinutes,  bool idleMaintenanceRequireAcPower)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.llmProvider,_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.memoryExtractionModel,_that.subagentModel,_that.goalSuggestionModel,_that.approvalAutoReviewModel,_that.memoryExtractionEndpointId,_that.subagentEndpointId,_that.goalSuggestionEndpointId,_that.approvalAutoReviewEndpointId,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.externalSettingsSyncEnabled,_that.externalSettingsPath,_that.externalToolHooksEnabled,_that.externalToolHooks,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.codingApprovalMode,_that.chatApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.enableCodingVerificationFeedback,_that.codingVerificationTriggerPolicy,_that.codingVerificationTimeoutSeconds,_that.codingVerificationMaxFailures,_that.enableAgentsMd,_that.enablePrefixStableToolLoop,_that.enableSemanticSearch,_that.embeddingsModel,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.feedbackUploadEnabled,_that.feedbackEndpointUrl,_that.demoMode,_that.onboardingCompleted,_that.browserToolsEnabled,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist,_that.modelCapabilityProfiles,_that.modelHarnessConfigs,_that.modelCapabilityProfileRevisions,_that.namedEndpoints,_that.idleMaintenanceEnabled,_that.idleMaintenanceWindowStartMinutes,_that.idleMaintenanceWindowEndMinutes,_that.idleMaintenanceMinIdleMinutes,_that.idleMaintenanceRequireAcPower);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)  LlmProvider llmProvider,  String baseUrl,  String model,  String apiKey,  double temperature,  int maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)  ReasoningEffortPreference reasoningEffort,  String memoryExtractionModel,  String subagentModel,  String goalSuggestionModel,  String approvalAutoReviewModel,  String memoryExtractionEndpointId,  String subagentEndpointId,  String goalSuggestionEndpointId,  String approvalAutoReviewEndpointId,  String googleChatWebhookUrl,  String mcpUrl,  List<String> mcpUrls,  List<McpServerConfig> mcpServers,  bool mcpEnabled,  bool externalSettingsSyncEnabled,  String externalSettingsPath,  bool externalToolHooksEnabled, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson)  List<ExternalToolHook> externalToolHooks,  bool ttsEnabled,  bool autoReadEnabled,  double speechRate,  bool voiceModeAutoStop,  String whisperUrl,  String voicevoxUrl,  int voicevoxSpeakerId,  String language, @JsonKey(unknownEnumValue: AssistantMode.general)  AssistantMode assistantMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode codingApprovalMode, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode chatApprovalMode,  bool confirmFileMutations,  bool confirmLocalCommands,  bool confirmGitWrites,  bool enableCodingVerificationFeedback, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim)  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,  int codingVerificationTimeoutSeconds,  int codingVerificationMaxFailures,  bool enableAgentsMd,  bool enablePrefixStableToolLoop,  bool enableSemanticSearch,  String embeddingsModel,  bool showMemoryUpdates,  bool enableLlmSessionLogs,  bool feedbackUploadEnabled,  String feedbackEndpointUrl,  bool demoMode,  bool onboardingCompleted,  bool browserToolsEnabled,  List<String> disabledBuiltInTools,  List<LocalCommandPermissionRule> localCommandPermissionRules,  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist, @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson)  List<ModelCapabilityProfile> modelCapabilityProfiles, @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson)  List<ModelHarnessConfig> modelHarnessConfigs, @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson)  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions, @JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson)  List<NamedEndpoint> namedEndpoints,  bool idleMaintenanceEnabled,  int idleMaintenanceWindowStartMinutes,  int idleMaintenanceWindowEndMinutes,  int idleMaintenanceMinIdleMinutes,  bool idleMaintenanceRequireAcPower)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.llmProvider,_that.baseUrl,_that.model,_that.apiKey,_that.temperature,_that.maxTokens,_that.reasoningEffort,_that.memoryExtractionModel,_that.subagentModel,_that.goalSuggestionModel,_that.approvalAutoReviewModel,_that.memoryExtractionEndpointId,_that.subagentEndpointId,_that.goalSuggestionEndpointId,_that.approvalAutoReviewEndpointId,_that.googleChatWebhookUrl,_that.mcpUrl,_that.mcpUrls,_that.mcpServers,_that.mcpEnabled,_that.externalSettingsSyncEnabled,_that.externalSettingsPath,_that.externalToolHooksEnabled,_that.externalToolHooks,_that.ttsEnabled,_that.autoReadEnabled,_that.speechRate,_that.voiceModeAutoStop,_that.whisperUrl,_that.voicevoxUrl,_that.voicevoxSpeakerId,_that.language,_that.assistantMode,_that.codingApprovalMode,_that.chatApprovalMode,_that.confirmFileMutations,_that.confirmLocalCommands,_that.confirmGitWrites,_that.enableCodingVerificationFeedback,_that.codingVerificationTriggerPolicy,_that.codingVerificationTimeoutSeconds,_that.codingVerificationMaxFailures,_that.enableAgentsMd,_that.enablePrefixStableToolLoop,_that.enableSemanticSearch,_that.embeddingsModel,_that.showMemoryUpdates,_that.enableLlmSessionLogs,_that.feedbackUploadEnabled,_that.feedbackEndpointUrl,_that.demoMode,_that.onboardingCompleted,_that.browserToolsEnabled,_that.disabledBuiltInTools,_that.localCommandPermissionRules,_that.routineComputerUseActionAllowlist,_that.modelCapabilityProfiles,_that.modelHarnessConfigs,_that.modelCapabilityProfileRevisions,_that.namedEndpoints,_that.idleMaintenanceEnabled,_that.idleMaintenanceWindowStartMinutes,_that.idleMaintenanceWindowEndMinutes,_that.idleMaintenanceMinIdleMinutes,_that.idleMaintenanceRequireAcPower);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppSettings extends AppSettings {
  const _AppSettings({@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) this.llmProvider = LlmProvider.openAiCompatible, required this.baseUrl, required this.model, required this.apiKey, required this.temperature, required this.maxTokens, @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) this.reasoningEffort = ReasoningEffortPreference.automatic, this.memoryExtractionModel = '', this.subagentModel = '', this.goalSuggestionModel = '', this.approvalAutoReviewModel = '', this.memoryExtractionEndpointId = '', this.subagentEndpointId = '', this.goalSuggestionEndpointId = '', this.approvalAutoReviewEndpointId = '', this.googleChatWebhookUrl = '', this.mcpUrl = '', final  List<String> mcpUrls = const <String>[], final  List<McpServerConfig> mcpServers = const <McpServerConfig>[], this.mcpEnabled = false, this.externalSettingsSyncEnabled = false, this.externalSettingsPath = '~/.caverno/config.json', this.externalToolHooksEnabled = false, @JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) final  List<ExternalToolHook> externalToolHooks = const <ExternalToolHook>[], this.ttsEnabled = true, this.autoReadEnabled = false, this.speechRate = 0.5, this.voiceModeAutoStop = true, this.whisperUrl = 'http://localhost:8080', this.voicevoxUrl = 'http://localhost:50021', this.voicevoxSpeakerId = 0, this.language = 'system', @JsonKey(unknownEnumValue: AssistantMode.general) this.assistantMode = AssistantMode.general, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) this.codingApprovalMode = ToolApprovalMode.defaultPermissions, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) this.chatApprovalMode = ToolApprovalMode.defaultPermissions, this.confirmFileMutations = true, this.confirmLocalCommands = true, this.confirmGitWrites = true, this.enableCodingVerificationFeedback = true, @JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) this.codingVerificationTriggerPolicy = CodingVerificationTriggerPolicy.onCompletionClaim, this.codingVerificationTimeoutSeconds = 90, this.codingVerificationMaxFailures = 5, this.enableAgentsMd = true, this.enablePrefixStableToolLoop = false, this.enableSemanticSearch = false, this.embeddingsModel = '', this.showMemoryUpdates = false, this.enableLlmSessionLogs = false, this.feedbackUploadEnabled = true, this.feedbackEndpointUrl = defaultFeedbackEndpointUrl, this.demoMode = false, this.onboardingCompleted = false, this.browserToolsEnabled = false, final  List<String> disabledBuiltInTools = const <String>[], final  List<LocalCommandPermissionRule> localCommandPermissionRules = const <LocalCommandPermissionRule>[], final  List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist = const <RoutineComputerUseActionAllowlistEntry>[], @JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) final  List<ModelCapabilityProfile> modelCapabilityProfiles = const <ModelCapabilityProfile>[], @JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) final  List<ModelHarnessConfig> modelHarnessConfigs = const <ModelHarnessConfig>[], @JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) final  List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions = const <ModelCapabilityProfileRevision>[], @JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson) final  List<NamedEndpoint> namedEndpoints = const <NamedEndpoint>[], this.idleMaintenanceEnabled = false, this.idleMaintenanceWindowStartMinutes = 120, this.idleMaintenanceWindowEndMinutes = 360, this.idleMaintenanceMinIdleMinutes = 10, this.idleMaintenanceRequireAcPower = true}): _mcpUrls = mcpUrls,_mcpServers = mcpServers,_externalToolHooks = externalToolHooks,_disabledBuiltInTools = disabledBuiltInTools,_localCommandPermissionRules = localCommandPermissionRules,_routineComputerUseActionAllowlist = routineComputerUseActionAllowlist,_modelCapabilityProfiles = modelCapabilityProfiles,_modelHarnessConfigs = modelHarnessConfigs,_modelCapabilityProfileRevisions = modelCapabilityProfileRevisions,_namedEndpoints = namedEndpoints,super._();
  factory _AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);

@override@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) final  LlmProvider llmProvider;
@override final  String baseUrl;
@override final  String model;
@override final  String apiKey;
@override final  double temperature;
@override final  int maxTokens;
@override@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) final  ReasoningEffortPreference reasoningEffort;
// Per-role model routing (LL1). Empty string means "use the main model".
// Lets secondary LLM calls run on a smaller, faster local model.
@override@JsonKey() final  String memoryExtractionModel;
@override@JsonKey() final  String subagentModel;
@override@JsonKey() final  String goalSuggestionModel;
@override@JsonKey() final  String approvalAutoReviewModel;
// LL8 per-role endpoint routing. Empty string means "use the primary
// endpoint". A non-empty value is a NamedEndpoint id; an unreachable mesh
// endpoint falls back to the primary at call time (MeshEndpointRouter).
@override@JsonKey() final  String memoryExtractionEndpointId;
@override@JsonKey() final  String subagentEndpointId;
@override@JsonKey() final  String goalSuggestionEndpointId;
@override@JsonKey() final  String approvalAutoReviewEndpointId;
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
@override@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) final  ToolApprovalMode codingApprovalMode;
// Approval policy for chat-mode built-in browser automation. Reuses the
// shared [ToolApprovalMode] levels but is independent from coding writes.
@override@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) final  ToolApprovalMode chatApprovalMode;
@override@JsonKey() final  bool confirmFileMutations;
@override@JsonKey() final  bool confirmLocalCommands;
@override@JsonKey() final  bool confirmGitWrites;
@override@JsonKey() final  bool enableCodingVerificationFeedback;
@override@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) final  CodingVerificationTriggerPolicy codingVerificationTriggerPolicy;
@override@JsonKey() final  int codingVerificationTimeoutSeconds;
@override@JsonKey() final  int codingVerificationMaxFailures;
@override@JsonKey() final  bool enableAgentsMd;
@override@JsonKey() final  bool enablePrefixStableToolLoop;
// LL5: opt-in local semantic search. When enabled and an embeddings model
// is configured, conversation history is embedded for semantic search;
// otherwise search degrades to lexical FTS.
@override@JsonKey() final  bool enableSemanticSearch;
@override@JsonKey() final  String embeddingsModel;
@override@JsonKey() final  bool showMemoryUpdates;
@override@JsonKey() final  bool enableLlmSessionLogs;
@override@JsonKey() final  bool feedbackUploadEnabled;
@override@JsonKey() final  String feedbackEndpointUrl;
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

// LL8: user-registered LAN inference endpoints (the mesh). Discovery only
// proposes candidates; entries here are explicitly registered.
 final  List<NamedEndpoint> _namedEndpoints;
// LL8: user-registered LAN inference endpoints (the mesh). Discovery only
// proposes candidates; entries here are explicitly registered.
@override@JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson) List<NamedEndpoint> get namedEndpoints {
  if (_namedEndpoints is EqualUnmodifiableListView) return _namedEndpoints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_namedEndpoints);
}

// LL18 idle/overnight maintenance gating (consumed via the maintenance
// feature's IdleMaintenanceConfig; minutes are since local midnight).
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.llmProvider, llmProvider) || other.llmProvider == llmProvider)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.model, model) || other.model == model)&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.reasoningEffort, reasoningEffort) || other.reasoningEffort == reasoningEffort)&&(identical(other.memoryExtractionModel, memoryExtractionModel) || other.memoryExtractionModel == memoryExtractionModel)&&(identical(other.subagentModel, subagentModel) || other.subagentModel == subagentModel)&&(identical(other.goalSuggestionModel, goalSuggestionModel) || other.goalSuggestionModel == goalSuggestionModel)&&(identical(other.approvalAutoReviewModel, approvalAutoReviewModel) || other.approvalAutoReviewModel == approvalAutoReviewModel)&&(identical(other.memoryExtractionEndpointId, memoryExtractionEndpointId) || other.memoryExtractionEndpointId == memoryExtractionEndpointId)&&(identical(other.subagentEndpointId, subagentEndpointId) || other.subagentEndpointId == subagentEndpointId)&&(identical(other.goalSuggestionEndpointId, goalSuggestionEndpointId) || other.goalSuggestionEndpointId == goalSuggestionEndpointId)&&(identical(other.approvalAutoReviewEndpointId, approvalAutoReviewEndpointId) || other.approvalAutoReviewEndpointId == approvalAutoReviewEndpointId)&&(identical(other.googleChatWebhookUrl, googleChatWebhookUrl) || other.googleChatWebhookUrl == googleChatWebhookUrl)&&(identical(other.mcpUrl, mcpUrl) || other.mcpUrl == mcpUrl)&&const DeepCollectionEquality().equals(other._mcpUrls, _mcpUrls)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&(identical(other.mcpEnabled, mcpEnabled) || other.mcpEnabled == mcpEnabled)&&(identical(other.externalSettingsSyncEnabled, externalSettingsSyncEnabled) || other.externalSettingsSyncEnabled == externalSettingsSyncEnabled)&&(identical(other.externalSettingsPath, externalSettingsPath) || other.externalSettingsPath == externalSettingsPath)&&(identical(other.externalToolHooksEnabled, externalToolHooksEnabled) || other.externalToolHooksEnabled == externalToolHooksEnabled)&&const DeepCollectionEquality().equals(other._externalToolHooks, _externalToolHooks)&&(identical(other.ttsEnabled, ttsEnabled) || other.ttsEnabled == ttsEnabled)&&(identical(other.autoReadEnabled, autoReadEnabled) || other.autoReadEnabled == autoReadEnabled)&&(identical(other.speechRate, speechRate) || other.speechRate == speechRate)&&(identical(other.voiceModeAutoStop, voiceModeAutoStop) || other.voiceModeAutoStop == voiceModeAutoStop)&&(identical(other.whisperUrl, whisperUrl) || other.whisperUrl == whisperUrl)&&(identical(other.voicevoxUrl, voicevoxUrl) || other.voicevoxUrl == voicevoxUrl)&&(identical(other.voicevoxSpeakerId, voicevoxSpeakerId) || other.voicevoxSpeakerId == voicevoxSpeakerId)&&(identical(other.language, language) || other.language == language)&&(identical(other.assistantMode, assistantMode) || other.assistantMode == assistantMode)&&(identical(other.codingApprovalMode, codingApprovalMode) || other.codingApprovalMode == codingApprovalMode)&&(identical(other.chatApprovalMode, chatApprovalMode) || other.chatApprovalMode == chatApprovalMode)&&(identical(other.confirmFileMutations, confirmFileMutations) || other.confirmFileMutations == confirmFileMutations)&&(identical(other.confirmLocalCommands, confirmLocalCommands) || other.confirmLocalCommands == confirmLocalCommands)&&(identical(other.confirmGitWrites, confirmGitWrites) || other.confirmGitWrites == confirmGitWrites)&&(identical(other.enableCodingVerificationFeedback, enableCodingVerificationFeedback) || other.enableCodingVerificationFeedback == enableCodingVerificationFeedback)&&(identical(other.codingVerificationTriggerPolicy, codingVerificationTriggerPolicy) || other.codingVerificationTriggerPolicy == codingVerificationTriggerPolicy)&&(identical(other.codingVerificationTimeoutSeconds, codingVerificationTimeoutSeconds) || other.codingVerificationTimeoutSeconds == codingVerificationTimeoutSeconds)&&(identical(other.codingVerificationMaxFailures, codingVerificationMaxFailures) || other.codingVerificationMaxFailures == codingVerificationMaxFailures)&&(identical(other.enableAgentsMd, enableAgentsMd) || other.enableAgentsMd == enableAgentsMd)&&(identical(other.enablePrefixStableToolLoop, enablePrefixStableToolLoop) || other.enablePrefixStableToolLoop == enablePrefixStableToolLoop)&&(identical(other.enableSemanticSearch, enableSemanticSearch) || other.enableSemanticSearch == enableSemanticSearch)&&(identical(other.embeddingsModel, embeddingsModel) || other.embeddingsModel == embeddingsModel)&&(identical(other.showMemoryUpdates, showMemoryUpdates) || other.showMemoryUpdates == showMemoryUpdates)&&(identical(other.enableLlmSessionLogs, enableLlmSessionLogs) || other.enableLlmSessionLogs == enableLlmSessionLogs)&&(identical(other.feedbackUploadEnabled, feedbackUploadEnabled) || other.feedbackUploadEnabled == feedbackUploadEnabled)&&(identical(other.feedbackEndpointUrl, feedbackEndpointUrl) || other.feedbackEndpointUrl == feedbackEndpointUrl)&&(identical(other.demoMode, demoMode) || other.demoMode == demoMode)&&(identical(other.onboardingCompleted, onboardingCompleted) || other.onboardingCompleted == onboardingCompleted)&&(identical(other.browserToolsEnabled, browserToolsEnabled) || other.browserToolsEnabled == browserToolsEnabled)&&const DeepCollectionEquality().equals(other._disabledBuiltInTools, _disabledBuiltInTools)&&const DeepCollectionEquality().equals(other._localCommandPermissionRules, _localCommandPermissionRules)&&const DeepCollectionEquality().equals(other._routineComputerUseActionAllowlist, _routineComputerUseActionAllowlist)&&const DeepCollectionEquality().equals(other._modelCapabilityProfiles, _modelCapabilityProfiles)&&const DeepCollectionEquality().equals(other._modelHarnessConfigs, _modelHarnessConfigs)&&const DeepCollectionEquality().equals(other._modelCapabilityProfileRevisions, _modelCapabilityProfileRevisions)&&const DeepCollectionEquality().equals(other._namedEndpoints, _namedEndpoints)&&(identical(other.idleMaintenanceEnabled, idleMaintenanceEnabled) || other.idleMaintenanceEnabled == idleMaintenanceEnabled)&&(identical(other.idleMaintenanceWindowStartMinutes, idleMaintenanceWindowStartMinutes) || other.idleMaintenanceWindowStartMinutes == idleMaintenanceWindowStartMinutes)&&(identical(other.idleMaintenanceWindowEndMinutes, idleMaintenanceWindowEndMinutes) || other.idleMaintenanceWindowEndMinutes == idleMaintenanceWindowEndMinutes)&&(identical(other.idleMaintenanceMinIdleMinutes, idleMaintenanceMinIdleMinutes) || other.idleMaintenanceMinIdleMinutes == idleMaintenanceMinIdleMinutes)&&(identical(other.idleMaintenanceRequireAcPower, idleMaintenanceRequireAcPower) || other.idleMaintenanceRequireAcPower == idleMaintenanceRequireAcPower));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,llmProvider,baseUrl,model,apiKey,temperature,maxTokens,reasoningEffort,memoryExtractionModel,subagentModel,goalSuggestionModel,approvalAutoReviewModel,memoryExtractionEndpointId,subagentEndpointId,goalSuggestionEndpointId,approvalAutoReviewEndpointId,googleChatWebhookUrl,mcpUrl,const DeepCollectionEquality().hash(_mcpUrls),const DeepCollectionEquality().hash(_mcpServers),mcpEnabled,externalSettingsSyncEnabled,externalSettingsPath,externalToolHooksEnabled,const DeepCollectionEquality().hash(_externalToolHooks),ttsEnabled,autoReadEnabled,speechRate,voiceModeAutoStop,whisperUrl,voicevoxUrl,voicevoxSpeakerId,language,assistantMode,codingApprovalMode,chatApprovalMode,confirmFileMutations,confirmLocalCommands,confirmGitWrites,enableCodingVerificationFeedback,codingVerificationTriggerPolicy,codingVerificationTimeoutSeconds,codingVerificationMaxFailures,enableAgentsMd,enablePrefixStableToolLoop,enableSemanticSearch,embeddingsModel,showMemoryUpdates,enableLlmSessionLogs,feedbackUploadEnabled,feedbackEndpointUrl,demoMode,onboardingCompleted,browserToolsEnabled,const DeepCollectionEquality().hash(_disabledBuiltInTools),const DeepCollectionEquality().hash(_localCommandPermissionRules),const DeepCollectionEquality().hash(_routineComputerUseActionAllowlist),const DeepCollectionEquality().hash(_modelCapabilityProfiles),const DeepCollectionEquality().hash(_modelHarnessConfigs),const DeepCollectionEquality().hash(_modelCapabilityProfileRevisions),const DeepCollectionEquality().hash(_namedEndpoints),idleMaintenanceEnabled,idleMaintenanceWindowStartMinutes,idleMaintenanceWindowEndMinutes,idleMaintenanceMinIdleMinutes,idleMaintenanceRequireAcPower]);

@override
String toString() {
  return 'AppSettings(llmProvider: $llmProvider, baseUrl: $baseUrl, model: $model, apiKey: $apiKey, temperature: $temperature, maxTokens: $maxTokens, reasoningEffort: $reasoningEffort, memoryExtractionModel: $memoryExtractionModel, subagentModel: $subagentModel, goalSuggestionModel: $goalSuggestionModel, approvalAutoReviewModel: $approvalAutoReviewModel, memoryExtractionEndpointId: $memoryExtractionEndpointId, subagentEndpointId: $subagentEndpointId, goalSuggestionEndpointId: $goalSuggestionEndpointId, approvalAutoReviewEndpointId: $approvalAutoReviewEndpointId, googleChatWebhookUrl: $googleChatWebhookUrl, mcpUrl: $mcpUrl, mcpUrls: $mcpUrls, mcpServers: $mcpServers, mcpEnabled: $mcpEnabled, externalSettingsSyncEnabled: $externalSettingsSyncEnabled, externalSettingsPath: $externalSettingsPath, externalToolHooksEnabled: $externalToolHooksEnabled, externalToolHooks: $externalToolHooks, ttsEnabled: $ttsEnabled, autoReadEnabled: $autoReadEnabled, speechRate: $speechRate, voiceModeAutoStop: $voiceModeAutoStop, whisperUrl: $whisperUrl, voicevoxUrl: $voicevoxUrl, voicevoxSpeakerId: $voicevoxSpeakerId, language: $language, assistantMode: $assistantMode, codingApprovalMode: $codingApprovalMode, chatApprovalMode: $chatApprovalMode, confirmFileMutations: $confirmFileMutations, confirmLocalCommands: $confirmLocalCommands, confirmGitWrites: $confirmGitWrites, enableCodingVerificationFeedback: $enableCodingVerificationFeedback, codingVerificationTriggerPolicy: $codingVerificationTriggerPolicy, codingVerificationTimeoutSeconds: $codingVerificationTimeoutSeconds, codingVerificationMaxFailures: $codingVerificationMaxFailures, enableAgentsMd: $enableAgentsMd, enablePrefixStableToolLoop: $enablePrefixStableToolLoop, enableSemanticSearch: $enableSemanticSearch, embeddingsModel: $embeddingsModel, showMemoryUpdates: $showMemoryUpdates, enableLlmSessionLogs: $enableLlmSessionLogs, feedbackUploadEnabled: $feedbackUploadEnabled, feedbackEndpointUrl: $feedbackEndpointUrl, demoMode: $demoMode, onboardingCompleted: $onboardingCompleted, browserToolsEnabled: $browserToolsEnabled, disabledBuiltInTools: $disabledBuiltInTools, localCommandPermissionRules: $localCommandPermissionRules, routineComputerUseActionAllowlist: $routineComputerUseActionAllowlist, modelCapabilityProfiles: $modelCapabilityProfiles, modelHarnessConfigs: $modelHarnessConfigs, modelCapabilityProfileRevisions: $modelCapabilityProfileRevisions, namedEndpoints: $namedEndpoints, idleMaintenanceEnabled: $idleMaintenanceEnabled, idleMaintenanceWindowStartMinutes: $idleMaintenanceWindowStartMinutes, idleMaintenanceWindowEndMinutes: $idleMaintenanceWindowEndMinutes, idleMaintenanceMinIdleMinutes: $idleMaintenanceMinIdleMinutes, idleMaintenanceRequireAcPower: $idleMaintenanceRequireAcPower)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(unknownEnumValue: LlmProvider.openAiCompatible) LlmProvider llmProvider, String baseUrl, String model, String apiKey, double temperature, int maxTokens,@JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic) ReasoningEffortPreference reasoningEffort, String memoryExtractionModel, String subagentModel, String goalSuggestionModel, String approvalAutoReviewModel, String memoryExtractionEndpointId, String subagentEndpointId, String goalSuggestionEndpointId, String approvalAutoReviewEndpointId, String googleChatWebhookUrl, String mcpUrl, List<String> mcpUrls, List<McpServerConfig> mcpServers, bool mcpEnabled, bool externalSettingsSyncEnabled, String externalSettingsPath, bool externalToolHooksEnabled,@JsonKey(fromJson: _externalToolHooksFromJson, toJson: _externalToolHooksToJson) List<ExternalToolHook> externalToolHooks, bool ttsEnabled, bool autoReadEnabled, double speechRate, bool voiceModeAutoStop, String whisperUrl, String voicevoxUrl, int voicevoxSpeakerId, String language,@JsonKey(unknownEnumValue: AssistantMode.general) AssistantMode assistantMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode codingApprovalMode,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode chatApprovalMode, bool confirmFileMutations, bool confirmLocalCommands, bool confirmGitWrites, bool enableCodingVerificationFeedback,@JsonKey(unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim) CodingVerificationTriggerPolicy codingVerificationTriggerPolicy, int codingVerificationTimeoutSeconds, int codingVerificationMaxFailures, bool enableAgentsMd, bool enablePrefixStableToolLoop, bool enableSemanticSearch, String embeddingsModel, bool showMemoryUpdates, bool enableLlmSessionLogs, bool feedbackUploadEnabled, String feedbackEndpointUrl, bool demoMode, bool onboardingCompleted, bool browserToolsEnabled, List<String> disabledBuiltInTools, List<LocalCommandPermissionRule> localCommandPermissionRules, List<RoutineComputerUseActionAllowlistEntry> routineComputerUseActionAllowlist,@JsonKey(fromJson: _modelCapabilityProfilesFromJson, toJson: _modelCapabilityProfilesToJson) List<ModelCapabilityProfile> modelCapabilityProfiles,@JsonKey(fromJson: _modelHarnessConfigsFromJson, toJson: _modelHarnessConfigsToJson) List<ModelHarnessConfig> modelHarnessConfigs,@JsonKey(fromJson: _profileRevisionsFromJson, toJson: _profileRevisionsToJson) List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions,@JsonKey(fromJson: _namedEndpointsFromJson, toJson: _namedEndpointsToJson) List<NamedEndpoint> namedEndpoints, bool idleMaintenanceEnabled, int idleMaintenanceWindowStartMinutes, int idleMaintenanceWindowEndMinutes, int idleMaintenanceMinIdleMinutes, bool idleMaintenanceRequireAcPower
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
@override @pragma('vm:prefer-inline') $Res call({Object? llmProvider = null,Object? baseUrl = null,Object? model = null,Object? apiKey = null,Object? temperature = null,Object? maxTokens = null,Object? reasoningEffort = null,Object? memoryExtractionModel = null,Object? subagentModel = null,Object? goalSuggestionModel = null,Object? approvalAutoReviewModel = null,Object? memoryExtractionEndpointId = null,Object? subagentEndpointId = null,Object? goalSuggestionEndpointId = null,Object? approvalAutoReviewEndpointId = null,Object? googleChatWebhookUrl = null,Object? mcpUrl = null,Object? mcpUrls = null,Object? mcpServers = null,Object? mcpEnabled = null,Object? externalSettingsSyncEnabled = null,Object? externalSettingsPath = null,Object? externalToolHooksEnabled = null,Object? externalToolHooks = null,Object? ttsEnabled = null,Object? autoReadEnabled = null,Object? speechRate = null,Object? voiceModeAutoStop = null,Object? whisperUrl = null,Object? voicevoxUrl = null,Object? voicevoxSpeakerId = null,Object? language = null,Object? assistantMode = null,Object? codingApprovalMode = null,Object? chatApprovalMode = null,Object? confirmFileMutations = null,Object? confirmLocalCommands = null,Object? confirmGitWrites = null,Object? enableCodingVerificationFeedback = null,Object? codingVerificationTriggerPolicy = null,Object? codingVerificationTimeoutSeconds = null,Object? codingVerificationMaxFailures = null,Object? enableAgentsMd = null,Object? enablePrefixStableToolLoop = null,Object? enableSemanticSearch = null,Object? embeddingsModel = null,Object? showMemoryUpdates = null,Object? enableLlmSessionLogs = null,Object? feedbackUploadEnabled = null,Object? feedbackEndpointUrl = null,Object? demoMode = null,Object? onboardingCompleted = null,Object? browserToolsEnabled = null,Object? disabledBuiltInTools = null,Object? localCommandPermissionRules = null,Object? routineComputerUseActionAllowlist = null,Object? modelCapabilityProfiles = null,Object? modelHarnessConfigs = null,Object? modelCapabilityProfileRevisions = null,Object? namedEndpoints = null,Object? idleMaintenanceEnabled = null,Object? idleMaintenanceWindowStartMinutes = null,Object? idleMaintenanceWindowEndMinutes = null,Object? idleMaintenanceMinIdleMinutes = null,Object? idleMaintenanceRequireAcPower = null,}) {
  return _then(_AppSettings(
llmProvider: null == llmProvider ? _self.llmProvider : llmProvider // ignore: cast_nullable_to_non_nullable
as LlmProvider,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningEffort: null == reasoningEffort ? _self.reasoningEffort : reasoningEffort // ignore: cast_nullable_to_non_nullable
as ReasoningEffortPreference,memoryExtractionModel: null == memoryExtractionModel ? _self.memoryExtractionModel : memoryExtractionModel // ignore: cast_nullable_to_non_nullable
as String,subagentModel: null == subagentModel ? _self.subagentModel : subagentModel // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionModel: null == goalSuggestionModel ? _self.goalSuggestionModel : goalSuggestionModel // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewModel: null == approvalAutoReviewModel ? _self.approvalAutoReviewModel : approvalAutoReviewModel // ignore: cast_nullable_to_non_nullable
as String,memoryExtractionEndpointId: null == memoryExtractionEndpointId ? _self.memoryExtractionEndpointId : memoryExtractionEndpointId // ignore: cast_nullable_to_non_nullable
as String,subagentEndpointId: null == subagentEndpointId ? _self.subagentEndpointId : subagentEndpointId // ignore: cast_nullable_to_non_nullable
as String,goalSuggestionEndpointId: null == goalSuggestionEndpointId ? _self.goalSuggestionEndpointId : goalSuggestionEndpointId // ignore: cast_nullable_to_non_nullable
as String,approvalAutoReviewEndpointId: null == approvalAutoReviewEndpointId ? _self.approvalAutoReviewEndpointId : approvalAutoReviewEndpointId // ignore: cast_nullable_to_non_nullable
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
as String,assistantMode: null == assistantMode ? _self.assistantMode : assistantMode // ignore: cast_nullable_to_non_nullable
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
as bool,enablePrefixStableToolLoop: null == enablePrefixStableToolLoop ? _self.enablePrefixStableToolLoop : enablePrefixStableToolLoop // ignore: cast_nullable_to_non_nullable
as bool,enableSemanticSearch: null == enableSemanticSearch ? _self.enableSemanticSearch : enableSemanticSearch // ignore: cast_nullable_to_non_nullable
as bool,embeddingsModel: null == embeddingsModel ? _self.embeddingsModel : embeddingsModel // ignore: cast_nullable_to_non_nullable
as String,showMemoryUpdates: null == showMemoryUpdates ? _self.showMemoryUpdates : showMemoryUpdates // ignore: cast_nullable_to_non_nullable
as bool,enableLlmSessionLogs: null == enableLlmSessionLogs ? _self.enableLlmSessionLogs : enableLlmSessionLogs // ignore: cast_nullable_to_non_nullable
as bool,feedbackUploadEnabled: null == feedbackUploadEnabled ? _self.feedbackUploadEnabled : feedbackUploadEnabled // ignore: cast_nullable_to_non_nullable
as bool,feedbackEndpointUrl: null == feedbackEndpointUrl ? _self.feedbackEndpointUrl : feedbackEndpointUrl // ignore: cast_nullable_to_non_nullable
as String,demoMode: null == demoMode ? _self.demoMode : demoMode // ignore: cast_nullable_to_non_nullable
as bool,onboardingCompleted: null == onboardingCompleted ? _self.onboardingCompleted : onboardingCompleted // ignore: cast_nullable_to_non_nullable
as bool,browserToolsEnabled: null == browserToolsEnabled ? _self.browserToolsEnabled : browserToolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,disabledBuiltInTools: null == disabledBuiltInTools ? _self._disabledBuiltInTools : disabledBuiltInTools // ignore: cast_nullable_to_non_nullable
as List<String>,localCommandPermissionRules: null == localCommandPermissionRules ? _self._localCommandPermissionRules : localCommandPermissionRules // ignore: cast_nullable_to_non_nullable
as List<LocalCommandPermissionRule>,routineComputerUseActionAllowlist: null == routineComputerUseActionAllowlist ? _self._routineComputerUseActionAllowlist : routineComputerUseActionAllowlist // ignore: cast_nullable_to_non_nullable
as List<RoutineComputerUseActionAllowlistEntry>,modelCapabilityProfiles: null == modelCapabilityProfiles ? _self._modelCapabilityProfiles : modelCapabilityProfiles // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfile>,modelHarnessConfigs: null == modelHarnessConfigs ? _self._modelHarnessConfigs : modelHarnessConfigs // ignore: cast_nullable_to_non_nullable
as List<ModelHarnessConfig>,modelCapabilityProfileRevisions: null == modelCapabilityProfileRevisions ? _self._modelCapabilityProfileRevisions : modelCapabilityProfileRevisions // ignore: cast_nullable_to_non_nullable
as List<ModelCapabilityProfileRevision>,namedEndpoints: null == namedEndpoints ? _self._namedEndpoints : namedEndpoints // ignore: cast_nullable_to_non_nullable
as List<NamedEndpoint>,idleMaintenanceEnabled: null == idleMaintenanceEnabled ? _self.idleMaintenanceEnabled : idleMaintenanceEnabled // ignore: cast_nullable_to_non_nullable
as bool,idleMaintenanceWindowStartMinutes: null == idleMaintenanceWindowStartMinutes ? _self.idleMaintenanceWindowStartMinutes : idleMaintenanceWindowStartMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceWindowEndMinutes: null == idleMaintenanceWindowEndMinutes ? _self.idleMaintenanceWindowEndMinutes : idleMaintenanceWindowEndMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceMinIdleMinutes: null == idleMaintenanceMinIdleMinutes ? _self.idleMaintenanceMinIdleMinutes : idleMaintenanceMinIdleMinutes // ignore: cast_nullable_to_non_nullable
as int,idleMaintenanceRequireAcPower: null == idleMaintenanceRequireAcPower ? _self.idleMaintenanceRequireAcPower : idleMaintenanceRequireAcPower // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
