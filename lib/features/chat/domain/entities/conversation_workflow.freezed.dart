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
mixin _$ConversationOpenQuestionProgress {

 String get questionId; String get question; ConversationOpenQuestionStatus get status; String get note; DateTime? get updatedAt;
/// Create a copy of ConversationOpenQuestionProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationOpenQuestionProgressCopyWith<ConversationOpenQuestionProgress> get copyWith => _$ConversationOpenQuestionProgressCopyWithImpl<ConversationOpenQuestionProgress>(this as ConversationOpenQuestionProgress, _$identity);

  /// Serializes this ConversationOpenQuestionProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationOpenQuestionProgress&&(identical(other.questionId, questionId) || other.questionId == questionId)&&(identical(other.question, question) || other.question == question)&&(identical(other.status, status) || other.status == status)&&(identical(other.note, note) || other.note == note)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,questionId,question,status,note,updatedAt);

@override
String toString() {
  return 'ConversationOpenQuestionProgress(questionId: $questionId, question: $question, status: $status, note: $note, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ConversationOpenQuestionProgressCopyWith<$Res>  {
  factory $ConversationOpenQuestionProgressCopyWith(ConversationOpenQuestionProgress value, $Res Function(ConversationOpenQuestionProgress) _then) = _$ConversationOpenQuestionProgressCopyWithImpl;
@useResult
$Res call({
 String questionId, String question, ConversationOpenQuestionStatus status, String note, DateTime? updatedAt
});




}
/// @nodoc
class _$ConversationOpenQuestionProgressCopyWithImpl<$Res>
    implements $ConversationOpenQuestionProgressCopyWith<$Res> {
  _$ConversationOpenQuestionProgressCopyWithImpl(this._self, this._then);

  final ConversationOpenQuestionProgress _self;
  final $Res Function(ConversationOpenQuestionProgress) _then;

/// Create a copy of ConversationOpenQuestionProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? questionId = null,Object? question = null,Object? status = null,Object? note = null,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationOpenQuestionStatus,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationOpenQuestionProgress].
extension ConversationOpenQuestionProgressPatterns on ConversationOpenQuestionProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationOpenQuestionProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationOpenQuestionProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationOpenQuestionProgress value)  $default,){
final _that = this;
switch (_that) {
case _ConversationOpenQuestionProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationOpenQuestionProgress value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationOpenQuestionProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String questionId,  String question,  ConversationOpenQuestionStatus status,  String note,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationOpenQuestionProgress() when $default != null:
return $default(_that.questionId,_that.question,_that.status,_that.note,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String questionId,  String question,  ConversationOpenQuestionStatus status,  String note,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ConversationOpenQuestionProgress():
return $default(_that.questionId,_that.question,_that.status,_that.note,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String questionId,  String question,  ConversationOpenQuestionStatus status,  String note,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ConversationOpenQuestionProgress() when $default != null:
return $default(_that.questionId,_that.question,_that.status,_that.note,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationOpenQuestionProgress extends ConversationOpenQuestionProgress {
  const _ConversationOpenQuestionProgress({required this.questionId, required this.question, this.status = ConversationOpenQuestionStatus.unresolved, this.note = '', this.updatedAt}): super._();
  factory _ConversationOpenQuestionProgress.fromJson(Map<String, dynamic> json) => _$ConversationOpenQuestionProgressFromJson(json);

@override final  String questionId;
@override final  String question;
@override@JsonKey() final  ConversationOpenQuestionStatus status;
@override@JsonKey() final  String note;
@override final  DateTime? updatedAt;

/// Create a copy of ConversationOpenQuestionProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationOpenQuestionProgressCopyWith<_ConversationOpenQuestionProgress> get copyWith => __$ConversationOpenQuestionProgressCopyWithImpl<_ConversationOpenQuestionProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationOpenQuestionProgressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationOpenQuestionProgress&&(identical(other.questionId, questionId) || other.questionId == questionId)&&(identical(other.question, question) || other.question == question)&&(identical(other.status, status) || other.status == status)&&(identical(other.note, note) || other.note == note)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,questionId,question,status,note,updatedAt);

@override
String toString() {
  return 'ConversationOpenQuestionProgress(questionId: $questionId, question: $question, status: $status, note: $note, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ConversationOpenQuestionProgressCopyWith<$Res> implements $ConversationOpenQuestionProgressCopyWith<$Res> {
  factory _$ConversationOpenQuestionProgressCopyWith(_ConversationOpenQuestionProgress value, $Res Function(_ConversationOpenQuestionProgress) _then) = __$ConversationOpenQuestionProgressCopyWithImpl;
@override @useResult
$Res call({
 String questionId, String question, ConversationOpenQuestionStatus status, String note, DateTime? updatedAt
});




}
/// @nodoc
class __$ConversationOpenQuestionProgressCopyWithImpl<$Res>
    implements _$ConversationOpenQuestionProgressCopyWith<$Res> {
  __$ConversationOpenQuestionProgressCopyWithImpl(this._self, this._then);

  final _ConversationOpenQuestionProgress _self;
  final $Res Function(_ConversationOpenQuestionProgress) _then;

/// Create a copy of ConversationOpenQuestionProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? questionId = null,Object? question = null,Object? status = null,Object? note = null,Object? updatedAt = freezed,}) {
  return _then(_ConversationOpenQuestionProgress(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationOpenQuestionStatus,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


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

 String get taskId; ConversationWorkflowTaskStatus get status; ConversationExecutionValidationStatus get validationStatus; DateTime? get updatedAt; DateTime? get lastRunAt; DateTime? get lastValidationAt; String get summary; String get blockedReason; String get lastValidationCommand; String get lastValidationSummary;@JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson) List<ConversationExecutionTaskEvent> get events;
/// Create a copy of ConversationExecutionTaskProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationExecutionTaskProgressCopyWith<ConversationExecutionTaskProgress> get copyWith => _$ConversationExecutionTaskProgressCopyWithImpl<ConversationExecutionTaskProgress>(this as ConversationExecutionTaskProgress, _$identity);

  /// Serializes this ConversationExecutionTaskProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationExecutionTaskProgress&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationStatus, validationStatus) || other.validationStatus == validationStatus)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&(identical(other.lastValidationAt, lastValidationAt) || other.lastValidationAt == lastValidationAt)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.lastValidationCommand, lastValidationCommand) || other.lastValidationCommand == lastValidationCommand)&&(identical(other.lastValidationSummary, lastValidationSummary) || other.lastValidationSummary == lastValidationSummary)&&const DeepCollectionEquality().equals(other.events, events));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,taskId,status,validationStatus,updatedAt,lastRunAt,lastValidationAt,summary,blockedReason,lastValidationCommand,lastValidationSummary,const DeepCollectionEquality().hash(events));

@override
String toString() {
  return 'ConversationExecutionTaskProgress(taskId: $taskId, status: $status, validationStatus: $validationStatus, updatedAt: $updatedAt, lastRunAt: $lastRunAt, lastValidationAt: $lastValidationAt, summary: $summary, blockedReason: $blockedReason, lastValidationCommand: $lastValidationCommand, lastValidationSummary: $lastValidationSummary, events: $events)';
}


}

/// @nodoc
abstract mixin class $ConversationExecutionTaskProgressCopyWith<$Res>  {
  factory $ConversationExecutionTaskProgressCopyWith(ConversationExecutionTaskProgress value, $Res Function(ConversationExecutionTaskProgress) _then) = _$ConversationExecutionTaskProgressCopyWithImpl;
@useResult
$Res call({
 String taskId, ConversationWorkflowTaskStatus status, ConversationExecutionValidationStatus validationStatus, DateTime? updatedAt, DateTime? lastRunAt, DateTime? lastValidationAt, String summary, String blockedReason, String lastValidationCommand, String lastValidationSummary,@JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson) List<ConversationExecutionTaskEvent> events
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
@pragma('vm:prefer-inline') @override $Res call({Object? taskId = null,Object? status = null,Object? validationStatus = null,Object? updatedAt = freezed,Object? lastRunAt = freezed,Object? lastValidationAt = freezed,Object? summary = null,Object? blockedReason = null,Object? lastValidationCommand = null,Object? lastValidationSummary = null,Object? events = null,}) {
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
as String,events: null == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as List<ConversationExecutionTaskEvent>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String taskId,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  DateTime? updatedAt,  DateTime? lastRunAt,  DateTime? lastValidationAt,  String summary,  String blockedReason,  String lastValidationCommand,  String lastValidationSummary, @JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson)  List<ConversationExecutionTaskEvent> events)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress() when $default != null:
return $default(_that.taskId,_that.status,_that.validationStatus,_that.updatedAt,_that.lastRunAt,_that.lastValidationAt,_that.summary,_that.blockedReason,_that.lastValidationCommand,_that.lastValidationSummary,_that.events);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String taskId,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  DateTime? updatedAt,  DateTime? lastRunAt,  DateTime? lastValidationAt,  String summary,  String blockedReason,  String lastValidationCommand,  String lastValidationSummary, @JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson)  List<ConversationExecutionTaskEvent> events)  $default,) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress():
return $default(_that.taskId,_that.status,_that.validationStatus,_that.updatedAt,_that.lastRunAt,_that.lastValidationAt,_that.summary,_that.blockedReason,_that.lastValidationCommand,_that.lastValidationSummary,_that.events);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String taskId,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  DateTime? updatedAt,  DateTime? lastRunAt,  DateTime? lastValidationAt,  String summary,  String blockedReason,  String lastValidationCommand,  String lastValidationSummary, @JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson)  List<ConversationExecutionTaskEvent> events)?  $default,) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskProgress() when $default != null:
return $default(_that.taskId,_that.status,_that.validationStatus,_that.updatedAt,_that.lastRunAt,_that.lastValidationAt,_that.summary,_that.blockedReason,_that.lastValidationCommand,_that.lastValidationSummary,_that.events);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationExecutionTaskProgress extends ConversationExecutionTaskProgress {
  const _ConversationExecutionTaskProgress({required this.taskId, this.status = ConversationWorkflowTaskStatus.pending, this.validationStatus = ConversationExecutionValidationStatus.unknown, this.updatedAt, this.lastRunAt, this.lastValidationAt, this.summary = '', this.blockedReason = '', this.lastValidationCommand = '', this.lastValidationSummary = '', @JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson) final  List<ConversationExecutionTaskEvent> events = const <ConversationExecutionTaskEvent>[]}): _events = events,super._();
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
 final  List<ConversationExecutionTaskEvent> _events;
@override@JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson) List<ConversationExecutionTaskEvent> get events {
  if (_events is EqualUnmodifiableListView) return _events;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_events);
}


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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationExecutionTaskProgress&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationStatus, validationStatus) || other.validationStatus == validationStatus)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&(identical(other.lastValidationAt, lastValidationAt) || other.lastValidationAt == lastValidationAt)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.lastValidationCommand, lastValidationCommand) || other.lastValidationCommand == lastValidationCommand)&&(identical(other.lastValidationSummary, lastValidationSummary) || other.lastValidationSummary == lastValidationSummary)&&const DeepCollectionEquality().equals(other._events, _events));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,taskId,status,validationStatus,updatedAt,lastRunAt,lastValidationAt,summary,blockedReason,lastValidationCommand,lastValidationSummary,const DeepCollectionEquality().hash(_events));

