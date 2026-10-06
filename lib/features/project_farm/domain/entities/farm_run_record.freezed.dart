// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'farm_run_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FarmRunRecord {

 String get id; String get projectId;/// `manual` (Run in background) or `unattended` (idle maintenance).
 String get trigger; DateTime get at;/// `enqueued` or `skipped`.
 String get outcome; String get taskId; String get command; String get branch;/// For a skip: the machine reason, such as `daily_limit` or `needsHuman`.
 String get detail;
/// Create a copy of FarmRunRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FarmRunRecordCopyWith<FarmRunRecord> get copyWith => _$FarmRunRecordCopyWithImpl<FarmRunRecord>(this as FarmRunRecord, _$identity);

  /// Serializes this FarmRunRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FarmRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.at, at) || other.at == at)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.command, command) || other.command == command)&&(identical(other.branch, branch) || other.branch == branch)&&(identical(other.detail, detail) || other.detail == detail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,trigger,at,outcome,taskId,command,branch,detail);

@override
String toString() {
  return 'FarmRunRecord(id: $id, projectId: $projectId, trigger: $trigger, at: $at, outcome: $outcome, taskId: $taskId, command: $command, branch: $branch, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $FarmRunRecordCopyWith<$Res>  {
  factory $FarmRunRecordCopyWith(FarmRunRecord value, $Res Function(FarmRunRecord) _then) = _$FarmRunRecordCopyWithImpl;
@useResult
$Res call({
 String id, String projectId, String trigger, DateTime at, String outcome, String taskId, String command, String branch, String detail
});




}
/// @nodoc
class _$FarmRunRecordCopyWithImpl<$Res>
    implements $FarmRunRecordCopyWith<$Res> {
  _$FarmRunRecordCopyWithImpl(this._self, this._then);

  final FarmRunRecord _self;
  final $Res Function(FarmRunRecord) _then;

/// Create a copy of FarmRunRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? trigger = null,Object? at = null,Object? outcome = null,Object? taskId = null,Object? command = null,Object? branch = null,Object? detail = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as String,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FarmRunRecord].
extension FarmRunRecordPatterns on FarmRunRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FarmRunRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FarmRunRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FarmRunRecord value)  $default,){
final _that = this;
switch (_that) {
case _FarmRunRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FarmRunRecord value)?  $default,){
final _that = this;
switch (_that) {
case _FarmRunRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String projectId,  String trigger,  DateTime at,  String outcome,  String taskId,  String command,  String branch,  String detail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FarmRunRecord() when $default != null:
return $default(_that.id,_that.projectId,_that.trigger,_that.at,_that.outcome,_that.taskId,_that.command,_that.branch,_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String projectId,  String trigger,  DateTime at,  String outcome,  String taskId,  String command,  String branch,  String detail)  $default,) {final _that = this;
switch (_that) {
case _FarmRunRecord():
return $default(_that.id,_that.projectId,_that.trigger,_that.at,_that.outcome,_that.taskId,_that.command,_that.branch,_that.detail);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String projectId,  String trigger,  DateTime at,  String outcome,  String taskId,  String command,  String branch,  String detail)?  $default,) {final _that = this;
switch (_that) {
case _FarmRunRecord() when $default != null:
return $default(_that.id,_that.projectId,_that.trigger,_that.at,_that.outcome,_that.taskId,_that.command,_that.branch,_that.detail);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FarmRunRecord implements FarmRunRecord {
  const _FarmRunRecord({required this.id, required this.projectId, required this.trigger, required this.at, required this.outcome, this.taskId = '', this.command = '', this.branch = '', this.detail = ''});
  factory _FarmRunRecord.fromJson(Map<String, dynamic> json) => _$FarmRunRecordFromJson(json);

@override final  String id;
@override final  String projectId;
/// `manual` (Run in background) or `unattended` (idle maintenance).
@override final  String trigger;
@override final  DateTime at;
/// `enqueued` or `skipped`.
@override final  String outcome;
@override@JsonKey() final  String taskId;
@override@JsonKey() final  String command;
@override@JsonKey() final  String branch;
/// For a skip: the machine reason, such as `daily_limit` or `needsHuman`.
@override@JsonKey() final  String detail;

/// Create a copy of FarmRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FarmRunRecordCopyWith<_FarmRunRecord> get copyWith => __$FarmRunRecordCopyWithImpl<_FarmRunRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FarmRunRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FarmRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.at, at) || other.at == at)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.command, command) || other.command == command)&&(identical(other.branch, branch) || other.branch == branch)&&(identical(other.detail, detail) || other.detail == detail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,trigger,at,outcome,taskId,command,branch,detail);

@override
String toString() {
  return 'FarmRunRecord(id: $id, projectId: $projectId, trigger: $trigger, at: $at, outcome: $outcome, taskId: $taskId, command: $command, branch: $branch, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$FarmRunRecordCopyWith<$Res> implements $FarmRunRecordCopyWith<$Res> {
  factory _$FarmRunRecordCopyWith(_FarmRunRecord value, $Res Function(_FarmRunRecord) _then) = __$FarmRunRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String projectId, String trigger, DateTime at, String outcome, String taskId, String command, String branch, String detail
});




}
/// @nodoc
class __$FarmRunRecordCopyWithImpl<$Res>
    implements _$FarmRunRecordCopyWith<$Res> {
  __$FarmRunRecordCopyWithImpl(this._self, this._then);

  final _FarmRunRecord _self;
  final $Res Function(_FarmRunRecord) _then;

/// Create a copy of FarmRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? trigger = null,Object? at = null,Object? outcome = null,Object? taskId = null,Object? command = null,Object? branch = null,Object? detail = null,}) {
  return _then(_FarmRunRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as String,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
