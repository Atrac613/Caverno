// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_workflow.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationWorkflowTask {

 String get id; String get title; ConversationWorkflowTaskStatus get status; List<String> get targetFiles; String get validationCommand; String get notes;
/// Create a copy of ConversationWorkflowTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationWorkflowTaskCopyWith<ConversationWorkflowTask> get copyWith => _$ConversationWorkflowTaskCopyWithImpl<ConversationWorkflowTask>(this as ConversationWorkflowTask, _$identity);

  /// Serializes this ConversationWorkflowTask to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationWorkflowTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.targetFiles, targetFiles)&&(identical(other.validationCommand, validationCommand) || other.validationCommand == validationCommand)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,status,const DeepCollectionEquality().hash(targetFiles),validationCommand,notes);

@override
String toString() {
  return 'ConversationWorkflowTask(id: $id, title: $title, status: $status, targetFiles: $targetFiles, validationCommand: $validationCommand, notes: $notes)';
}


}

/// @nodoc
abstract mixin class $ConversationWorkflowTaskCopyWith<$Res>  {
  factory $ConversationWorkflowTaskCopyWith(ConversationWorkflowTask value, $Res Function(ConversationWorkflowTask) _then) = _$ConversationWorkflowTaskCopyWithImpl;
@useResult
$Res call({
 String id, String title, ConversationWorkflowTaskStatus status, List<String> targetFiles, String validationCommand, String notes
});




}
/// @nodoc
class _$ConversationWorkflowTaskCopyWithImpl<$Res>
    implements $ConversationWorkflowTaskCopyWith<$Res> {
  _$ConversationWorkflowTaskCopyWithImpl(this._self, this._then);

  final ConversationWorkflowTask _self;
  final $Res Function(ConversationWorkflowTask) _then;

/// Create a copy of ConversationWorkflowTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? status = null,Object? targetFiles = null,Object? validationCommand = null,Object? notes = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowTaskStatus,targetFiles: null == targetFiles ? _self.targetFiles : targetFiles // ignore: cast_nullable_to_non_nullable
as List<String>,validationCommand: null == validationCommand ? _self.validationCommand : validationCommand // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationWorkflowTask].
extension ConversationWorkflowTaskPatterns on ConversationWorkflowTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationWorkflowTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationWorkflowTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationWorkflowTask value)  $default,){
final _that = this;
switch (_that) {
case _ConversationWorkflowTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationWorkflowTask value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationWorkflowTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  ConversationWorkflowTaskStatus status,  List<String> targetFiles,  String validationCommand,  String notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationWorkflowTask() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.targetFiles,_that.validationCommand,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  ConversationWorkflowTaskStatus status,  List<String> targetFiles,  String validationCommand,  String notes)  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowTask():
return $default(_that.id,_that.title,_that.status,_that.targetFiles,_that.validationCommand,_that.notes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  ConversationWorkflowTaskStatus status,  List<String> targetFiles,  String validationCommand,  String notes)?  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowTask() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.targetFiles,_that.validationCommand,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationWorkflowTask extends ConversationWorkflowTask {
  const _ConversationWorkflowTask({required this.id, required this.title, this.status = ConversationWorkflowTaskStatus.pending, final  List<String> targetFiles = const <String>[], this.validationCommand = '', this.notes = ''}): _targetFiles = targetFiles,super._();
  factory _ConversationWorkflowTask.fromJson(Map<String, dynamic> json) => _$ConversationWorkflowTaskFromJson(json);

@override final  String id;
@override final  String title;
@override@JsonKey() final  ConversationWorkflowTaskStatus status;
 final  List<String> _targetFiles;
@override@JsonKey() List<String> get targetFiles {
  if (_targetFiles is EqualUnmodifiableListView) return _targetFiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targetFiles);
}

@override@JsonKey() final  String validationCommand;
@override@JsonKey() final  String notes;

/// Create a copy of ConversationWorkflowTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationWorkflowTaskCopyWith<_ConversationWorkflowTask> get copyWith => __$ConversationWorkflowTaskCopyWithImpl<_ConversationWorkflowTask>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationWorkflowTaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationWorkflowTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._targetFiles, _targetFiles)&&(identical(other.validationCommand, validationCommand) || other.validationCommand == validationCommand)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,status,const DeepCollectionEquality().hash(_targetFiles),validationCommand,notes);

@override
String toString() {
  return 'ConversationWorkflowTask(id: $id, title: $title, status: $status, targetFiles: $targetFiles, validationCommand: $validationCommand, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$ConversationWorkflowTaskCopyWith<$Res> implements $ConversationWorkflowTaskCopyWith<$Res> {
  factory _$ConversationWorkflowTaskCopyWith(_ConversationWorkflowTask value, $Res Function(_ConversationWorkflowTask) _then) = __$ConversationWorkflowTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, ConversationWorkflowTaskStatus status, List<String> targetFiles, String validationCommand, String notes
});




}
/// @nodoc
class __$ConversationWorkflowTaskCopyWithImpl<$Res>
    implements _$ConversationWorkflowTaskCopyWith<$Res> {
  __$ConversationWorkflowTaskCopyWithImpl(this._self, this._then);

  final _ConversationWorkflowTask _self;
  final $Res Function(_ConversationWorkflowTask) _then;

/// Create a copy of ConversationWorkflowTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? status = null,Object? targetFiles = null,Object? validationCommand = null,Object? notes = null,}) {
  return _then(_ConversationWorkflowTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowTaskStatus,targetFiles: null == targetFiles ? _self._targetFiles : targetFiles // ignore: cast_nullable_to_non_nullable
as List<String>,validationCommand: null == validationCommand ? _self.validationCommand : validationCommand // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConversationExecutionTaskProgress {

 String get taskId; ConversationWorkflowTaskStatus get status; ConversationExecutionValidationStatus get validationStatus; DateTime? get updatedAt; DateTime? get lastRunAt; DateTime? get lastValidationAt; String get summary; String get blockedReason; String get lastValidationCommand; String get lastValidationSummary;
/// Create a copy of ConversationExecutionTaskProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationExecutionTaskProgressCopyWith<ConversationExecutionTaskProgress> get copyWith => _$ConversationExecutionTaskProgressCopyWithImpl<ConversationExecutionTaskProgress>(this as ConversationExecutionTaskProgress, _$identity);

  /// Serializes this ConversationExecutionTaskProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationExecutionTaskProgress&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationStatus, validationStatus) || other.validationStatus == validationStatus)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&(identical(other.lastValidationAt, lastValidationAt) || other.lastValidationAt == lastValidationAt)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.lastValidationCommand, lastValidationCommand) || other.lastValidationCommand == lastValidationCommand)&&(identical(other.lastValidationSummary, lastValidationSummary) || other.lastValidationSummary == lastValidationSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,taskId,status,validationStatus,updatedAt,lastRunAt,lastValidationAt,summary,blockedReason,lastValidationCommand,lastValidationSummary);

@override
String toString() {
  return 'ConversationExecutionTaskProgress(taskId: $taskId, status: $status, validationStatus: $validationStatus, updatedAt: $updatedAt, lastRunAt: $lastRunAt, lastValidationAt: $lastValidationAt, summary: $summary, blockedReason: $blockedReason, lastValidationCommand: $lastValidationCommand, lastValidationSummary: $lastValidationSummary)';
}


}

/// @nodoc
abstract mixin class $ConversationExecutionTaskProgressCopyWith<$Res>  {
  factory $ConversationExecutionTaskProgressCopyWith(ConversationExecutionTaskProgress value, $Res Function(ConversationExecutionTaskProgress) _then) = _$ConversationExecutionTaskProgressCopyWithImpl;
@useResult
$Res call({
 String taskId, ConversationWorkflowTaskStatus status, ConversationExecutionValidationStatus validationStatus, DateTime? updatedAt, DateTime? lastRunAt, DateTime? lastValidationAt, String summary, String blockedReason, String lastValidationCommand, String lastValidationSummary
});




}
/// @nodoc
class _$ConversationExecutionTaskProgressCopyWithImpl<$Res>
    implements $ConversationExecutionTaskProgressCopyWith<$Res> {
  _$ConversationExecutionTaskProgressCopyWithImpl(this._self, this._then);

  final ConversationExecutionTaskProgress _self;
  final $Res Function(ConversationExecutionTaskProgress) _then;

/// Create a copy of ConversationExecutionTaskProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? taskId = null,Object? status = null,Object? validationStatus = null,Object? updatedAt = freezed,Object? lastRunAt = freezed,Object? lastValidationAt = freezed,Object? summary = null,Object? blockedReason = null,Object? lastValidationCommand = null,Object? lastValidationSummary = null,}) {
  return _then(_self.copyWith(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowTaskStatus,validationStatus: null == validationStatus ? _self.validationStatus : validationStatus // ignore: cast_nullable_to_non_nullable
as ConversationExecutionValidationStatus,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastValidationAt: freezed == lastValidationAt ? _self.lastValidationAt : lastValidationAt // ignore: cast_nullable_to_non_nullable
as DateTime?,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,blockedReason: null == blockedReason ? _self.blockedReason : blockedReason // ignore: cast_nullable_to_non_nullable
as String,lastValidationCommand: null == lastValidationCommand ? _self.lastValidationCommand : lastValidationCommand // ignore: cast_nullable_to_non_nullable
as String,lastValidationSummary: null == lastValidationSummary ? _self.lastValidationSummary : lastValidationSummary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationExecutionTaskProgress].
extension ConversationExecutionTaskProgressPatterns on ConversationExecutionTaskProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationExecutionTaskProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationExecutionTaskProgress value)  $default,){
final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationExecutionTaskProgress value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String taskId,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  DateTime? updatedAt,  DateTime? lastRunAt,  DateTime? lastValidationAt,  String summary,  String blockedReason,  String lastValidationCommand,  String lastValidationSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress() when $default != null:
return $default(_that.taskId,_that.status,_that.validationStatus,_that.updatedAt,_that.lastRunAt,_that.lastValidationAt,_that.summary,_that.blockedReason,_that.lastValidationCommand,_that.lastValidationSummary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String taskId,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  DateTime? updatedAt,  DateTime? lastRunAt,  DateTime? lastValidationAt,  String summary,  String blockedReason,  String lastValidationCommand,  String lastValidationSummary)  $default,) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress():
return $default(_that.taskId,_that.status,_that.validationStatus,_that.updatedAt,_that.lastRunAt,_that.lastValidationAt,_that.summary,_that.blockedReason,_that.lastValidationCommand,_that.lastValidationSummary);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String taskId,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  DateTime? updatedAt,  DateTime? lastRunAt,  DateTime? lastValidationAt,  String summary,  String blockedReason,  String lastValidationCommand,  String lastValidationSummary)?  $default,) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress() when $default != null:
return $default(_that.taskId,_that.status,_that.validationStatus,_that.updatedAt,_that.lastRunAt,_that.lastValidationAt,_that.summary,_that.blockedReason,_that.lastValidationCommand,_that.lastValidationSummary);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationExecutionTaskProgress extends ConversationExecutionTaskProgress {
  const _ConversationExecutionTaskProgress({required this.taskId, this.status = ConversationWorkflowTaskStatus.pending, this.validationStatus = ConversationExecutionValidationStatus.unknown, this.updatedAt, this.lastRunAt, this.lastValidationAt, this.summary = '', this.blockedReason = '', this.lastValidationCommand = '', this.lastValidationSummary = ''}): super._();
  factory _ConversationExecutionTaskProgress.fromJson(Map<String, dynamic> json) => _$ConversationExecutionTaskProgressFromJson(json);

@override final  String taskId;
@override@JsonKey() final  ConversationWorkflowTaskStatus status;
@override@JsonKey() final  ConversationExecutionValidationStatus validationStatus;
@override final  DateTime? updatedAt;
@override final  DateTime? lastRunAt;
@override final  DateTime? lastValidationAt;
@override@JsonKey() final  String summary;
@override@JsonKey() final  String blockedReason;
@override@JsonKey() final  String lastValidationCommand;
@override@JsonKey() final  String lastValidationSummary;

/// Create a copy of ConversationExecutionTaskProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationExecutionTaskProgressCopyWith<_ConversationExecutionTaskProgress> get copyWith => __$ConversationExecutionTaskProgressCopyWithImpl<_ConversationExecutionTaskProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationExecutionTaskProgressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationExecutionTaskProgress&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationStatus, validationStatus) || other.validationStatus == validationStatus)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&(identical(other.lastValidationAt, lastValidationAt) || other.lastValidationAt == lastValidationAt)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.lastValidationCommand, lastValidationCommand) || other.lastValidationCommand == lastValidationCommand)&&(identical(other.lastValidationSummary, lastValidationSummary) || other.lastValidationSummary == lastValidationSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,taskId,status,validationStatus,updatedAt,lastRunAt,lastValidationAt,summary,blockedReason,lastValidationCommand,lastValidationSummary);

@override
String toString() {
  return 'ConversationExecutionTaskProgress(taskId: $taskId, status: $status, validationStatus: $validationStatus, updatedAt: $updatedAt, lastRunAt: $lastRunAt, lastValidationAt: $lastValidationAt, summary: $summary, blockedReason: $blockedReason, lastValidationCommand: $lastValidationCommand, lastValidationSummary: $lastValidationSummary)';
}


}

