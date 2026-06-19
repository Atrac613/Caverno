// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'worktree_agent_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WorktreeAgentTask {

 String get id;@JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery) WorktreeAgentTaskStatus get status; String get title; String get prompt; String get codingProjectId; String get baseBranch; String get branchName; String get worktreePath; String get checkpointLineageId; String get endpointId; String get verificationCommand; DateTime get createdAt; DateTime get updatedAt; DateTime? get startedAt; DateTime? get finishedAt; String get resultSummary; bool get verifiedGreen; String get verificationSummary; String get recoveryNote; String get error;
/// Create a copy of WorktreeAgentTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorktreeAgentTaskCopyWith<WorktreeAgentTask> get copyWith => _$WorktreeAgentTaskCopyWithImpl<WorktreeAgentTask>(this as WorktreeAgentTask, _$identity);

  /// Serializes this WorktreeAgentTask to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorktreeAgentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.title, title) || other.title == title)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.codingProjectId, codingProjectId) || other.codingProjectId == codingProjectId)&&(identical(other.baseBranch, baseBranch) || other.baseBranch == baseBranch)&&(identical(other.branchName, branchName) || other.branchName == branchName)&&(identical(other.worktreePath, worktreePath) || other.worktreePath == worktreePath)&&(identical(other.checkpointLineageId, checkpointLineageId) || other.checkpointLineageId == checkpointLineageId)&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId)&&(identical(other.verificationCommand, verificationCommand) || other.verificationCommand == verificationCommand)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.resultSummary, resultSummary) || other.resultSummary == resultSummary)&&(identical(other.verifiedGreen, verifiedGreen) || other.verifiedGreen == verifiedGreen)&&(identical(other.verificationSummary, verificationSummary) || other.verificationSummary == verificationSummary)&&(identical(other.recoveryNote, recoveryNote) || other.recoveryNote == recoveryNote)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,status,title,prompt,codingProjectId,baseBranch,branchName,worktreePath,checkpointLineageId,endpointId,verificationCommand,createdAt,updatedAt,startedAt,finishedAt,resultSummary,verifiedGreen,verificationSummary,recoveryNote,error]);

@override
String toString() {
  return 'WorktreeAgentTask(id: $id, status: $status, title: $title, prompt: $prompt, codingProjectId: $codingProjectId, baseBranch: $baseBranch, branchName: $branchName, worktreePath: $worktreePath, checkpointLineageId: $checkpointLineageId, endpointId: $endpointId, verificationCommand: $verificationCommand, createdAt: $createdAt, updatedAt: $updatedAt, startedAt: $startedAt, finishedAt: $finishedAt, resultSummary: $resultSummary, verifiedGreen: $verifiedGreen, verificationSummary: $verificationSummary, recoveryNote: $recoveryNote, error: $error)';
}


}

