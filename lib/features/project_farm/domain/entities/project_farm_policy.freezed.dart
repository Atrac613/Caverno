// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project_farm_policy.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProjectFarmPolicy {

 String get projectId; List<String> get allowedVerificationCommands; int get maxConcurrentTasks; DateTime get updatedAt;/// FARM5: the subset of [allowedVerificationCommands] the user declared as
/// not executing project code (e.g. analyze, a format check). Only these
/// may run unattended: a test run executes code the agent just wrote, so
/// it keeps a person in the loop. Declared, never inferred.
 List<String> get unattendedCommands;/// FARM5: whether idle-time maintenance may start runs on its own. Off
/// until the user turns it on.
 bool get autoRunEnabled;/// FARM5: unattended runs allowed per local day.
 int get dailyRunLimit;
/// Create a copy of ProjectFarmPolicy
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectFarmPolicyCopyWith<ProjectFarmPolicy> get copyWith => _$ProjectFarmPolicyCopyWithImpl<ProjectFarmPolicy>(this as ProjectFarmPolicy, _$identity);

  /// Serializes this ProjectFarmPolicy to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectFarmPolicy&&(identical(other.projectId, projectId) || other.projectId == projectId)&&const DeepCollectionEquality().equals(other.allowedVerificationCommands, allowedVerificationCommands)&&(identical(other.maxConcurrentTasks, maxConcurrentTasks) || other.maxConcurrentTasks == maxConcurrentTasks)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.unattendedCommands, unattendedCommands)&&(identical(other.autoRunEnabled, autoRunEnabled) || other.autoRunEnabled == autoRunEnabled)&&(identical(other.dailyRunLimit, dailyRunLimit) || other.dailyRunLimit == dailyRunLimit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,projectId,const DeepCollectionEquality().hash(allowedVerificationCommands),maxConcurrentTasks,updatedAt,const DeepCollectionEquality().hash(unattendedCommands),autoRunEnabled,dailyRunLimit);

@override
String toString() {
  return 'ProjectFarmPolicy(projectId: $projectId, allowedVerificationCommands: $allowedVerificationCommands, maxConcurrentTasks: $maxConcurrentTasks, updatedAt: $updatedAt, unattendedCommands: $unattendedCommands, autoRunEnabled: $autoRunEnabled, dailyRunLimit: $dailyRunLimit)';
}


}