@override
String toString() {
  return 'ConversationExecutionTaskProgress(taskId: $taskId, status: $status, validationStatus: $validationStatus, updatedAt: $updatedAt, lastRunAt: $lastRunAt, lastValidationAt: $lastValidationAt, summary: $summary, blockedReason: $blockedReason, lastValidationCommand: $lastValidationCommand, lastValidationSummary: $lastValidationSummary, events: $events)';
}


}

/// @nodoc
abstract mixin class _$ConversationExecutionTaskProgressCopyWith<$Res> implements $ConversationExecutionTaskProgressCopyWith<$Res> {
  factory _$ConversationExecutionTaskProgressCopyWith(_ConversationExecutionTaskProgress value, $Res Function(_ConversationExecutionTaskProgress) _then) = __$ConversationExecutionTaskProgressCopyWithImpl;
@override @useResult
$Res call({
 String taskId, ConversationWorkflowTaskStatus status, ConversationExecutionValidationStatus validationStatus, DateTime? updatedAt, DateTime? lastRunAt, DateTime? lastValidationAt, String summary, String blockedReason, String lastValidationCommand, String lastValidationSummary,@JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson) List<ConversationExecutionTaskEvent> events
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
@override @pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? status = null,Object? validationStatus = null,Object? updatedAt = freezed,Object? lastRunAt = freezed,Object? lastValidationAt = freezed,Object? summary = null,Object? blockedReason = null,Object? lastValidationCommand = null,Object? lastValidationSummary = null,Object? events = null,}) {
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
as String,events: null == events ? _self._events : events // ignore: cast_nullable_to_non_nullable
as List<ConversationExecutionTaskEvent>,
  ));
}


}


