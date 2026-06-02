// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'subagent_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SubagentTask {

 String get id; SubagentTaskStatus get status; String get description; String? get parentToolUseId; String get prompt; String get output; String get resultSummary; DateTime? get startedAt; DateTime? get finishedAt; bool get isBackground; bool get notified; String? get error;
/// Create a copy of SubagentTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubagentTaskCopyWith<SubagentTask> get copyWith => _$SubagentTaskCopyWithImpl<SubagentTask>(this as SubagentTask, _$identity);

  /// Serializes this SubagentTask to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubagentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.description, description) || other.description == description)&&(identical(other.parentToolUseId, parentToolUseId) || other.parentToolUseId == parentToolUseId)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.output, output) || other.output == output)&&(identical(other.resultSummary, resultSummary) || other.resultSummary == resultSummary)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.isBackground, isBackground) || other.isBackground == isBackground)&&(identical(other.notified, notified) || other.notified == notified)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,status,description,parentToolUseId,prompt,output,resultSummary,startedAt,finishedAt,isBackground,notified,error);

@override
String toString() {
  return 'SubagentTask(id: $id, status: $status, description: $description, parentToolUseId: $parentToolUseId, prompt: $prompt, output: $output, resultSummary: $resultSummary, startedAt: $startedAt, finishedAt: $finishedAt, isBackground: $isBackground, notified: $notified, error: $error)';
}


}

