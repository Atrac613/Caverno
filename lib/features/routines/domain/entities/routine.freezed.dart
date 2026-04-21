// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoutineRunRecord {

 String get id; DateTime get startedAt; DateTime get finishedAt;@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus get status;@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger get trigger; int get durationMs; bool get usedTools; int get toolCallCount; List<String> get toolNames;@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus get deliveryStatus; DateTime? get deliveredAt; String get deliveryMessage; String get preview; String get output; String get error;
/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRunRecordCopyWith<RoutineRunRecord> get copyWith => _$RoutineRunRecordCopyWithImpl<RoutineRunRecord>(this as RoutineRunRecord, _$identity);

  /// Serializes this RoutineRunRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.usedTools, usedTools) || other.usedTools == usedTools)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&const DeepCollectionEquality().equals(other.toolNames, toolNames)&&(identical(other.deliveryStatus, deliveryStatus) || other.deliveryStatus == deliveryStatus)&&(identical(other.deliveredAt, deliveredAt) || other.deliveredAt == deliveredAt)&&(identical(other.deliveryMessage, deliveryMessage) || other.deliveryMessage == deliveryMessage)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.output, output) || other.output == output)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,startedAt,finishedAt,status,trigger,durationMs,usedTools,toolCallCount,const DeepCollectionEquality().hash(toolNames),deliveryStatus,deliveredAt,deliveryMessage,preview,output,error);

@override
String toString() {
  return 'RoutineRunRecord(id: $id, startedAt: $startedAt, finishedAt: $finishedAt, status: $status, trigger: $trigger, durationMs: $durationMs, usedTools: $usedTools, toolCallCount: $toolCallCount, toolNames: $toolNames, deliveryStatus: $deliveryStatus, deliveredAt: $deliveredAt, deliveryMessage: $deliveryMessage, preview: $preview, output: $output, error: $error)';
}


}

/// @nodoc
abstract mixin class $RoutineRunRecordCopyWith<$Res>  {
  factory $RoutineRunRecordCopyWith(RoutineRunRecord value, $Res Function(RoutineRunRecord) _then) = _$RoutineRunRecordCopyWithImpl;
@useResult
$Res call({
 String id, DateTime startedAt, DateTime finishedAt,@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus status,@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger trigger, int durationMs, bool usedTools, int toolCallCount, List<String> toolNames,@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus deliveryStatus, DateTime? deliveredAt, String deliveryMessage, String preview, String output, String error
});




}
/// @nodoc
class _$RoutineRunRecordCopyWithImpl<$Res>
    implements $RoutineRunRecordCopyWith<$Res> {
  _$RoutineRunRecordCopyWithImpl(this._self, this._then);

  final RoutineRunRecord _self;
  final $Res Function(RoutineRunRecord) _then;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? startedAt = null,Object? finishedAt = null,Object? status = null,Object? trigger = null,Object? durationMs = null,Object? usedTools = null,Object? toolCallCount = null,Object? toolNames = null,Object? deliveryStatus = null,Object? deliveredAt = freezed,Object? deliveryMessage = null,Object? preview = null,Object? output = null,Object? error = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,finishedAt: null == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoutineRunStatus,trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as RoutineRunTrigger,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,usedTools: null == usedTools ? _self.usedTools : usedTools // ignore: cast_nullable_to_non_nullable
as bool,toolCallCount: null == toolCallCount ? _self.toolCallCount : toolCallCount // ignore: cast_nullable_to_non_nullable
as int,toolNames: null == toolNames ? _self.toolNames : toolNames // ignore: cast_nullable_to_non_nullable
as List<String>,deliveryStatus: null == deliveryStatus ? _self.deliveryStatus : deliveryStatus // ignore: cast_nullable_to_non_nullable
as RoutineDeliveryStatus,deliveredAt: freezed == deliveredAt ? _self.deliveredAt : deliveredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deliveryMessage: null == deliveryMessage ? _self.deliveryMessage : deliveryMessage // ignore: cast_nullable_to_non_nullable
as String,preview: null == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as String,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineRunRecord].
extension RoutineRunRecordPatterns on RoutineRunRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineRunRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineRunRecord value)  $default,){
final _that = this;
switch (_that) {
case _RoutineRunRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineRunRecord value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error)  $default,) {final _that = this;
switch (_that) {
case _RoutineRunRecord():
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRunRecord extends RoutineRunRecord {
  const _RoutineRunRecord({required this.id, required this.startedAt, required this.finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed) this.status = RoutineRunStatus.completed, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual) this.trigger = RoutineRunTrigger.manual, this.durationMs = 0, this.usedTools = false, this.toolCallCount = 0, final  List<String> toolNames = const <String>[], @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) this.deliveryStatus = RoutineDeliveryStatus.notRequested, this.deliveredAt, this.deliveryMessage = '', this.preview = '', this.output = '', this.error = ''}): _toolNames = toolNames,super._();
  factory _RoutineRunRecord.fromJson(Map<String, dynamic> json) => _$RoutineRunRecordFromJson(json);