/// @nodoc
mixin _$ConversationExecutionTaskEvent {

 ConversationExecutionTaskEventType get type; DateTime get createdAt; String get summary; ConversationWorkflowTaskStatus get status; ConversationExecutionValidationStatus get validationStatus; String get blockedReason; String get validationCommand; String get validationSummary;
/// Create a copy of ConversationExecutionTaskEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationExecutionTaskEventCopyWith<ConversationExecutionTaskEvent> get copyWith => _$ConversationExecutionTaskEventCopyWithImpl<ConversationExecutionTaskEvent>(this as ConversationExecutionTaskEvent, _$identity);

  /// Serializes this ConversationExecutionTaskEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationExecutionTaskEvent&&(identical(other.type, type) || other.type == type)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationStatus, validationStatus) || other.validationStatus == validationStatus)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.validationCommand, validationCommand) || other.validationCommand == validationCommand)&&(identical(other.validationSummary, validationSummary) || other.validationSummary == validationSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,createdAt,summary,status,validationStatus,blockedReason,validationCommand,validationSummary);

@override
String toString() {
  return 'ConversationExecutionTaskEvent(type: $type, createdAt: $createdAt, summary: $summary, status: $status, validationStatus: $validationStatus, blockedReason: $blockedReason, validationCommand: $validationCommand, validationSummary: $validationSummary)';
}


}