/// @nodoc
abstract mixin class _$ConversationExecutionTaskProgressCopyWith<$Res> implements $ConversationExecutionTaskProgressCopyWith<$Res> {
  factory _$ConversationExecutionTaskProgressCopyWith(_ConversationExecutionTaskProgress value, $Res Function(_ConversationExecutionTaskProgress) _then) = __$ConversationExecutionTaskProgressCopyWithImpl;
@override @useResult
$Res call({
 String taskId, ConversationWorkflowTaskStatus status, ConversationExecutionValidationStatus validationStatus, DateTime? updatedAt, DateTime? lastRunAt, DateTime? lastValidationAt, String summary, String blockedReason, String lastValidationCommand, String lastValidationSummary
});




}
/// @nodoc
class __$ConversationExecutionTaskProgressCopyWithImpl<$Res>
    implements _$ConversationExecutionTaskProgressCopyWith<$Res> {
  __$ConversationExecutionTaskProgressCopyWithImpl(this._self, this._then);

  final _ConversationExecutionTaskProgress _self;
  final $Res Function(_ConversationExecutionTaskProgress) _then;

/// Create a copy of ConversationExecutionTaskProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? status = null,Object? validationStatus = null,Object? updatedAt = freezed,Object? lastRunAt = freezed,Object? lastValidationAt = freezed,Object? summary = null,Object? blockedReason = null,Object? lastValidationCommand = null,Object? lastValidationSummary = null,}) {
  return _then(_ConversationExecutionTaskProgress(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowTaskStatus,validationStatus: null == validationStatus ? _self.validationStatus : validationStatus // ignore: cast_nullable_to_non_nullable
as ConversationExecutionValidationStatus,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastValidationAt: freezed == lastValidationAt ? _self.lastValidationAt : lastValidationAt // ignore: cast_nullable_to_non_nullable
as DateTime?,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,blockedReason: null == blockedReason ? _self.blockedReason : blockedReason // ignore: cast_nullable_to_non_nullable
as String,lastValidationCommand: null == lastValidationCommand ? _self.lastValidationCommand : lastValidationCommand // ignore: cast_nullable_to_non_nullable
as String,lastValidationSummary: null == lastValidationSummary ? _self.lastValidationSummary : lastValidationSummary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConversationWorkflowSpec {

 String get goal; List<String> get constraints; List<String> get acceptanceCriteria; List<String> get openQuestions;@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> get tasks;
/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<ConversationWorkflowSpec> get copyWith => _$ConversationWorkflowSpecCopyWithImpl<ConversationWorkflowSpec>(this as ConversationWorkflowSpec, _$identity);

  /// Serializes this ConversationWorkflowSpec to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationWorkflowSpec&&(identical(other.goal, goal) || other.goal == goal)&&const DeepCollectionEquality().equals(other.constraints, constraints)&&const DeepCollectionEquality().equals(other.acceptanceCriteria, acceptanceCriteria)&&const DeepCollectionEquality().equals(other.openQuestions, openQuestions)&&const DeepCollectionEquality().equals(other.tasks, tasks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goal,const DeepCollectionEquality().hash(constraints),const DeepCollectionEquality().hash(acceptanceCriteria),const DeepCollectionEquality().hash(openQuestions),const DeepCollectionEquality().hash(tasks));

@override
String toString() {
  return 'ConversationWorkflowSpec(goal: $goal, constraints: $constraints, acceptanceCriteria: $acceptanceCriteria, openQuestions: $openQuestions, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class $ConversationWorkflowSpecCopyWith<$Res>  {
  factory $ConversationWorkflowSpecCopyWith(ConversationWorkflowSpec value, $Res Function(ConversationWorkflowSpec) _then) = _$ConversationWorkflowSpecCopyWithImpl;
@useResult
$Res call({
 String goal, List<String> constraints, List<String> acceptanceCriteria, List<String> openQuestions,@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> tasks
});




}
/// @nodoc
class _$ConversationWorkflowSpecCopyWithImpl<$Res>
    implements $ConversationWorkflowSpecCopyWith<$Res> {
  _$ConversationWorkflowSpecCopyWithImpl(this._self, this._then);

  final ConversationWorkflowSpec _self;
  final $Res Function(ConversationWorkflowSpec) _then;

/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? goal = null,Object? constraints = null,Object? acceptanceCriteria = null,Object? openQuestions = null,Object? tasks = null,}) {
  return _then(_self.copyWith(
goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,constraints: null == constraints ? _self.constraints : constraints // ignore: cast_nullable_to_non_nullable
as List<String>,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,openQuestions: null == openQuestions ? _self.openQuestions : openQuestions // ignore: cast_nullable_to_non_nullable
as List<String>,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ConversationWorkflowTask>,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationWorkflowSpec].
extension ConversationWorkflowSpecPatterns on ConversationWorkflowSpec {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationWorkflowSpec value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationWorkflowSpec value)  $default,){
final _that = this;
switch (_that) {
case _ConversationWorkflowSpec():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationWorkflowSpec value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions, @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)  List<ConversationWorkflowTask> tasks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions,_that.tasks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions, @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)  List<ConversationWorkflowTask> tasks)  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec():
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions,_that.tasks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions, @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)  List<ConversationWorkflowTask> tasks)?  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions,_that.tasks);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationWorkflowSpec extends ConversationWorkflowSpec {
  const _ConversationWorkflowSpec({this.goal = '', final  List<String> constraints = const <String>[], final  List<String> acceptanceCriteria = const <String>[], final  List<String> openQuestions = const <String>[], @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) final  List<ConversationWorkflowTask> tasks = const <ConversationWorkflowTask>[]}): _constraints = constraints,_acceptanceCriteria = acceptanceCriteria,_openQuestions = openQuestions,_tasks = tasks,super._();
  factory _ConversationWorkflowSpec.fromJson(Map<String, dynamic> json) => _$ConversationWorkflowSpecFromJson(json);