@override final  String id;
@override final  DateTime startedAt;
@override final  DateTime finishedAt;
@override@JsonKey(unknownEnumValue: RoutineRunStatus.completed) final  RoutineRunStatus status;
@override@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) final  RoutineRunTrigger trigger;
@override@JsonKey() final  int durationMs;
@override@JsonKey() final  bool usedTools;
@override@JsonKey() final  int toolCallCount;
 final  List<String> _toolNames;
@override@JsonKey() List<String> get toolNames {
  if (_toolNames is EqualUnmodifiableListView) return _toolNames;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_toolNames);
}

@override@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) final  RoutineDeliveryStatus deliveryStatus;
@override final  DateTime? deliveredAt;
@override@JsonKey() final  String deliveryMessage;
@override@JsonKey() final  String preview;
@override@JsonKey() final  String output;
@override@JsonKey() final  String error;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineRunRecordCopyWith<_RoutineRunRecord> get copyWith => __$RoutineRunRecordCopyWithImpl<_RoutineRunRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineRunRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.usedTools, usedTools) || other.usedTools == usedTools)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&const DeepCollectionEquality().equals(other._toolNames, _toolNames)&&(identical(other.deliveryStatus, deliveryStatus) || other.deliveryStatus == deliveryStatus)&&(identical(other.deliveredAt, deliveredAt) || other.deliveredAt == deliveredAt)&&(identical(other.deliveryMessage, deliveryMessage) || other.deliveryMessage == deliveryMessage)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.output, output) || other.output == output)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,startedAt,finishedAt,status,trigger,durationMs,usedTools,toolCallCount,const DeepCollectionEquality().hash(_toolNames),deliveryStatus,deliveredAt,deliveryMessage,preview,output,error);

@override
String toString() {
  return 'RoutineRunRecord(id: $id, startedAt: $startedAt, finishedAt: $finishedAt, status: $status, trigger: $trigger, durationMs: $durationMs, usedTools: $usedTools, toolCallCount: $toolCallCount, toolNames: $toolNames, deliveryStatus: $deliveryStatus, deliveredAt: $deliveredAt, deliveryMessage: $deliveryMessage, preview: $preview, output: $output, error: $error)';
}


}