/// @nodoc
abstract mixin class $ConversationExecutionTaskEventCopyWith<$Res>  {
  factory $ConversationExecutionTaskEventCopyWith(ConversationExecutionTaskEvent value, $Res Function(ConversationExecutionTaskEvent) _then) = _$ConversationExecutionTaskEventCopyWithImpl;
@useResult
$Res call({
 ConversationExecutionTaskEventType type, DateTime createdAt, String summary, ConversationWorkflowTaskStatus status, ConversationExecutionValidationStatus validationStatus, String blockedReason, String validationCommand, String validationSummary
});




}
/// @nodoc
class _$ConversationExecutionTaskEventCopyWithImpl<$Res>
    implements $ConversationExecutionTaskEventCopyWith<$Res> {
  _$ConversationExecutionTaskEventCopyWithImpl(this._self, this._then);

  final ConversationExecutionTaskEvent _self;
  final $Res Function(ConversationExecutionTaskEvent) _then;

/// Create a copy of ConversationExecutionTaskEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? createdAt = null,Object? summary = null,Object? status = null,Object? validationStatus = null,Object? blockedReason = null,Object? validationCommand = null,Object? validationSummary = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as ConversationExecutionTaskEventType,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowTaskStatus,validationStatus: null == validationStatus ? _self.validationStatus : validationStatus // ignore: cast_nullable_to_non_nullable
as ConversationExecutionValidationStatus,blockedReason: null == blockedReason ? _self.blockedReason : blockedReason // ignore: cast_nullable_to_non_nullable
as String,validationCommand: null == validationCommand ? _self.validationCommand : validationCommand // ignore: cast_nullable_to_non_nullable
as String,validationSummary: null == validationSummary ? _self.validationSummary : validationSummary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationExecutionTaskEvent].
extension ConversationExecutionTaskEventPatterns on ConversationExecutionTaskEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationExecutionTaskEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationExecutionTaskEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationExecutionTaskEvent value)  $default,){
final _that = this;
switch (_that) {
case _ConversationExecutionTaskEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationExecutionTaskEvent value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationExecutionTaskEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConversationExecutionTaskEventType type,  DateTime createdAt,  String summary,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  String blockedReason,  String validationCommand,  String validationSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskEvent() when $default != null:
return $default(_that.type,_that.createdAt,_that.summary,_that.status,_that.validationStatus,_that.blockedReason,_that.validationCommand,_that.validationSummary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConversationExecutionTaskEventType type,  DateTime createdAt,  String summary,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  String blockedReason,  String validationCommand,  String validationSummary)  $default,) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskEvent():
return $default(_that.type,_that.createdAt,_that.summary,_that.status,_that.validationStatus,_that.blockedReason,_that.validationCommand,_that.validationSummary);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConversationExecutionTaskEventType type,  DateTime createdAt,  String summary,  ConversationWorkflowTaskStatus status,  ConversationExecutionValidationStatus validationStatus,  String blockedReason,  String validationCommand,  String validationSummary)?  $default,) {final _that = this;
switch (_that) {
case _ConversationExecutionTaskEvent() when $default != null:
return $default(_that.type,_that.createdAt,_that.summary,_that.status,_that.validationStatus,_that.blockedReason,_that.validationCommand,_that.validationSummary);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationExecutionTaskEvent extends ConversationExecutionTaskEvent {
  const _ConversationExecutionTaskEvent({required this.type, required this.createdAt, this.summary = '', this.status = ConversationWorkflowTaskStatus.pending, this.validationStatus = ConversationExecutionValidationStatus.unknown, this.blockedReason = '', this.validationCommand = '', this.validationSummary = ''}): super._();
  factory _ConversationExecutionTaskEvent.fromJson(Map<String, dynamic> json) => _$ConversationExecutionTaskEventFromJson(json);

@override final  ConversationExecutionTaskEventType type;
@override final  DateTime createdAt;
@override@JsonKey() final  String summary;
@override@JsonKey() final  ConversationWorkflowTaskStatus status;
@override@JsonKey() final  ConversationExecutionValidationStatus validationStatus;
@override@JsonKey() final  String blockedReason;
@override@JsonKey() final  String validationCommand;
@override@JsonKey() final  String validationSummary;

/// Create a copy of ConversationExecutionTaskEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationExecutionTaskEventCopyWith<_ConversationExecutionTaskEvent> get copyWith => __$ConversationExecutionTaskEventCopyWithImpl<_ConversationExecutionTaskEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationExecutionTaskEventToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationExecutionTaskEvent&&(identical(other.type, type) || other.type == type)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationStatus, validationStatus) || other.validationStatus == validationStatus)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.validationCommand, validationCommand) || other.validationCommand == validationCommand)&&(identical(other.validationSummary, validationSummary) || other.validationSummary == validationSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,createdAt,summary,status,validationStatus,blockedReason,validationCommand,validationSummary);

@override
String toString() {
  return 'ConversationExecutionTaskEvent(type: $type, createdAt: $createdAt, summary: $summary, status: $status, validationStatus: $validationStatus, blockedReason: $blockedReason, validationCommand: $validationCommand, validationSummary: $validationSummary)';
}


}

/// @nodoc
abstract mixin class _$ConversationExecutionTaskEventCopyWith<$Res> implements $ConversationExecutionTaskEventCopyWith<$Res> {
  factory _$ConversationExecutionTaskEventCopyWith(_ConversationExecutionTaskEvent value, $Res Function(_ConversationExecutionTaskEvent) _then) = __$ConversationExecutionTaskEventCopyWithImpl;
@override @useResult
$Res call({
 ConversationExecutionTaskEventType type, DateTime createdAt, String summary, ConversationWorkflowTaskStatus status, ConversationExecutionValidationStatus validationStatus, String blockedReason, String validationCommand, String validationSummary
});




}
/// @nodoc
class __$ConversationExecutionTaskEventCopyWithImpl<$Res>
    implements _$ConversationExecutionTaskEventCopyWith<$Res> {
  __$ConversationExecutionTaskEventCopyWithImpl(this._self, this._then);

  final _ConversationExecutionTaskEvent _self;
  final $Res Function(_ConversationExecutionTaskEvent) _then;

/// Create a copy of ConversationExecutionTaskEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? createdAt = null,Object? summary = null,Object? status = null,Object? validationStatus = null,Object? blockedReason = null,Object? validationCommand = null,Object? validationSummary = null,}) {
  return _then(_ConversationExecutionTaskEvent(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as ConversationExecutionTaskEventType,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowTaskStatus,validationStatus: null == validationStatus ? _self.validationStatus : validationStatus // ignore: cast_nullable_to_non_nullable
as ConversationExecutionValidationStatus,blockedReason: null == blockedReason ? _self.blockedReason : blockedReason // ignore: cast_nullable_to_non_nullable
as String,validationCommand: null == validationCommand ? _self.validationCommand : validationCommand // ignore: cast_nullable_to_non_nullable
as String,validationSummary: null == validationSummary ? _self.validationSummary : validationSummary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConversationContractSourceReference {

 String get id; ConversationContractSourceKind get kind; String get locator; String get contentHash; String get section; String get toolCallId;
/// Create a copy of ConversationContractSourceReference
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationContractSourceReferenceCopyWith<ConversationContractSourceReference> get copyWith => _$ConversationContractSourceReferenceCopyWithImpl<ConversationContractSourceReference>(this as ConversationContractSourceReference, _$identity);

  /// Serializes this ConversationContractSourceReference to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationContractSourceReference&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.locator, locator) || other.locator == locator)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.section, section) || other.section == section)&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,locator,contentHash,section,toolCallId);

@override
String toString() {
  return 'ConversationContractSourceReference(id: $id, kind: $kind, locator: $locator, contentHash: $contentHash, section: $section, toolCallId: $toolCallId)';
}


}

/// @nodoc
abstract mixin class $ConversationContractSourceReferenceCopyWith<$Res>  {
  factory $ConversationContractSourceReferenceCopyWith(ConversationContractSourceReference value, $Res Function(ConversationContractSourceReference) _then) = _$ConversationContractSourceReferenceCopyWithImpl;
@useResult
$Res call({
 String id, ConversationContractSourceKind kind, String locator, String contentHash, String section, String toolCallId
});




}
/// @nodoc
class _$ConversationContractSourceReferenceCopyWithImpl<$Res>
    implements $ConversationContractSourceReferenceCopyWith<$Res> {
  _$ConversationContractSourceReferenceCopyWithImpl(this._self, this._then);

  final ConversationContractSourceReference _self;
  final $Res Function(ConversationContractSourceReference) _then;

/// Create a copy of ConversationContractSourceReference
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? locator = null,Object? contentHash = null,Object? section = null,Object? toolCallId = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ConversationContractSourceKind,locator: null == locator ? _self.locator : locator // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationContractSourceReference].
extension ConversationContractSourceReferencePatterns on ConversationContractSourceReference {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationContractSourceReference value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationContractSourceReference() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationContractSourceReference value)  $default,){
final _that = this;
switch (_that) {
case _ConversationContractSourceReference():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationContractSourceReference value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationContractSourceReference() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  ConversationContractSourceKind kind,  String locator,  String contentHash,  String section,  String toolCallId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationContractSourceReference() when $default != null:
return $default(_that.id,_that.kind,_that.locator,_that.contentHash,_that.section,_that.toolCallId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  ConversationContractSourceKind kind,  String locator,  String contentHash,  String section,  String toolCallId)  $default,) {final _that = this;
switch (_that) {
case _ConversationContractSourceReference():
return $default(_that.id,_that.kind,_that.locator,_that.contentHash,_that.section,_that.toolCallId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  ConversationContractSourceKind kind,  String locator,  String contentHash,  String section,  String toolCallId)?  $default,) {final _that = this;
switch (_that) {
case _ConversationContractSourceReference() when $default != null:
return $default(_that.id,_that.kind,_that.locator,_that.contentHash,_that.section,_that.toolCallId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationContractSourceReference extends ConversationContractSourceReference {
  const _ConversationContractSourceReference({required this.id, required this.kind, this.locator = '', this.contentHash = '', this.section = '', this.toolCallId = ''}): super._();
  factory _ConversationContractSourceReference.fromJson(Map<String, dynamic> json) => _$ConversationContractSourceReferenceFromJson(json);

@override final  String id;
@override final  ConversationContractSourceKind kind;
@override@JsonKey() final  String locator;
@override@JsonKey() final  String contentHash;
@override@JsonKey() final  String section;
@override@JsonKey() final  String toolCallId;

/// Create a copy of ConversationContractSourceReference
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationContractSourceReferenceCopyWith<_ConversationContractSourceReference> get copyWith => __$ConversationContractSourceReferenceCopyWithImpl<_ConversationContractSourceReference>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationContractSourceReferenceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationContractSourceReference&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.locator, locator) || other.locator == locator)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.section, section) || other.section == section)&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,locator,contentHash,section,toolCallId);

@override
String toString() {
  return 'ConversationContractSourceReference(id: $id, kind: $kind, locator: $locator, contentHash: $contentHash, section: $section, toolCallId: $toolCallId)';
}


}

/// @nodoc
abstract mixin class _$ConversationContractSourceReferenceCopyWith<$Res> implements $ConversationContractSourceReferenceCopyWith<$Res> {
  factory _$ConversationContractSourceReferenceCopyWith(_ConversationContractSourceReference value, $Res Function(_ConversationContractSourceReference) _then) = __$ConversationContractSourceReferenceCopyWithImpl;
@override @useResult
$Res call({
 String id, ConversationContractSourceKind kind, String locator, String contentHash, String section, String toolCallId
});




}
/// @nodoc
class __$ConversationContractSourceReferenceCopyWithImpl<$Res>
    implements _$ConversationContractSourceReferenceCopyWith<$Res> {
  __$ConversationContractSourceReferenceCopyWithImpl(this._self, this._then);

  final _ConversationContractSourceReference _self;
  final $Res Function(_ConversationContractSourceReference) _then;

/// Create a copy of ConversationContractSourceReference
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? locator = null,Object? contentHash = null,Object? section = null,Object? toolCallId = null,}) {
  return _then(_ConversationContractSourceReference(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ConversationContractSourceKind,locator: null == locator ? _self.locator : locator // ignore: cast_nullable_to_non_nullable
as String,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConversationContractItemProvenance {

 String get itemId; ConversationContractItemKind get kind; List<String> get sourceIds; bool get assumption; bool get material; bool get confirmed; String get clarificationQuestion;
/// Create a copy of ConversationContractItemProvenance
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationContractItemProvenanceCopyWith<ConversationContractItemProvenance> get copyWith => _$ConversationContractItemProvenanceCopyWithImpl<ConversationContractItemProvenance>(this as ConversationContractItemProvenance, _$identity);

  /// Serializes this ConversationContractItemProvenance to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationContractItemProvenance&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.kind, kind) || other.kind == kind)&&const DeepCollectionEquality().equals(other.sourceIds, sourceIds)&&(identical(other.assumption, assumption) || other.assumption == assumption)&&(identical(other.material, material) || other.material == material)&&(identical(other.confirmed, confirmed) || other.confirmed == confirmed)&&(identical(other.clarificationQuestion, clarificationQuestion) || other.clarificationQuestion == clarificationQuestion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,itemId,kind,const DeepCollectionEquality().hash(sourceIds),assumption,material,confirmed,clarificationQuestion);

@override
String toString() {
  return 'ConversationContractItemProvenance(itemId: $itemId, kind: $kind, sourceIds: $sourceIds, assumption: $assumption, material: $material, confirmed: $confirmed, clarificationQuestion: $clarificationQuestion)';
}


}

/// @nodoc
abstract mixin class $ConversationContractItemProvenanceCopyWith<$Res>  {
  factory $ConversationContractItemProvenanceCopyWith(ConversationContractItemProvenance value, $Res Function(ConversationContractItemProvenance) _then) = _$ConversationContractItemProvenanceCopyWithImpl;
@useResult
$Res call({
 String itemId, ConversationContractItemKind kind, List<String> sourceIds, bool assumption, bool material, bool confirmed, String clarificationQuestion
});




}
/// @nodoc
class _$ConversationContractItemProvenanceCopyWithImpl<$Res>
    implements $ConversationContractItemProvenanceCopyWith<$Res> {
  _$ConversationContractItemProvenanceCopyWithImpl(this._self, this._then);

  final ConversationContractItemProvenance _self;
  final $Res Function(ConversationContractItemProvenance) _then;

/// Create a copy of ConversationContractItemProvenance
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? itemId = null,Object? kind = null,Object? sourceIds = null,Object? assumption = null,Object? material = null,Object? confirmed = null,Object? clarificationQuestion = null,}) {
  return _then(_self.copyWith(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ConversationContractItemKind,sourceIds: null == sourceIds ? _self.sourceIds : sourceIds // ignore: cast_nullable_to_non_nullable
as List<String>,assumption: null == assumption ? _self.assumption : assumption // ignore: cast_nullable_to_non_nullable
as bool,material: null == material ? _self.material : material // ignore: cast_nullable_to_non_nullable
as bool,confirmed: null == confirmed ? _self.confirmed : confirmed // ignore: cast_nullable_to_non_nullable
as bool,clarificationQuestion: null == clarificationQuestion ? _self.clarificationQuestion : clarificationQuestion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationContractItemProvenance].
extension ConversationContractItemProvenancePatterns on ConversationContractItemProvenance {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationContractItemProvenance value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationContractItemProvenance() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationContractItemProvenance value)  $default,){
final _that = this;
switch (_that) {
case _ConversationContractItemProvenance():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationContractItemProvenance value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationContractItemProvenance() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String itemId,  ConversationContractItemKind kind,  List<String> sourceIds,  bool assumption,  bool material,  bool confirmed,  String clarificationQuestion)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationContractItemProvenance() when $default != null:
return $default(_that.itemId,_that.kind,_that.sourceIds,_that.assumption,_that.material,_that.confirmed,_that.clarificationQuestion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String itemId,  ConversationContractItemKind kind,  List<String> sourceIds,  bool assumption,  bool material,  bool confirmed,  String clarificationQuestion)  $default,) {final _that = this;
switch (_that) {
case _ConversationContractItemProvenance():
return $default(_that.itemId,_that.kind,_that.sourceIds,_that.assumption,_that.material,_that.confirmed,_that.clarificationQuestion);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String itemId,  ConversationContractItemKind kind,  List<String> sourceIds,  bool assumption,  bool material,  bool confirmed,  String clarificationQuestion)?  $default,) {final _that = this;
switch (_that) {
case _ConversationContractItemProvenance() when $default != null:
return $default(_that.itemId,_that.kind,_that.sourceIds,_that.assumption,_that.material,_that.confirmed,_that.clarificationQuestion);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationContractItemProvenance extends ConversationContractItemProvenance {
  const _ConversationContractItemProvenance({required this.itemId, required this.kind, final  List<String> sourceIds = const <String>[], this.assumption = false, this.material = false, this.confirmed = false, this.clarificationQuestion = ''}): _sourceIds = sourceIds,super._();
  factory _ConversationContractItemProvenance.fromJson(Map<String, dynamic> json) => _$ConversationContractItemProvenanceFromJson(json);

@override final  String itemId;
@override final  ConversationContractItemKind kind;
 final  List<String> _sourceIds;
@override@JsonKey() List<String> get sourceIds {
  if (_sourceIds is EqualUnmodifiableListView) return _sourceIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sourceIds);
}

@override@JsonKey() final  bool assumption;
@override@JsonKey() final  bool material;
@override@JsonKey() final  bool confirmed;
@override@JsonKey() final  String clarificationQuestion;

/// Create a copy of ConversationContractItemProvenance
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationContractItemProvenanceCopyWith<_ConversationContractItemProvenance> get copyWith => __$ConversationContractItemProvenanceCopyWithImpl<_ConversationContractItemProvenance>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationContractItemProvenanceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationContractItemProvenance&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.kind, kind) || other.kind == kind)&&const DeepCollectionEquality().equals(other._sourceIds, _sourceIds)&&(identical(other.assumption, assumption) || other.assumption == assumption)&&(identical(other.material, material) || other.material == material)&&(identical(other.confirmed, confirmed) || other.confirmed == confirmed)&&(identical(other.clarificationQuestion, clarificationQuestion) || other.clarificationQuestion == clarificationQuestion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,itemId,kind,const DeepCollectionEquality().hash(_sourceIds),assumption,material,confirmed,clarificationQuestion);

@override
String toString() {
  return 'ConversationContractItemProvenance(itemId: $itemId, kind: $kind, sourceIds: $sourceIds, assumption: $assumption, material: $material, confirmed: $confirmed, clarificationQuestion: $clarificationQuestion)';
}


}

/// @nodoc
abstract mixin class _$ConversationContractItemProvenanceCopyWith<$Res> implements $ConversationContractItemProvenanceCopyWith<$Res> {
  factory _$ConversationContractItemProvenanceCopyWith(_ConversationContractItemProvenance value, $Res Function(_ConversationContractItemProvenance) _then) = __$ConversationContractItemProvenanceCopyWithImpl;
@override @useResult
$Res call({
 String itemId, ConversationContractItemKind kind, List<String> sourceIds, bool assumption, bool material, bool confirmed, String clarificationQuestion
});




}
/// @nodoc
class __$ConversationContractItemProvenanceCopyWithImpl<$Res>
    implements _$ConversationContractItemProvenanceCopyWith<$Res> {
  __$ConversationContractItemProvenanceCopyWithImpl(this._self, this._then);

  final _ConversationContractItemProvenance _self;
  final $Res Function(_ConversationContractItemProvenance) _then;

/// Create a copy of ConversationContractItemProvenance
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? itemId = null,Object? kind = null,Object? sourceIds = null,Object? assumption = null,Object? material = null,Object? confirmed = null,Object? clarificationQuestion = null,}) {
  return _then(_ConversationContractItemProvenance(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ConversationContractItemKind,sourceIds: null == sourceIds ? _self._sourceIds : sourceIds // ignore: cast_nullable_to_non_nullable
as List<String>,assumption: null == assumption ? _self.assumption : assumption // ignore: cast_nullable_to_non_nullable
as bool,material: null == material ? _self.material : material // ignore: cast_nullable_to_non_nullable
as bool,confirmed: null == confirmed ? _self.confirmed : confirmed // ignore: cast_nullable_to_non_nullable
as bool,clarificationQuestion: null == clarificationQuestion ? _self.clarificationQuestion : clarificationQuestion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConversationWorkflowSpec {

 String get goal; List<String> get constraints; List<String> get acceptanceCriteria; List<String> get openQuestions;@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> get tasks;@JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson) List<ConversationContractSourceReference> get sources;@JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson) List<ConversationContractItemProvenance> get provenance;
/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<ConversationWorkflowSpec> get copyWith => _$ConversationWorkflowSpecCopyWithImpl<ConversationWorkflowSpec>(this as ConversationWorkflowSpec, _$identity);

  /// Serializes this ConversationWorkflowSpec to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationWorkflowSpec&&(identical(other.goal, goal) || other.goal == goal)&&const DeepCollectionEquality().equals(other.constraints, constraints)&&const DeepCollectionEquality().equals(other.acceptanceCriteria, acceptanceCriteria)&&const DeepCollectionEquality().equals(other.openQuestions, openQuestions)&&const DeepCollectionEquality().equals(other.tasks, tasks)&&const DeepCollectionEquality().equals(other.sources, sources)&&const DeepCollectionEquality().equals(other.provenance, provenance));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goal,const DeepCollectionEquality().hash(constraints),const DeepCollectionEquality().hash(acceptanceCriteria),const DeepCollectionEquality().hash(openQuestions),const DeepCollectionEquality().hash(tasks),const DeepCollectionEquality().hash(sources),const DeepCollectionEquality().hash(provenance));

@override
String toString() {
  return 'ConversationWorkflowSpec(goal: $goal, constraints: $constraints, acceptanceCriteria: $acceptanceCriteria, openQuestions: $openQuestions, tasks: $tasks, sources: $sources, provenance: $provenance)';
}


}

/// @nodoc
abstract mixin class $ConversationWorkflowSpecCopyWith<$Res>  {
  factory $ConversationWorkflowSpecCopyWith(ConversationWorkflowSpec value, $Res Function(ConversationWorkflowSpec) _then) = _$ConversationWorkflowSpecCopyWithImpl;
@useResult
$Res call({
 String goal, List<String> constraints, List<String> acceptanceCriteria, List<String> openQuestions,@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> tasks,@JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson) List<ConversationContractSourceReference> sources,@JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson) List<ConversationContractItemProvenance> provenance
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
@pragma('vm:prefer-inline') @override $Res call({Object? goal = null,Object? constraints = null,Object? acceptanceCriteria = null,Object? openQuestions = null,Object? tasks = null,Object? sources = null,Object? provenance = null,}) {
  return _then(_self.copyWith(
goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,constraints: null == constraints ? _self.constraints : constraints // ignore: cast_nullable_to_non_nullable
as List<String>,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,openQuestions: null == openQuestions ? _self.openQuestions : openQuestions // ignore: cast_nullable_to_non_nullable
as List<String>,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ConversationWorkflowTask>,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as List<ConversationContractSourceReference>,provenance: null == provenance ? _self.provenance : provenance // ignore: cast_nullable_to_non_nullable
as List<ConversationContractItemProvenance>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions, @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)  List<ConversationWorkflowTask> tasks, @JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson)  List<ConversationContractSourceReference> sources, @JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson)  List<ConversationContractItemProvenance> provenance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions,_that.tasks,_that.sources,_that.provenance);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions, @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)  List<ConversationWorkflowTask> tasks, @JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson)  List<ConversationContractSourceReference> sources, @JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson)  List<ConversationContractItemProvenance> provenance)  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec():
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions,_that.tasks,_that.sources,_that.provenance);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions, @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)  List<ConversationWorkflowTask> tasks, @JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson)  List<ConversationContractSourceReference> sources, @JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson)  List<ConversationContractItemProvenance> provenance)?  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions,_that.tasks,_that.sources,_that.provenance);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationWorkflowSpec extends ConversationWorkflowSpec {
  const _ConversationWorkflowSpec({this.goal = '', final  List<String> constraints = const <String>[], final  List<String> acceptanceCriteria = const <String>[], final  List<String> openQuestions = const <String>[], @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) final  List<ConversationWorkflowTask> tasks = const <ConversationWorkflowTask>[], @JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson) final  List<ConversationContractSourceReference> sources = const <ConversationContractSourceReference>[], @JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson) final  List<ConversationContractItemProvenance> provenance = const <ConversationContractItemProvenance>[]}): _constraints = constraints,_acceptanceCriteria = acceptanceCriteria,_openQuestions = openQuestions,_tasks = tasks,_sources = sources,_provenance = provenance,super._();
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

 final  List<ConversationContractSourceReference> _sources;