@override@JsonKey() final  String goal;
 final  List<String> _constraints;
@override@JsonKey() List<String> get constraints {
  if (_constraints is EqualUnmodifiableListView) return _constraints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_constraints);
}

 final  List<String> _acceptanceCriteria;
@override@JsonKey() List<String> get acceptanceCriteria {
  if (_acceptanceCriteria is EqualUnmodifiableListView) return _acceptanceCriteria;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_acceptanceCriteria);
}

 final  List<String> _openQuestions;
@override@JsonKey() List<String> get openQuestions {
  if (_openQuestions is EqualUnmodifiableListView) return _openQuestions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_openQuestions);
}

 final  List<ConversationWorkflowTask> _tasks;
@override@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}


/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationWorkflowSpecCopyWith<_ConversationWorkflowSpec> get copyWith => __$ConversationWorkflowSpecCopyWithImpl<_ConversationWorkflowSpec>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationWorkflowSpecToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationWorkflowSpec&&(identical(other.goal, goal) || other.goal == goal)&&const DeepCollectionEquality().equals(other._constraints, _constraints)&&const DeepCollectionEquality().equals(other._acceptanceCriteria, _acceptanceCriteria)&&const DeepCollectionEquality().equals(other._openQuestions, _openQuestions)&&const DeepCollectionEquality().equals(other._tasks, _tasks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goal,const DeepCollectionEquality().hash(_constraints),const DeepCollectionEquality().hash(_acceptanceCriteria),const DeepCollectionEquality().hash(_openQuestions),const DeepCollectionEquality().hash(_tasks));