/// @nodoc
abstract mixin class _$RoutineRunRecordCopyWith<$Res> implements $RoutineRunRecordCopyWith<$Res> {
  factory _$RoutineRunRecordCopyWith(_RoutineRunRecord value, $Res Function(_RoutineRunRecord) _then) = __$RoutineRunRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime startedAt, DateTime finishedAt,@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus status,@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger trigger, int durationMs, bool usedTools, int toolCallCount, List<String> toolNames,@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus deliveryStatus, DateTime? deliveredAt, String deliveryMessage, String preview, String output, String error
});




}
/// @nodoc
class __$RoutineRunRecordCopyWithImpl<$Res>
    implements _$RoutineRunRecordCopyWith<$Res> {
  __$RoutineRunRecordCopyWithImpl(this._self, this._then);

  final _RoutineRunRecord _self;
  final $Res Function(_RoutineRunRecord) _then;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? startedAt = null,Object? finishedAt = null,Object? status = null,Object? trigger = null,Object? durationMs = null,Object? usedTools = null,Object? toolCallCount = null,Object? toolNames = null,Object? deliveryStatus = null,Object? deliveredAt = freezed,Object? deliveryMessage = null,Object? preview = null,Object? output = null,Object? error = null,}) {
  return _then(_RoutineRunRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,finishedAt: null == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoutineRunStatus,trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as RoutineRunTrigger,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,usedTools: null == usedTools ? _self.usedTools : usedTools // ignore: cast_nullable_to_non_nullable
as bool,toolCallCount: null == toolCallCount ? _self.toolCallCount : toolCallCount // ignore: cast_nullable_to_non_nullable
as int,toolNames: null == toolNames ? _self._toolNames : toolNames // ignore: cast_nullable_to_non_nullable
as List<String>,deliveryStatus: null == deliveryStatus ? _self.deliveryStatus : deliveryStatus // ignore: cast_nullable_to_non_nullable
as RoutineDeliveryStatus,deliveredAt: freezed == deliveredAt ? _self.deliveredAt : deliveredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deliveryMessage: null == deliveryMessage ? _self.deliveryMessage : deliveryMessage // ignore: cast_nullable_to_non_nullable
as String,preview: null == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as String,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$Routine {

 String get id; String get name; String get prompt; DateTime get createdAt; DateTime get updatedAt; bool get enabled; bool get notifyOnCompletion; bool get toolsEnabled;@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction get completionAction;@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule get googleChatRule; int get intervalValue;@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit get intervalUnit; DateTime? get nextRunAt; DateTime? get lastRunAt; List<RoutineRunRecord> get runs;
/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineCopyWith<Routine> get copyWith => _$RoutineCopyWithImpl<Routine>(this as Routine, _$identity);

  /// Serializes this Routine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Routine&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.notifyOnCompletion, notifyOnCompletion) || other.notifyOnCompletion == notifyOnCompletion)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.completionAction, completionAction) || other.completionAction == completionAction)&&(identical(other.googleChatRule, googleChatRule) || other.googleChatRule == googleChatRule)&&(identical(other.intervalValue, intervalValue) || other.intervalValue == intervalValue)&&(identical(other.intervalUnit, intervalUnit) || other.intervalUnit == intervalUnit)&&(identical(other.nextRunAt, nextRunAt) || other.nextRunAt == nextRunAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&const DeepCollectionEquality().equals(other.runs, runs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,prompt,createdAt,updatedAt,enabled,notifyOnCompletion,toolsEnabled,completionAction,googleChatRule,intervalValue,intervalUnit,nextRunAt,lastRunAt,const DeepCollectionEquality().hash(runs));

@override
String toString() {
  return 'Routine(id: $id, name: $name, prompt: $prompt, createdAt: $createdAt, updatedAt: $updatedAt, enabled: $enabled, notifyOnCompletion: $notifyOnCompletion, toolsEnabled: $toolsEnabled, completionAction: $completionAction, googleChatRule: $googleChatRule, intervalValue: $intervalValue, intervalUnit: $intervalUnit, nextRunAt: $nextRunAt, lastRunAt: $lastRunAt, runs: $runs)';
}


}

/// @nodoc
abstract mixin class $RoutineCopyWith<$Res>  {
  factory $RoutineCopyWith(Routine value, $Res Function(Routine) _then) = _$RoutineCopyWithImpl;
@useResult
$Res call({
 String id, String name, String prompt, DateTime createdAt, DateTime updatedAt, bool enabled, bool notifyOnCompletion, bool toolsEnabled,@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction completionAction,@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule googleChatRule, int intervalValue,@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit intervalUnit, DateTime? nextRunAt, DateTime? lastRunAt, List<RoutineRunRecord> runs
});




}
/// @nodoc
class _$RoutineCopyWithImpl<$Res>
    implements $RoutineCopyWith<$Res> {
  _$RoutineCopyWithImpl(this._self, this._then);

  final Routine _self;
  final $Res Function(Routine) _then;

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? createdAt = null,Object? updatedAt = null,Object? enabled = null,Object? notifyOnCompletion = null,Object? toolsEnabled = null,Object? completionAction = null,Object? googleChatRule = null,Object? intervalValue = null,Object? intervalUnit = null,Object? nextRunAt = freezed,Object? lastRunAt = freezed,Object? runs = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,notifyOnCompletion: null == notifyOnCompletion ? _self.notifyOnCompletion : notifyOnCompletion // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,completionAction: null == completionAction ? _self.completionAction : completionAction // ignore: cast_nullable_to_non_nullable
as RoutineCompletionAction,googleChatRule: null == googleChatRule ? _self.googleChatRule : googleChatRule // ignore: cast_nullable_to_non_nullable
as RoutineGoogleChatRule,intervalValue: null == intervalValue ? _self.intervalValue : intervalValue // ignore: cast_nullable_to_non_nullable
as int,intervalUnit: null == intervalUnit ? _self.intervalUnit : intervalUnit // ignore: cast_nullable_to_non_nullable
as RoutineIntervalUnit,nextRunAt: freezed == nextRunAt ? _self.nextRunAt : nextRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,runs: null == runs ? _self.runs : runs // ignore: cast_nullable_to_non_nullable
as List<RoutineRunRecord>,
  ));
}

}