@override@JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson) List<ConversationContractSourceReference> get sources {
  if (_sources is EqualUnmodifiableListView) return _sources;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sources);
}

 final  List<ConversationContractItemProvenance> _provenance;
@override@JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson) List<ConversationContractItemProvenance> get provenance {
  if (_provenance is EqualUnmodifiableListView) return _provenance;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_provenance);
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationWorkflowSpec&&(identical(other.goal, goal) || other.goal == goal)&&const DeepCollectionEquality().equals(other._constraints, _constraints)&&const DeepCollectionEquality().equals(other._acceptanceCriteria, _acceptanceCriteria)&&const DeepCollectionEquality().equals(other._openQuestions, _openQuestions)&&const DeepCollectionEquality().equals(other._tasks, _tasks)&&const DeepCollectionEquality().equals(other._sources, _sources)&&const DeepCollectionEquality().equals(other._provenance, _provenance));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goal,const DeepCollectionEquality().hash(_constraints),const DeepCollectionEquality().hash(_acceptanceCriteria),const DeepCollectionEquality().hash(_openQuestions),const DeepCollectionEquality().hash(_tasks),const DeepCollectionEquality().hash(_sources),const DeepCollectionEquality().hash(_provenance));

@override
String toString() {
  return 'ConversationWorkflowSpec(goal: $goal, constraints: $constraints, acceptanceCriteria: $acceptanceCriteria, openQuestions: $openQuestions, tasks: $tasks, sources: $sources, provenance: $provenance)';
}


}