@override
String toString() {
  return 'ConversationWorkflowSpec(goal: $goal, constraints: $constraints, acceptanceCriteria: $acceptanceCriteria, openQuestions: $openQuestions, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class _$ConversationWorkflowSpecCopyWith<$Res> implements $ConversationWorkflowSpecCopyWith<$Res> {
  factory _$ConversationWorkflowSpecCopyWith(_ConversationWorkflowSpec value, $Res Function(_ConversationWorkflowSpec) _then) = __$ConversationWorkflowSpecCopyWithImpl;
@override @useResult
$Res call({
 String goal, List<String> constraints, List<String> acceptanceCriteria, List<String> openQuestions,@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> tasks
});




}
/// @nodoc
class __$ConversationWorkflowSpecCopyWithImpl<$Res>
    implements _$ConversationWorkflowSpecCopyWith<$Res> {
  __$ConversationWorkflowSpecCopyWithImpl(this._self, this._then);

  final _ConversationWorkflowSpec _self;
  final $Res Function(_ConversationWorkflowSpec) _then;

/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? goal = null,Object? constraints = null,Object? acceptanceCriteria = null,Object? openQuestions = null,Object? tasks = null,}) {
  return _then(_ConversationWorkflowSpec(
goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,constraints: null == constraints ? _self._constraints : constraints // ignore: cast_nullable_to_non_nullable
as List<String>,acceptanceCriteria: null == acceptanceCriteria ? _self._acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,openQuestions: null == openQuestions ? _self._openQuestions : openQuestions // ignore: cast_nullable_to_non_nullable
as List<String>,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ConversationWorkflowTask>,
  ));
}


}

// dart format on