/// @nodoc
abstract mixin class $SubagentTaskCopyWith<$Res>  {
  factory $SubagentTaskCopyWith(SubagentTask value, $Res Function(SubagentTask) _then) = _$SubagentTaskCopyWithImpl;
@useResult
$Res call({
 String id, SubagentTaskStatus status, String description, String? parentToolUseId, String prompt, String output, String resultSummary, DateTime? startedAt, DateTime? finishedAt, bool isBackground, bool notified, String? error
});




}
/// @nodoc
class _$SubagentTaskCopyWithImpl<$Res>
    implements $SubagentTaskCopyWith<$Res> {
  _$SubagentTaskCopyWithImpl(this._self, this._then);

  final SubagentTask _self;
  final $Res Function(SubagentTask) _then;

/// Create a copy of SubagentTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? status = null,Object? description = null,Object? parentToolUseId = freezed,Object? prompt = null,Object? output = null,Object? resultSummary = null,Object? startedAt = freezed,Object? finishedAt = freezed,Object? isBackground = null,Object? notified = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SubagentTaskStatus,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,parentToolUseId: freezed == parentToolUseId ? _self.parentToolUseId : parentToolUseId // ignore: cast_nullable_to_non_nullable
as String?,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,resultSummary: null == resultSummary ? _self.resultSummary : resultSummary // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,isBackground: null == isBackground ? _self.isBackground : isBackground // ignore: cast_nullable_to_non_nullable
as bool,notified: null == notified ? _self.notified : notified // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SubagentTask].
extension SubagentTaskPatterns on SubagentTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubagentTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubagentTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubagentTask value)  $default,){
final _that = this;
switch (_that) {
case _SubagentTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubagentTask value)?  $default,){
final _that = this;
switch (_that) {
case _SubagentTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  SubagentTaskStatus status,  String description,  String? parentToolUseId,  String prompt,  String output,  String resultSummary,  DateTime? startedAt,  DateTime? finishedAt,  bool isBackground,  bool notified,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubagentTask() when $default != null:
return $default(_that.id,_that.status,_that.description,_that.parentToolUseId,_that.prompt,_that.output,_that.resultSummary,_that.startedAt,_that.finishedAt,_that.isBackground,_that.notified,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  SubagentTaskStatus status,  String description,  String? parentToolUseId,  String prompt,  String output,  String resultSummary,  DateTime? startedAt,  DateTime? finishedAt,  bool isBackground,  bool notified,  String? error)  $default,) {final _that = this;
switch (_that) {
case _SubagentTask():
return $default(_that.id,_that.status,_that.description,_that.parentToolUseId,_that.prompt,_that.output,_that.resultSummary,_that.startedAt,_that.finishedAt,_that.isBackground,_that.notified,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  SubagentTaskStatus status,  String description,  String? parentToolUseId,  String prompt,  String output,  String resultSummary,  DateTime? startedAt,  DateTime? finishedAt,  bool isBackground,  bool notified,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _SubagentTask() when $default != null:
return $default(_that.id,_that.status,_that.description,_that.parentToolUseId,_that.prompt,_that.output,_that.resultSummary,_that.startedAt,_that.finishedAt,_that.isBackground,_that.notified,_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SubagentTask extends SubagentTask {
  const _SubagentTask({required this.id, this.status = SubagentTaskStatus.pending, this.description = '', this.parentToolUseId, this.prompt = '', this.output = '', this.resultSummary = '', this.startedAt, this.finishedAt, this.isBackground = false, this.notified = false, this.error}): super._();
  factory _SubagentTask.fromJson(Map<String, dynamic> json) => _$SubagentTaskFromJson(json);

@override final  String id;
@override@JsonKey() final  SubagentTaskStatus status;
@override@JsonKey() final  String description;
@override final  String? parentToolUseId;
@override@JsonKey() final  String prompt;
@override@JsonKey() final  String output;
@override@JsonKey() final  String resultSummary;
@override final  DateTime? startedAt;
@override final  DateTime? finishedAt;
@override@JsonKey() final  bool isBackground;
@override@JsonKey() final  bool notified;
@override final  String? error;

/// Create a copy of SubagentTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubagentTaskCopyWith<_SubagentTask> get copyWith => __$SubagentTaskCopyWithImpl<_SubagentTask>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SubagentTaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubagentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.description, description) || other.description == description)&&(identical(other.parentToolUseId, parentToolUseId) || other.parentToolUseId == parentToolUseId)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.output, output) || other.output == output)&&(identical(other.resultSummary, resultSummary) || other.resultSummary == resultSummary)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.isBackground, isBackground) || other.isBackground == isBackground)&&(identical(other.notified, notified) || other.notified == notified)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,status,description,parentToolUseId,prompt,output,resultSummary,startedAt,finishedAt,isBackground,notified,error);

@override
String toString() {
  return 'SubagentTask(id: $id, status: $status, description: $description, parentToolUseId: $parentToolUseId, prompt: $prompt, output: $output, resultSummary: $resultSummary, startedAt: $startedAt, finishedAt: $finishedAt, isBackground: $isBackground, notified: $notified, error: $error)';
}


}

/// @nodoc
abstract mixin class _$SubagentTaskCopyWith<$Res> implements $SubagentTaskCopyWith<$Res> {
  factory _$SubagentTaskCopyWith(_SubagentTask value, $Res Function(_SubagentTask) _then) = __$SubagentTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, SubagentTaskStatus status, String description, String? parentToolUseId, String prompt, String output, String resultSummary, DateTime? startedAt, DateTime? finishedAt, bool isBackground, bool notified, String? error
});




}
/// @nodoc
class __$SubagentTaskCopyWithImpl<$Res>
    implements _$SubagentTaskCopyWith<$Res> {
  __$SubagentTaskCopyWithImpl(this._self, this._then);

  final _SubagentTask _self;
  final $Res Function(_SubagentTask) _then;

/// Create a copy of SubagentTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? status = null,Object? description = null,Object? parentToolUseId = freezed,Object? prompt = null,Object? output = null,Object? resultSummary = null,Object? startedAt = freezed,Object? finishedAt = freezed,Object? isBackground = null,Object? notified = null,Object? error = freezed,}) {
  return _then(_SubagentTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SubagentTaskStatus,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,parentToolUseId: freezed == parentToolUseId ? _self.parentToolUseId : parentToolUseId // ignore: cast_nullable_to_non_nullable
as String?,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,resultSummary: null == resultSummary ? _self.resultSummary : resultSummary // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,isBackground: null == isBackground ? _self.isBackground : isBackground // ignore: cast_nullable_to_non_nullable
as bool,notified: null == notified ? _self.notified : notified // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