/// @nodoc
abstract mixin class _$ConversationWorkflowSpecCopyWith<$Res> implements $ConversationWorkflowSpecCopyWith<$Res> {
  factory _$ConversationWorkflowSpecCopyWith(_ConversationWorkflowSpec value, $Res Function(_ConversationWorkflowSpec) _then) = __$ConversationWorkflowSpecCopyWithImpl;
@override @useResult
$Res call({
 String goal, List<String> constraints, List<String> acceptanceCriteria, List<String> openQuestions,@JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson) List<ConversationWorkflowTask> tasks,@JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson) List<ConversationContractSourceReference> sources,@JsonKey(fromJson: _contractProvenanceFromJson, toJson: _contractProvenanceToJson) List<ConversationContractItemProvenance> provenance
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
@override @pragma('vm:prefer-inline') $Res call({Object? goal = null,Object? constraints = null,Object? acceptanceCriteria = null,Object? openQuestions = null,Object? tasks = null,Object? sources = null,Object? provenance = null,}) {
  return _then(_ConversationWorkflowSpec(
goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,constraints: null == constraints ? _self._constraints : constraints // ignore: cast_nullable_to_non_nullable
as List<String>,acceptanceCriteria: null == acceptanceCriteria ? _self._acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,openQuestions: null == openQuestions ? _self._openQuestions : openQuestions // ignore: cast_nullable_to_non_nullable
as List<String>,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ConversationWorkflowTask>,sources: null == sources ? _self._sources : sources // ignore: cast_nullable_to_non_nullable
as List<ConversationContractSourceReference>,provenance: null == provenance ? _self._provenance : provenance // ignore: cast_nullable_to_non_nullable
as List<ConversationContractItemProvenance>,
  ));
}


}

// dart format on