/// @nodoc
abstract mixin class $WorktreeAgentTaskCopyWith<$Res>  {
  factory $WorktreeAgentTaskCopyWith(WorktreeAgentTask value, $Res Function(WorktreeAgentTask) _then) = _$WorktreeAgentTaskCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery) WorktreeAgentTaskStatus status, String title, String prompt, String codingProjectId, String baseBranch, String branchName, String worktreePath, String checkpointLineageId, String endpointId, String verificationCommand, DateTime createdAt, DateTime updatedAt, DateTime? startedAt, DateTime? finishedAt, String resultSummary, bool verifiedGreen, String verificationSummary, String recoveryNote, String error
});




}
/// @nodoc
class _$WorktreeAgentTaskCopyWithImpl<$Res>
    implements $WorktreeAgentTaskCopyWith<$Res> {
  _$WorktreeAgentTaskCopyWithImpl(this._self, this._then);

  final WorktreeAgentTask _self;
  final $Res Function(WorktreeAgentTask) _then;

/// Create a copy of WorktreeAgentTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? status = null,Object? title = null,Object? prompt = null,Object? codingProjectId = null,Object? baseBranch = null,Object? branchName = null,Object? worktreePath = null,Object? checkpointLineageId = null,Object? endpointId = null,Object? verificationCommand = null,Object? createdAt = null,Object? updatedAt = null,Object? startedAt = freezed,Object? finishedAt = freezed,Object? resultSummary = null,Object? verifiedGreen = null,Object? verificationSummary = null,Object? recoveryNote = null,Object? error = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as WorktreeAgentTaskStatus,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,codingProjectId: null == codingProjectId ? _self.codingProjectId : codingProjectId // ignore: cast_nullable_to_non_nullable
as String,baseBranch: null == baseBranch ? _self.baseBranch : baseBranch // ignore: cast_nullable_to_non_nullable
as String,branchName: null == branchName ? _self.branchName : branchName // ignore: cast_nullable_to_non_nullable
as String,worktreePath: null == worktreePath ? _self.worktreePath : worktreePath // ignore: cast_nullable_to_non_nullable
as String,checkpointLineageId: null == checkpointLineageId ? _self.checkpointLineageId : checkpointLineageId // ignore: cast_nullable_to_non_nullable
as String,endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,verificationCommand: null == verificationCommand ? _self.verificationCommand : verificationCommand // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,resultSummary: null == resultSummary ? _self.resultSummary : resultSummary // ignore: cast_nullable_to_non_nullable
as String,verifiedGreen: null == verifiedGreen ? _self.verifiedGreen : verifiedGreen // ignore: cast_nullable_to_non_nullable
as bool,verificationSummary: null == verificationSummary ? _self.verificationSummary : verificationSummary // ignore: cast_nullable_to_non_nullable
as String,recoveryNote: null == recoveryNote ? _self.recoveryNote : recoveryNote // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WorktreeAgentTask].
extension WorktreeAgentTaskPatterns on WorktreeAgentTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorktreeAgentTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorktreeAgentTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorktreeAgentTask value)  $default,){
final _that = this;
switch (_that) {
case _WorktreeAgentTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorktreeAgentTask value)?  $default,){
final _that = this;
switch (_that) {
case _WorktreeAgentTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery)  WorktreeAgentTaskStatus status,  String title,  String prompt,  String codingProjectId,  String baseBranch,  String branchName,  String worktreePath,  String checkpointLineageId,  String endpointId,  String verificationCommand,  DateTime createdAt,  DateTime updatedAt,  DateTime? startedAt,  DateTime? finishedAt,  String resultSummary,  bool verifiedGreen,  String verificationSummary,  String recoveryNote,  String error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorktreeAgentTask() when $default != null:
return $default(_that.id,_that.status,_that.title,_that.prompt,_that.codingProjectId,_that.baseBranch,_that.branchName,_that.worktreePath,_that.checkpointLineageId,_that.endpointId,_that.verificationCommand,_that.createdAt,_that.updatedAt,_that.startedAt,_that.finishedAt,_that.resultSummary,_that.verifiedGreen,_that.verificationSummary,_that.recoveryNote,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery)  WorktreeAgentTaskStatus status,  String title,  String prompt,  String codingProjectId,  String baseBranch,  String branchName,  String worktreePath,  String checkpointLineageId,  String endpointId,  String verificationCommand,  DateTime createdAt,  DateTime updatedAt,  DateTime? startedAt,  DateTime? finishedAt,  String resultSummary,  bool verifiedGreen,  String verificationSummary,  String recoveryNote,  String error)  $default,) {final _that = this;
switch (_that) {
case _WorktreeAgentTask():
return $default(_that.id,_that.status,_that.title,_that.prompt,_that.codingProjectId,_that.baseBranch,_that.branchName,_that.worktreePath,_that.checkpointLineageId,_that.endpointId,_that.verificationCommand,_that.createdAt,_that.updatedAt,_that.startedAt,_that.finishedAt,_that.resultSummary,_that.verifiedGreen,_that.verificationSummary,_that.recoveryNote,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery)  WorktreeAgentTaskStatus status,  String title,  String prompt,  String codingProjectId,  String baseBranch,  String branchName,  String worktreePath,  String checkpointLineageId,  String endpointId,  String verificationCommand,  DateTime createdAt,  DateTime updatedAt,  DateTime? startedAt,  DateTime? finishedAt,  String resultSummary,  bool verifiedGreen,  String verificationSummary,  String recoveryNote,  String error)?  $default,) {final _that = this;
switch (_that) {
case _WorktreeAgentTask() when $default != null:
return $default(_that.id,_that.status,_that.title,_that.prompt,_that.codingProjectId,_that.baseBranch,_that.branchName,_that.worktreePath,_that.checkpointLineageId,_that.endpointId,_that.verificationCommand,_that.createdAt,_that.updatedAt,_that.startedAt,_that.finishedAt,_that.resultSummary,_that.verifiedGreen,_that.verificationSummary,_that.recoveryNote,_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorktreeAgentTask extends WorktreeAgentTask {
  const _WorktreeAgentTask({required this.id, @JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery) this.status = WorktreeAgentTaskStatus.queued, this.title = '', this.prompt = '', this.codingProjectId = '', this.baseBranch = 'main', required this.branchName, required this.worktreePath, this.checkpointLineageId = '', this.endpointId = '', this.verificationCommand = '', required this.createdAt, required this.updatedAt, this.startedAt, this.finishedAt, this.resultSummary = '', this.verifiedGreen = false, this.verificationSummary = '', this.recoveryNote = '', this.error = ''}): super._();
  factory _WorktreeAgentTask.fromJson(Map<String, dynamic> json) => _$WorktreeAgentTaskFromJson(json);

@override final  String id;
@override@JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery) final  WorktreeAgentTaskStatus status;
@override@JsonKey() final  String title;
@override@JsonKey() final  String prompt;
@override@JsonKey() final  String codingProjectId;
@override@JsonKey() final  String baseBranch;
@override final  String branchName;
@override final  String worktreePath;
@override@JsonKey() final  String checkpointLineageId;
@override@JsonKey() final  String endpointId;
@override@JsonKey() final  String verificationCommand;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? startedAt;
@override final  DateTime? finishedAt;
@override@JsonKey() final  String resultSummary;
@override@JsonKey() final  bool verifiedGreen;
@override@JsonKey() final  String verificationSummary;
@override@JsonKey() final  String recoveryNote;
@override@JsonKey() final  String error;

/// Create a copy of WorktreeAgentTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorktreeAgentTaskCopyWith<_WorktreeAgentTask> get copyWith => __$WorktreeAgentTaskCopyWithImpl<_WorktreeAgentTask>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorktreeAgentTaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorktreeAgentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.title, title) || other.title == title)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.codingProjectId, codingProjectId) || other.codingProjectId == codingProjectId)&&(identical(other.baseBranch, baseBranch) || other.baseBranch == baseBranch)&&(identical(other.branchName, branchName) || other.branchName == branchName)&&(identical(other.worktreePath, worktreePath) || other.worktreePath == worktreePath)&&(identical(other.checkpointLineageId, checkpointLineageId) || other.checkpointLineageId == checkpointLineageId)&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId)&&(identical(other.verificationCommand, verificationCommand) || other.verificationCommand == verificationCommand)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.resultSummary, resultSummary) || other.resultSummary == resultSummary)&&(identical(other.verifiedGreen, verifiedGreen) || other.verifiedGreen == verifiedGreen)&&(identical(other.verificationSummary, verificationSummary) || other.verificationSummary == verificationSummary)&&(identical(other.recoveryNote, recoveryNote) || other.recoveryNote == recoveryNote)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,status,title,prompt,codingProjectId,baseBranch,branchName,worktreePath,checkpointLineageId,endpointId,verificationCommand,createdAt,updatedAt,startedAt,finishedAt,resultSummary,verifiedGreen,verificationSummary,recoveryNote,error]);

@override
String toString() {
  return 'WorktreeAgentTask(id: $id, status: $status, title: $title, prompt: $prompt, codingProjectId: $codingProjectId, baseBranch: $baseBranch, branchName: $branchName, worktreePath: $worktreePath, checkpointLineageId: $checkpointLineageId, endpointId: $endpointId, verificationCommand: $verificationCommand, createdAt: $createdAt, updatedAt: $updatedAt, startedAt: $startedAt, finishedAt: $finishedAt, resultSummary: $resultSummary, verifiedGreen: $verifiedGreen, verificationSummary: $verificationSummary, recoveryNote: $recoveryNote, error: $error)';
}


}

/// @nodoc
abstract mixin class _$WorktreeAgentTaskCopyWith<$Res> implements $WorktreeAgentTaskCopyWith<$Res> {
  factory _$WorktreeAgentTaskCopyWith(_WorktreeAgentTask value, $Res Function(_WorktreeAgentTask) _then) = __$WorktreeAgentTaskCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery) WorktreeAgentTaskStatus status, String title, String prompt, String codingProjectId, String baseBranch, String branchName, String worktreePath, String checkpointLineageId, String endpointId, String verificationCommand, DateTime createdAt, DateTime updatedAt, DateTime? startedAt, DateTime? finishedAt, String resultSummary, bool verifiedGreen, String verificationSummary, String recoveryNote, String error
});




}
/// @nodoc
class __$WorktreeAgentTaskCopyWithImpl<$Res>
    implements _$WorktreeAgentTaskCopyWith<$Res> {
  __$WorktreeAgentTaskCopyWithImpl(this._self, this._then);

  final _WorktreeAgentTask _self;
  final $Res Function(_WorktreeAgentTask) _then;

/// Create a copy of WorktreeAgentTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? status = null,Object? title = null,Object? prompt = null,Object? codingProjectId = null,Object? baseBranch = null,Object? branchName = null,Object? worktreePath = null,Object? checkpointLineageId = null,Object? endpointId = null,Object? verificationCommand = null,Object? createdAt = null,Object? updatedAt = null,Object? startedAt = freezed,Object? finishedAt = freezed,Object? resultSummary = null,Object? verifiedGreen = null,Object? verificationSummary = null,Object? recoveryNote = null,Object? error = null,}) {
  return _then(_WorktreeAgentTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as WorktreeAgentTaskStatus,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,codingProjectId: null == codingProjectId ? _self.codingProjectId : codingProjectId // ignore: cast_nullable_to_non_nullable
as String,baseBranch: null == baseBranch ? _self.baseBranch : baseBranch // ignore: cast_nullable_to_non_nullable
as String,branchName: null == branchName ? _self.branchName : branchName // ignore: cast_nullable_to_non_nullable
as String,worktreePath: null == worktreePath ? _self.worktreePath : worktreePath // ignore: cast_nullable_to_non_nullable
as String,checkpointLineageId: null == checkpointLineageId ? _self.checkpointLineageId : checkpointLineageId // ignore: cast_nullable_to_non_nullable
as String,endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,verificationCommand: null == verificationCommand ? _self.verificationCommand : verificationCommand // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,resultSummary: null == resultSummary ? _self.resultSummary : resultSummary // ignore: cast_nullable_to_non_nullable
as String,verifiedGreen: null == verifiedGreen ? _self.verifiedGreen : verifiedGreen // ignore: cast_nullable_to_non_nullable
as bool,verificationSummary: null == verificationSummary ? _self.verificationSummary : verificationSummary // ignore: cast_nullable_to_non_nullable
as String,recoveryNote: null == recoveryNote ? _self.recoveryNote : recoveryNote // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