/// @nodoc
abstract mixin class $ProjectFarmPolicyCopyWith<$Res>  {
  factory $ProjectFarmPolicyCopyWith(ProjectFarmPolicy value, $Res Function(ProjectFarmPolicy) _then) = _$ProjectFarmPolicyCopyWithImpl;
@useResult
$Res call({
 String projectId, List<String> allowedVerificationCommands, int maxConcurrentTasks, DateTime updatedAt, List<String> unattendedCommands, bool autoRunEnabled, int dailyRunLimit
});




}
/// @nodoc
class _$ProjectFarmPolicyCopyWithImpl<$Res>
    implements $ProjectFarmPolicyCopyWith<$Res> {
  _$ProjectFarmPolicyCopyWithImpl(this._self, this._then);

  final ProjectFarmPolicy _self;
  final $Res Function(ProjectFarmPolicy) _then;

/// Create a copy of ProjectFarmPolicy
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? allowedVerificationCommands = null,Object? maxConcurrentTasks = null,Object? updatedAt = null,Object? unattendedCommands = null,Object? autoRunEnabled = null,Object? dailyRunLimit = null,}) {
  return _then(_self.copyWith(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,allowedVerificationCommands: null == allowedVerificationCommands ? _self.allowedVerificationCommands : allowedVerificationCommands // ignore: cast_nullable_to_non_nullable
as List<String>,maxConcurrentTasks: null == maxConcurrentTasks ? _self.maxConcurrentTasks : maxConcurrentTasks // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,unattendedCommands: null == unattendedCommands ? _self.unattendedCommands : unattendedCommands // ignore: cast_nullable_to_non_nullable
as List<String>,autoRunEnabled: null == autoRunEnabled ? _self.autoRunEnabled : autoRunEnabled // ignore: cast_nullable_to_non_nullable
as bool,dailyRunLimit: null == dailyRunLimit ? _self.dailyRunLimit : dailyRunLimit // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectFarmPolicy].
extension ProjectFarmPolicyPatterns on ProjectFarmPolicy {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectFarmPolicy value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectFarmPolicy() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectFarmPolicy value)  $default,){
final _that = this;
switch (_that) {
case _ProjectFarmPolicy():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectFarmPolicy value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectFarmPolicy() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  List<String> allowedVerificationCommands,  int maxConcurrentTasks,  DateTime updatedAt,  List<String> unattendedCommands,  bool autoRunEnabled,  int dailyRunLimit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectFarmPolicy() when $default != null:
return $default(_that.projectId,_that.allowedVerificationCommands,_that.maxConcurrentTasks,_that.updatedAt,_that.unattendedCommands,_that.autoRunEnabled,_that.dailyRunLimit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  List<String> allowedVerificationCommands,  int maxConcurrentTasks,  DateTime updatedAt,  List<String> unattendedCommands,  bool autoRunEnabled,  int dailyRunLimit)  $default,) {final _that = this;
switch (_that) {
case _ProjectFarmPolicy():
return $default(_that.projectId,_that.allowedVerificationCommands,_that.maxConcurrentTasks,_that.updatedAt,_that.unattendedCommands,_that.autoRunEnabled,_that.dailyRunLimit);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  List<String> allowedVerificationCommands,  int maxConcurrentTasks,  DateTime updatedAt,  List<String> unattendedCommands,  bool autoRunEnabled,  int dailyRunLimit)?  $default,) {final _that = this;
switch (_that) {
case _ProjectFarmPolicy() when $default != null:
return $default(_that.projectId,_that.allowedVerificationCommands,_that.maxConcurrentTasks,_that.updatedAt,_that.unattendedCommands,_that.autoRunEnabled,_that.dailyRunLimit);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProjectFarmPolicy extends ProjectFarmPolicy {
  const _ProjectFarmPolicy({required this.projectId, final  List<String> allowedVerificationCommands = const <String>[], this.maxConcurrentTasks = 1, required this.updatedAt, final  List<String> unattendedCommands = const <String>[], this.autoRunEnabled = false, this.dailyRunLimit = 1}): _allowedVerificationCommands = allowedVerificationCommands,_unattendedCommands = unattendedCommands,super._();
  factory _ProjectFarmPolicy.fromJson(Map<String, dynamic> json) => _$ProjectFarmPolicyFromJson(json);

@override final  String projectId;
 final  List<String> _allowedVerificationCommands;
@override@JsonKey() List<String> get allowedVerificationCommands {
  if (_allowedVerificationCommands is EqualUnmodifiableListView) return _allowedVerificationCommands;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_allowedVerificationCommands);
}

@override@JsonKey() final  int maxConcurrentTasks;
@override final  DateTime updatedAt;
/// FARM5: the subset of [allowedVerificationCommands] the user declared as
/// not executing project code (e.g. analyze, a format check). Only these
/// may run unattended: a test run executes code the agent just wrote, so
/// it keeps a person in the loop. Declared, never inferred.
 final  List<String> _unattendedCommands;
/// FARM5: the subset of [allowedVerificationCommands] the user declared as
/// not executing project code (e.g. analyze, a format check). Only these
/// may run unattended: a test run executes code the agent just wrote, so
/// it keeps a person in the loop. Declared, never inferred.
@override@JsonKey() List<String> get unattendedCommands {
  if (_unattendedCommands is EqualUnmodifiableListView) return _unattendedCommands;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unattendedCommands);
}

/// FARM5: whether idle-time maintenance may start runs on its own. Off
/// until the user turns it on.
@override@JsonKey() final  bool autoRunEnabled;
/// FARM5: unattended runs allowed per local day.
@override@JsonKey() final  int dailyRunLimit;

/// Create a copy of ProjectFarmPolicy
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectFarmPolicyCopyWith<_ProjectFarmPolicy> get copyWith => __$ProjectFarmPolicyCopyWithImpl<_ProjectFarmPolicy>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProjectFarmPolicyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectFarmPolicy&&(identical(other.projectId, projectId) || other.projectId == projectId)&&const DeepCollectionEquality().equals(other._allowedVerificationCommands, _allowedVerificationCommands)&&(identical(other.maxConcurrentTasks, maxConcurrentTasks) || other.maxConcurrentTasks == maxConcurrentTasks)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other._unattendedCommands, _unattendedCommands)&&(identical(other.autoRunEnabled, autoRunEnabled) || other.autoRunEnabled == autoRunEnabled)&&(identical(other.dailyRunLimit, dailyRunLimit) || other.dailyRunLimit == dailyRunLimit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,projectId,const DeepCollectionEquality().hash(_allowedVerificationCommands),maxConcurrentTasks,updatedAt,const DeepCollectionEquality().hash(_unattendedCommands),autoRunEnabled,dailyRunLimit);

@override
String toString() {
  return 'ProjectFarmPolicy(projectId: $projectId, allowedVerificationCommands: $allowedVerificationCommands, maxConcurrentTasks: $maxConcurrentTasks, updatedAt: $updatedAt, unattendedCommands: $unattendedCommands, autoRunEnabled: $autoRunEnabled, dailyRunLimit: $dailyRunLimit)';
}


}

/// @nodoc
abstract mixin class _$ProjectFarmPolicyCopyWith<$Res> implements $ProjectFarmPolicyCopyWith<$Res> {
  factory _$ProjectFarmPolicyCopyWith(_ProjectFarmPolicy value, $Res Function(_ProjectFarmPolicy) _then) = __$ProjectFarmPolicyCopyWithImpl;
@override @useResult
$Res call({
 String projectId, List<String> allowedVerificationCommands, int maxConcurrentTasks, DateTime updatedAt, List<String> unattendedCommands, bool autoRunEnabled, int dailyRunLimit
});




}
/// @nodoc
class __$ProjectFarmPolicyCopyWithImpl<$Res>
    implements _$ProjectFarmPolicyCopyWith<$Res> {
  __$ProjectFarmPolicyCopyWithImpl(this._self, this._then);

  final _ProjectFarmPolicy _self;
  final $Res Function(_ProjectFarmPolicy) _then;

/// Create a copy of ProjectFarmPolicy
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? allowedVerificationCommands = null,Object? maxConcurrentTasks = null,Object? updatedAt = null,Object? unattendedCommands = null,Object? autoRunEnabled = null,Object? dailyRunLimit = null,}) {
  return _then(_ProjectFarmPolicy(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,allowedVerificationCommands: null == allowedVerificationCommands ? _self._allowedVerificationCommands : allowedVerificationCommands // ignore: cast_nullable_to_non_nullable
as List<String>,maxConcurrentTasks: null == maxConcurrentTasks ? _self.maxConcurrentTasks : maxConcurrentTasks // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,unattendedCommands: null == unattendedCommands ? _self._unattendedCommands : unattendedCommands // ignore: cast_nullable_to_non_nullable
as List<String>,autoRunEnabled: null == autoRunEnabled ? _self.autoRunEnabled : autoRunEnabled // ignore: cast_nullable_to_non_nullable
as bool,dailyRunLimit: null == dailyRunLimit ? _self.dailyRunLimit : dailyRunLimit // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