/// Adds pattern-matching-related methods to [Routine].
extension RoutinePatterns on Routine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Routine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Routine() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Routine value)  $default,){
final _that = this;
switch (_that) {
case _Routine():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Routine value)?  $default,){
final _that = this;
switch (_that) {
case _Routine() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Routine() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.intervalValue,_that.intervalUnit,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)  $default,) {final _that = this;
switch (_that) {
case _Routine():
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.intervalValue,_that.intervalUnit,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)?  $default,) {final _that = this;
switch (_that) {
case _Routine() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.intervalValue,_that.intervalUnit,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Routine extends Routine {
  const _Routine({required this.id, required this.name, required this.prompt, required this.createdAt, required this.updatedAt, this.enabled = true, this.notifyOnCompletion = true, this.toolsEnabled = false, @JsonKey(unknownEnumValue: RoutineCompletionAction.none) this.completionAction = RoutineCompletionAction.none, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) this.googleChatRule = RoutineGoogleChatRule.onFailure, this.intervalValue = 1, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) this.intervalUnit = RoutineIntervalUnit.hours, this.nextRunAt, this.lastRunAt, final  List<RoutineRunRecord> runs = const <RoutineRunRecord>[]}): _runs = runs,super._();
  factory _Routine.fromJson(Map<String, dynamic> json) => _$RoutineFromJson(json);

@override final  String id;
@override final  String name;
@override final  String prompt;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool notifyOnCompletion;
@override@JsonKey() final  bool toolsEnabled;
@override@JsonKey(unknownEnumValue: RoutineCompletionAction.none) final  RoutineCompletionAction completionAction;
@override@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) final  RoutineGoogleChatRule googleChatRule;
@override@JsonKey() final  int intervalValue;
@override@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) final  RoutineIntervalUnit intervalUnit;
@override final  DateTime? nextRunAt;
@override final  DateTime? lastRunAt;
 final  List<RoutineRunRecord> _runs;
@override@JsonKey() List<RoutineRunRecord> get runs {
  if (_runs is EqualUnmodifiableListView) return _runs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_runs);
}


/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineCopyWith<_Routine> get copyWith => __$RoutineCopyWithImpl<_Routine>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Routine&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.notifyOnCompletion, notifyOnCompletion) || other.notifyOnCompletion == notifyOnCompletion)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.completionAction, completionAction) || other.completionAction == completionAction)&&(identical(other.googleChatRule, googleChatRule) || other.googleChatRule == googleChatRule)&&(identical(other.intervalValue, intervalValue) || other.intervalValue == intervalValue)&&(identical(other.intervalUnit, intervalUnit) || other.intervalUnit == intervalUnit)&&(identical(other.nextRunAt, nextRunAt) || other.nextRunAt == nextRunAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&const DeepCollectionEquality().equals(other._runs, _runs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,prompt,createdAt,updatedAt,enabled,notifyOnCompletion,toolsEnabled,completionAction,googleChatRule,intervalValue,intervalUnit,nextRunAt,lastRunAt,const DeepCollectionEquality().hash(_runs));

@override
String toString() {
  return 'Routine(id: $id, name: $name, prompt: $prompt, createdAt: $createdAt, updatedAt: $updatedAt, enabled: $enabled, notifyOnCompletion: $notifyOnCompletion, toolsEnabled: $toolsEnabled, completionAction: $completionAction, googleChatRule: $googleChatRule, intervalValue: $intervalValue, intervalUnit: $intervalUnit, nextRunAt: $nextRunAt, lastRunAt: $lastRunAt, runs: $runs)';
}


}

/// @nodoc
abstract mixin class _$RoutineCopyWith<$Res> implements $RoutineCopyWith<$Res> {
  factory _$RoutineCopyWith(_Routine value, $Res Function(_Routine) _then) = __$RoutineCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String prompt, DateTime createdAt, DateTime updatedAt, bool enabled, bool notifyOnCompletion, bool toolsEnabled,@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction completionAction,@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule googleChatRule, int intervalValue,@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit intervalUnit, DateTime? nextRunAt, DateTime? lastRunAt, List<RoutineRunRecord> runs
});




}
/// @nodoc
class __$RoutineCopyWithImpl<$Res>
    implements _$RoutineCopyWith<$Res> {
  __$RoutineCopyWithImpl(this._self, this._then);

  final _Routine _self;
  final $Res Function(_Routine) _then;

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? createdAt = null,Object? updatedAt = null,Object? enabled = null,Object? notifyOnCompletion = null,Object? toolsEnabled = null,Object? completionAction = null,Object? googleChatRule = null,Object? intervalValue = null,Object? intervalUnit = null,Object? nextRunAt = freezed,Object? lastRunAt = freezed,Object? runs = null,}) {
  return _then(_Routine(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,notifyOnCompletion: null == notifyOnCompletion ? _self.notifyOnCompletion : notifyOnCompletion // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,completionAction: null == completionAction ? _self.completionAction : completionAction // ignore: cast_nullable_to_non_nullable
as RoutineCompletionAction,googleChatRule: null == googleChatRule ? _self.googleChatRule : googleChatRule // ignore: cast_nullable_to_non_nullable
as RoutineGoogleChatRule,intervalValue: null == intervalValue ? _self.intervalValue : intervalValue // ignore: cast_nullable_to_non_nullable
as int,intervalUnit: null == intervalUnit ? _self.intervalUnit : intervalUnit // ignore: cast_nullable_to_non_nullable
as RoutineIntervalUnit,nextRunAt: freezed == nextRunAt ? _self.nextRunAt : nextRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,runs: null == runs ? _self._runs : runs // ignore: cast_nullable_to_non_nullable
as List<RoutineRunRecord>,
  ));
}


}

// dart format on
