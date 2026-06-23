// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WorkflowProposalDraft {

 ConversationWorkflowStage get workflowStage; ConversationWorkflowSpec get workflowSpec;
/// Create a copy of WorkflowProposalDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowProposalDraftCopyWith<WorkflowProposalDraft> get copyWith => _$WorkflowProposalDraftCopyWithImpl<WorkflowProposalDraft>(this as WorkflowProposalDraft, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowProposalDraft&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec));
}


@override
int get hashCode => Object.hash(runtimeType,workflowStage,workflowSpec);

@override
String toString() {
  return 'WorkflowProposalDraft(workflowStage: $workflowStage, workflowSpec: $workflowSpec)';
}


}

/// @nodoc
abstract mixin class $WorkflowProposalDraftCopyWith<$Res>  {
  factory $WorkflowProposalDraftCopyWith(WorkflowProposalDraft value, $Res Function(WorkflowProposalDraft) _then) = _$WorkflowProposalDraftCopyWithImpl;
@useResult
$Res call({
 ConversationWorkflowStage workflowStage, ConversationWorkflowSpec workflowSpec
});


$ConversationWorkflowSpecCopyWith<$Res> get workflowSpec;

}
/// @nodoc
class _$WorkflowProposalDraftCopyWithImpl<$Res>
    implements $WorkflowProposalDraftCopyWith<$Res> {
  _$WorkflowProposalDraftCopyWithImpl(this._self, this._then);

  final WorkflowProposalDraft _self;
  final $Res Function(WorkflowProposalDraft) _then;

/// Create a copy of WorkflowProposalDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workflowStage = null,Object? workflowSpec = null,}) {
  return _then(_self.copyWith(
workflowStage: null == workflowStage ? _self.workflowStage : workflowStage // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowStage,workflowSpec: null == workflowSpec ? _self.workflowSpec : workflowSpec // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowSpec,
  ));
}
/// Create a copy of WorkflowProposalDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<$Res> get workflowSpec {
  
  return $ConversationWorkflowSpecCopyWith<$Res>(_self.workflowSpec, (value) {
    return _then(_self.copyWith(workflowSpec: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkflowProposalDraft].
extension WorkflowProposalDraftPatterns on WorkflowProposalDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowProposalDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowProposalDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowProposalDraft value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowProposalDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowProposalDraft value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowProposalDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConversationWorkflowStage workflowStage,  ConversationWorkflowSpec workflowSpec)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowProposalDraft() when $default != null:
return $default(_that.workflowStage,_that.workflowSpec);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConversationWorkflowStage workflowStage,  ConversationWorkflowSpec workflowSpec)  $default,) {final _that = this;
switch (_that) {
case _WorkflowProposalDraft():
return $default(_that.workflowStage,_that.workflowSpec);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConversationWorkflowStage workflowStage,  ConversationWorkflowSpec workflowSpec)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowProposalDraft() when $default != null:
return $default(_that.workflowStage,_that.workflowSpec);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowProposalDraft implements WorkflowProposalDraft {
  const _WorkflowProposalDraft({required this.workflowStage, required this.workflowSpec});
  

@override final  ConversationWorkflowStage workflowStage;
@override final  ConversationWorkflowSpec workflowSpec;

/// Create a copy of WorkflowProposalDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowProposalDraftCopyWith<_WorkflowProposalDraft> get copyWith => __$WorkflowProposalDraftCopyWithImpl<_WorkflowProposalDraft>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowProposalDraft&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec));
}


@override
int get hashCode => Object.hash(runtimeType,workflowStage,workflowSpec);

@override
String toString() {
  return 'WorkflowProposalDraft(workflowStage: $workflowStage, workflowSpec: $workflowSpec)';
}


}

/// @nodoc
abstract mixin class _$WorkflowProposalDraftCopyWith<$Res> implements $WorkflowProposalDraftCopyWith<$Res> {
  factory _$WorkflowProposalDraftCopyWith(_WorkflowProposalDraft value, $Res Function(_WorkflowProposalDraft) _then) = __$WorkflowProposalDraftCopyWithImpl;
@override @useResult
$Res call({
 ConversationWorkflowStage workflowStage, ConversationWorkflowSpec workflowSpec
});


@override $ConversationWorkflowSpecCopyWith<$Res> get workflowSpec;

}
/// @nodoc
class __$WorkflowProposalDraftCopyWithImpl<$Res>
    implements _$WorkflowProposalDraftCopyWith<$Res> {
  __$WorkflowProposalDraftCopyWithImpl(this._self, this._then);

  final _WorkflowProposalDraft _self;
  final $Res Function(_WorkflowProposalDraft) _then;

/// Create a copy of WorkflowProposalDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workflowStage = null,Object? workflowSpec = null,}) {
  return _then(_WorkflowProposalDraft(
workflowStage: null == workflowStage ? _self.workflowStage : workflowStage // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowStage,workflowSpec: null == workflowSpec ? _self.workflowSpec : workflowSpec // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowSpec,
  ));
}

/// Create a copy of WorkflowProposalDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<$Res> get workflowSpec {
  
  return $ConversationWorkflowSpecCopyWith<$Res>(_self.workflowSpec, (value) {
    return _then(_self.copyWith(workflowSpec: value));
  });
}
}

/// @nodoc
mixin _$WorkflowTaskProposalDraft {

 List<ConversationWorkflowTask> get tasks;
/// Create a copy of WorkflowTaskProposalDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowTaskProposalDraftCopyWith<WorkflowTaskProposalDraft> get copyWith => _$WorkflowTaskProposalDraftCopyWithImpl<WorkflowTaskProposalDraft>(this as WorkflowTaskProposalDraft, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowTaskProposalDraft&&const DeepCollectionEquality().equals(other.tasks, tasks));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(tasks));

@override
String toString() {
  return 'WorkflowTaskProposalDraft(tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class $WorkflowTaskProposalDraftCopyWith<$Res>  {
  factory $WorkflowTaskProposalDraftCopyWith(WorkflowTaskProposalDraft value, $Res Function(WorkflowTaskProposalDraft) _then) = _$WorkflowTaskProposalDraftCopyWithImpl;
@useResult
$Res call({
 List<ConversationWorkflowTask> tasks
});




}
/// @nodoc
class _$WorkflowTaskProposalDraftCopyWithImpl<$Res>
    implements $WorkflowTaskProposalDraftCopyWith<$Res> {
  _$WorkflowTaskProposalDraftCopyWithImpl(this._self, this._then);

  final WorkflowTaskProposalDraft _self;
  final $Res Function(WorkflowTaskProposalDraft) _then;

/// Create a copy of WorkflowTaskProposalDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tasks = null,}) {
  return _then(_self.copyWith(
tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ConversationWorkflowTask>,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowTaskProposalDraft].
extension WorkflowTaskProposalDraftPatterns on WorkflowTaskProposalDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowTaskProposalDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowTaskProposalDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowTaskProposalDraft value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowTaskProposalDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowTaskProposalDraft value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowTaskProposalDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ConversationWorkflowTask> tasks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowTaskProposalDraft() when $default != null:
return $default(_that.tasks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ConversationWorkflowTask> tasks)  $default,) {final _that = this;
switch (_that) {
case _WorkflowTaskProposalDraft():
return $default(_that.tasks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ConversationWorkflowTask> tasks)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowTaskProposalDraft() when $default != null:
return $default(_that.tasks);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowTaskProposalDraft implements WorkflowTaskProposalDraft {
  const _WorkflowTaskProposalDraft({required final  List<ConversationWorkflowTask> tasks}): _tasks = tasks;
  

 final  List<ConversationWorkflowTask> _tasks;
@override List<ConversationWorkflowTask> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}


/// Create a copy of WorkflowTaskProposalDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowTaskProposalDraftCopyWith<_WorkflowTaskProposalDraft> get copyWith => __$WorkflowTaskProposalDraftCopyWithImpl<_WorkflowTaskProposalDraft>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowTaskProposalDraft&&const DeepCollectionEquality().equals(other._tasks, _tasks));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_tasks));

@override
String toString() {
  return 'WorkflowTaskProposalDraft(tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class _$WorkflowTaskProposalDraftCopyWith<$Res> implements $WorkflowTaskProposalDraftCopyWith<$Res> {
  factory _$WorkflowTaskProposalDraftCopyWith(_WorkflowTaskProposalDraft value, $Res Function(_WorkflowTaskProposalDraft) _then) = __$WorkflowTaskProposalDraftCopyWithImpl;
@override @useResult
$Res call({
 List<ConversationWorkflowTask> tasks
});




}
/// @nodoc
class __$WorkflowTaskProposalDraftCopyWithImpl<$Res>
    implements _$WorkflowTaskProposalDraftCopyWith<$Res> {
  __$WorkflowTaskProposalDraftCopyWithImpl(this._self, this._then);

  final _WorkflowTaskProposalDraft _self;
  final $Res Function(_WorkflowTaskProposalDraft) _then;

/// Create a copy of WorkflowTaskProposalDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tasks = null,}) {
  return _then(_WorkflowTaskProposalDraft(
tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ConversationWorkflowTask>,
  ));
}


}

/// @nodoc
mixin _$ParticipantTurnRuntime {

 String? get activeParticipantId; String get activeParticipantName; String get activeParticipantRoleLabel; int? get activeParticipantColorValue; int get currentRound; int get maxRounds; bool get multiRound; bool get stopRequested; bool get paused; String get activeToolName;
/// Create a copy of ParticipantTurnRuntime
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParticipantTurnRuntimeCopyWith<ParticipantTurnRuntime> get copyWith => _$ParticipantTurnRuntimeCopyWithImpl<ParticipantTurnRuntime>(this as ParticipantTurnRuntime, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParticipantTurnRuntime&&(identical(other.activeParticipantId, activeParticipantId) || other.activeParticipantId == activeParticipantId)&&(identical(other.activeParticipantName, activeParticipantName) || other.activeParticipantName == activeParticipantName)&&(identical(other.activeParticipantRoleLabel, activeParticipantRoleLabel) || other.activeParticipantRoleLabel == activeParticipantRoleLabel)&&(identical(other.activeParticipantColorValue, activeParticipantColorValue) || other.activeParticipantColorValue == activeParticipantColorValue)&&(identical(other.currentRound, currentRound) || other.currentRound == currentRound)&&(identical(other.maxRounds, maxRounds) || other.maxRounds == maxRounds)&&(identical(other.multiRound, multiRound) || other.multiRound == multiRound)&&(identical(other.stopRequested, stopRequested) || other.stopRequested == stopRequested)&&(identical(other.paused, paused) || other.paused == paused)&&(identical(other.activeToolName, activeToolName) || other.activeToolName == activeToolName));
}


@override
int get hashCode => Object.hash(runtimeType,activeParticipantId,activeParticipantName,activeParticipantRoleLabel,activeParticipantColorValue,currentRound,maxRounds,multiRound,stopRequested,paused,activeToolName);

@override
String toString() {
  return 'ParticipantTurnRuntime(activeParticipantId: $activeParticipantId, activeParticipantName: $activeParticipantName, activeParticipantRoleLabel: $activeParticipantRoleLabel, activeParticipantColorValue: $activeParticipantColorValue, currentRound: $currentRound, maxRounds: $maxRounds, multiRound: $multiRound, stopRequested: $stopRequested, paused: $paused, activeToolName: $activeToolName)';
}


}

/// @nodoc
abstract mixin class $ParticipantTurnRuntimeCopyWith<$Res>  {
  factory $ParticipantTurnRuntimeCopyWith(ParticipantTurnRuntime value, $Res Function(ParticipantTurnRuntime) _then) = _$ParticipantTurnRuntimeCopyWithImpl;
@useResult
$Res call({
 String? activeParticipantId, String activeParticipantName, String activeParticipantRoleLabel, int? activeParticipantColorValue, int currentRound, int maxRounds, bool multiRound, bool stopRequested, bool paused, String activeToolName
});




}
/// @nodoc
class _$ParticipantTurnRuntimeCopyWithImpl<$Res>
    implements $ParticipantTurnRuntimeCopyWith<$Res> {
  _$ParticipantTurnRuntimeCopyWithImpl(this._self, this._then);

  final ParticipantTurnRuntime _self;
  final $Res Function(ParticipantTurnRuntime) _then;

/// Create a copy of ParticipantTurnRuntime
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? activeParticipantId = freezed,Object? activeParticipantName = null,Object? activeParticipantRoleLabel = null,Object? activeParticipantColorValue = freezed,Object? currentRound = null,Object? maxRounds = null,Object? multiRound = null,Object? stopRequested = null,Object? paused = null,Object? activeToolName = null,}) {
  return _then(_self.copyWith(
activeParticipantId: freezed == activeParticipantId ? _self.activeParticipantId : activeParticipantId // ignore: cast_nullable_to_non_nullable
as String?,activeParticipantName: null == activeParticipantName ? _self.activeParticipantName : activeParticipantName // ignore: cast_nullable_to_non_nullable
as String,activeParticipantRoleLabel: null == activeParticipantRoleLabel ? _self.activeParticipantRoleLabel : activeParticipantRoleLabel // ignore: cast_nullable_to_non_nullable
as String,activeParticipantColorValue: freezed == activeParticipantColorValue ? _self.activeParticipantColorValue : activeParticipantColorValue // ignore: cast_nullable_to_non_nullable
as int?,currentRound: null == currentRound ? _self.currentRound : currentRound // ignore: cast_nullable_to_non_nullable
as int,maxRounds: null == maxRounds ? _self.maxRounds : maxRounds // ignore: cast_nullable_to_non_nullable
as int,multiRound: null == multiRound ? _self.multiRound : multiRound // ignore: cast_nullable_to_non_nullable
as bool,stopRequested: null == stopRequested ? _self.stopRequested : stopRequested // ignore: cast_nullable_to_non_nullable
as bool,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,activeToolName: null == activeToolName ? _self.activeToolName : activeToolName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ParticipantTurnRuntime].
extension ParticipantTurnRuntimePatterns on ParticipantTurnRuntime {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParticipantTurnRuntime value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParticipantTurnRuntime() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParticipantTurnRuntime value)  $default,){
final _that = this;
switch (_that) {
case _ParticipantTurnRuntime():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParticipantTurnRuntime value)?  $default,){
final _that = this;
switch (_that) {
case _ParticipantTurnRuntime() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? activeParticipantId,  String activeParticipantName,  String activeParticipantRoleLabel,  int? activeParticipantColorValue,  int currentRound,  int maxRounds,  bool multiRound,  bool stopRequested,  bool paused,  String activeToolName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParticipantTurnRuntime() when $default != null:
return $default(_that.activeParticipantId,_that.activeParticipantName,_that.activeParticipantRoleLabel,_that.activeParticipantColorValue,_that.currentRound,_that.maxRounds,_that.multiRound,_that.stopRequested,_that.paused,_that.activeToolName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? activeParticipantId,  String activeParticipantName,  String activeParticipantRoleLabel,  int? activeParticipantColorValue,  int currentRound,  int maxRounds,  bool multiRound,  bool stopRequested,  bool paused,  String activeToolName)  $default,) {final _that = this;
switch (_that) {
case _ParticipantTurnRuntime():
return $default(_that.activeParticipantId,_that.activeParticipantName,_that.activeParticipantRoleLabel,_that.activeParticipantColorValue,_that.currentRound,_that.maxRounds,_that.multiRound,_that.stopRequested,_that.paused,_that.activeToolName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? activeParticipantId,  String activeParticipantName,  String activeParticipantRoleLabel,  int? activeParticipantColorValue,  int currentRound,  int maxRounds,  bool multiRound,  bool stopRequested,  bool paused,  String activeToolName)?  $default,) {final _that = this;
switch (_that) {
case _ParticipantTurnRuntime() when $default != null:
return $default(_that.activeParticipantId,_that.activeParticipantName,_that.activeParticipantRoleLabel,_that.activeParticipantColorValue,_that.currentRound,_that.maxRounds,_that.multiRound,_that.stopRequested,_that.paused,_that.activeToolName);case _:
  return null;

}
}

}

/// @nodoc


class _ParticipantTurnRuntime implements ParticipantTurnRuntime {
  const _ParticipantTurnRuntime({this.activeParticipantId, this.activeParticipantName = '', this.activeParticipantRoleLabel = '', this.activeParticipantColorValue, this.currentRound = 1, this.maxRounds = 1, this.multiRound = false, this.stopRequested = false, this.paused = false, this.activeToolName = ''});


@override final  String? activeParticipantId;
@override@JsonKey() final  String activeParticipantName;
@override@JsonKey() final  String activeParticipantRoleLabel;
@override final  int? activeParticipantColorValue;
@override@JsonKey() final  int currentRound;
@override@JsonKey() final  int maxRounds;
@override@JsonKey() final  bool multiRound;
@override@JsonKey() final  bool stopRequested;
@override@JsonKey() final  bool paused;
@override@JsonKey() final  String activeToolName;

/// Create a copy of ParticipantTurnRuntime
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParticipantTurnRuntimeCopyWith<_ParticipantTurnRuntime> get copyWith => __$ParticipantTurnRuntimeCopyWithImpl<_ParticipantTurnRuntime>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParticipantTurnRuntime&&(identical(other.activeParticipantId, activeParticipantId) || other.activeParticipantId == activeParticipantId)&&(identical(other.activeParticipantName, activeParticipantName) || other.activeParticipantName == activeParticipantName)&&(identical(other.activeParticipantRoleLabel, activeParticipantRoleLabel) || other.activeParticipantRoleLabel == activeParticipantRoleLabel)&&(identical(other.activeParticipantColorValue, activeParticipantColorValue) || other.activeParticipantColorValue == activeParticipantColorValue)&&(identical(other.currentRound, currentRound) || other.currentRound == currentRound)&&(identical(other.maxRounds, maxRounds) || other.maxRounds == maxRounds)&&(identical(other.multiRound, multiRound) || other.multiRound == multiRound)&&(identical(other.stopRequested, stopRequested) || other.stopRequested == stopRequested)&&(identical(other.paused, paused) || other.paused == paused)&&(identical(other.activeToolName, activeToolName) || other.activeToolName == activeToolName));
}


@override
int get hashCode => Object.hash(runtimeType,activeParticipantId,activeParticipantName,activeParticipantRoleLabel,activeParticipantColorValue,currentRound,maxRounds,multiRound,stopRequested,paused,activeToolName);

@override
String toString() {
  return 'ParticipantTurnRuntime(activeParticipantId: $activeParticipantId, activeParticipantName: $activeParticipantName, activeParticipantRoleLabel: $activeParticipantRoleLabel, activeParticipantColorValue: $activeParticipantColorValue, currentRound: $currentRound, maxRounds: $maxRounds, multiRound: $multiRound, stopRequested: $stopRequested, paused: $paused, activeToolName: $activeToolName)';
}


}

/// @nodoc
abstract mixin class _$ParticipantTurnRuntimeCopyWith<$Res> implements $ParticipantTurnRuntimeCopyWith<$Res> {
  factory _$ParticipantTurnRuntimeCopyWith(_ParticipantTurnRuntime value, $Res Function(_ParticipantTurnRuntime) _then) = __$ParticipantTurnRuntimeCopyWithImpl;
@override @useResult
$Res call({
 String? activeParticipantId, String activeParticipantName, String activeParticipantRoleLabel, int? activeParticipantColorValue, int currentRound, int maxRounds, bool multiRound, bool stopRequested, bool paused, String activeToolName
});




}
/// @nodoc
class __$ParticipantTurnRuntimeCopyWithImpl<$Res>
    implements _$ParticipantTurnRuntimeCopyWith<$Res> {
  __$ParticipantTurnRuntimeCopyWithImpl(this._self, this._then);

  final _ParticipantTurnRuntime _self;
  final $Res Function(_ParticipantTurnRuntime) _then;

/// Create a copy of ParticipantTurnRuntime
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? activeParticipantId = freezed,Object? activeParticipantName = null,Object? activeParticipantRoleLabel = null,Object? activeParticipantColorValue = freezed,Object? currentRound = null,Object? maxRounds = null,Object? multiRound = null,Object? stopRequested = null,Object? paused = null,Object? activeToolName = null,}) {
  return _then(_ParticipantTurnRuntime(
activeParticipantId: freezed == activeParticipantId ? _self.activeParticipantId : activeParticipantId // ignore: cast_nullable_to_non_nullable
as String?,activeParticipantName: null == activeParticipantName ? _self.activeParticipantName : activeParticipantName // ignore: cast_nullable_to_non_nullable
as String,activeParticipantRoleLabel: null == activeParticipantRoleLabel ? _self.activeParticipantRoleLabel : activeParticipantRoleLabel // ignore: cast_nullable_to_non_nullable
as String,activeParticipantColorValue: freezed == activeParticipantColorValue ? _self.activeParticipantColorValue : activeParticipantColorValue // ignore: cast_nullable_to_non_nullable
as int?,currentRound: null == currentRound ? _self.currentRound : currentRound // ignore: cast_nullable_to_non_nullable
as int,maxRounds: null == maxRounds ? _self.maxRounds : maxRounds // ignore: cast_nullable_to_non_nullable
as int,multiRound: null == multiRound ? _self.multiRound : multiRound // ignore: cast_nullable_to_non_nullable
as bool,stopRequested: null == stopRequested ? _self.stopRequested : stopRequested // ignore: cast_nullable_to_non_nullable
as bool,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,activeToolName: null == activeToolName ? _self.activeToolName : activeToolName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ChatState {

 List<Message> get messages; List<QueuedChatMessage> get queuedMessages; bool get isLoading; String? get error; int get promptTokens; int get completionTokens; int get totalTokens; int get estimatedPromptTokens; ContextTokenPressureLevel get contextTokenPressureLevel; bool get promptCompactionActive; ContextSurgeryObservationSnapshot get contextSurgerySnapshot; ParticipantTurnRuntime? get participantTurnRuntime;// SSH tool UI flow — holders contain Completers so they live outside
// the freezed equality graph.
 PendingSshConnect? get pendingSshConnect; PendingSshCommand? get pendingSshCommand;// Git tool UI flow — same Completer-based pattern as SSH.
 PendingGitCommand? get pendingGitCommand;// Local shell tool UI flow.
 PendingLocalCommand? get pendingLocalCommand;// macOS computer-use tool UI flow.
 PendingComputerUseAction? get pendingComputerUseAction;// Built-in browser sensitive-action UI flow.
 PendingBrowserAction? get pendingBrowserAction;// File mutation tool UI flow.
 PendingFileOperation? get pendingFileOperation;// BLE tool UI flow — same Completer-based pattern as SSH.
 PendingBleConnect? get pendingBleConnect;// Serial port open UI flow — same Completer-based approval as BLE.
 PendingSerialOpen? get pendingSerialOpen;// Participant read-only tool UI flow.
 PendingParticipantToolApproval? get pendingParticipantToolApproval;// Generic model-initiated question UI flow.
 PendingAskUserQuestion? get pendingAskUserQuestion;// Workflow planning choice UI flow.
 PendingWorkflowDecision? get pendingWorkflowDecision; bool get isGeneratingWorkflowProposal; WorkflowProposalDraft? get workflowProposalDraft; String? get workflowProposalError; bool get isGeneratingTaskProposal; WorkflowTaskProposalDraft? get taskProposalDraft; String? get taskProposalError;
/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatStateCopyWith<ChatState> get copyWith => _$ChatStateCopyWithImpl<ChatState>(this as ChatState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatState&&const DeepCollectionEquality().equals(other.messages, messages)&&const DeepCollectionEquality().equals(other.queuedMessages, queuedMessages)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.estimatedPromptTokens, estimatedPromptTokens) || other.estimatedPromptTokens == estimatedPromptTokens)&&(identical(other.contextTokenPressureLevel, contextTokenPressureLevel) || other.contextTokenPressureLevel == contextTokenPressureLevel)&&(identical(other.promptCompactionActive, promptCompactionActive) || other.promptCompactionActive == promptCompactionActive)&&(identical(other.contextSurgerySnapshot, contextSurgerySnapshot) || other.contextSurgerySnapshot == contextSurgerySnapshot)&&(identical(other.participantTurnRuntime, participantTurnRuntime) || other.participantTurnRuntime == participantTurnRuntime)&&(identical(other.pendingSshConnect, pendingSshConnect) || other.pendingSshConnect == pendingSshConnect)&&(identical(other.pendingSshCommand, pendingSshCommand) || other.pendingSshCommand == pendingSshCommand)&&(identical(other.pendingGitCommand, pendingGitCommand) || other.pendingGitCommand == pendingGitCommand)&&(identical(other.pendingLocalCommand, pendingLocalCommand) || other.pendingLocalCommand == pendingLocalCommand)&&(identical(other.pendingComputerUseAction, pendingComputerUseAction) || other.pendingComputerUseAction == pendingComputerUseAction)&&(identical(other.pendingBrowserAction, pendingBrowserAction) || other.pendingBrowserAction == pendingBrowserAction)&&(identical(other.pendingFileOperation, pendingFileOperation) || other.pendingFileOperation == pendingFileOperation)&&(identical(other.pendingBleConnect, pendingBleConnect) || other.pendingBleConnect == pendingBleConnect)&&(identical(other.pendingSerialOpen, pendingSerialOpen) || other.pendingSerialOpen == pendingSerialOpen)&&(identical(other.pendingParticipantToolApproval, pendingParticipantToolApproval) || other.pendingParticipantToolApproval == pendingParticipantToolApproval)&&(identical(other.pendingAskUserQuestion, pendingAskUserQuestion) || other.pendingAskUserQuestion == pendingAskUserQuestion)&&(identical(other.pendingWorkflowDecision, pendingWorkflowDecision) || other.pendingWorkflowDecision == pendingWorkflowDecision)&&(identical(other.isGeneratingWorkflowProposal, isGeneratingWorkflowProposal) || other.isGeneratingWorkflowProposal == isGeneratingWorkflowProposal)&&(identical(other.workflowProposalDraft, workflowProposalDraft) || other.workflowProposalDraft == workflowProposalDraft)&&(identical(other.workflowProposalError, workflowProposalError) || other.workflowProposalError == workflowProposalError)&&(identical(other.isGeneratingTaskProposal, isGeneratingTaskProposal) || other.isGeneratingTaskProposal == isGeneratingTaskProposal)&&(identical(other.taskProposalDraft, taskProposalDraft) || other.taskProposalDraft == taskProposalDraft)&&(identical(other.taskProposalError, taskProposalError) || other.taskProposalError == taskProposalError));
}


@override
int get hashCode => Object.hashAll([runtimeType,const DeepCollectionEquality().hash(messages),const DeepCollectionEquality().hash(queuedMessages),isLoading,error,promptTokens,completionTokens,totalTokens,estimatedPromptTokens,contextTokenPressureLevel,promptCompactionActive,contextSurgerySnapshot,participantTurnRuntime,pendingSshConnect,pendingSshCommand,pendingGitCommand,pendingLocalCommand,pendingComputerUseAction,pendingBrowserAction,pendingFileOperation,pendingBleConnect,pendingSerialOpen,pendingParticipantToolApproval,pendingAskUserQuestion,pendingWorkflowDecision,isGeneratingWorkflowProposal,workflowProposalDraft,workflowProposalError,isGeneratingTaskProposal,taskProposalDraft,taskProposalError]);

@override
String toString() {
  return 'ChatState(messages: $messages, queuedMessages: $queuedMessages, isLoading: $isLoading, error: $error, promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, estimatedPromptTokens: $estimatedPromptTokens, contextTokenPressureLevel: $contextTokenPressureLevel, promptCompactionActive: $promptCompactionActive, contextSurgerySnapshot: $contextSurgerySnapshot, participantTurnRuntime: $participantTurnRuntime, pendingSshConnect: $pendingSshConnect, pendingSshCommand: $pendingSshCommand, pendingGitCommand: $pendingGitCommand, pendingLocalCommand: $pendingLocalCommand, pendingComputerUseAction: $pendingComputerUseAction, pendingBrowserAction: $pendingBrowserAction, pendingFileOperation: $pendingFileOperation, pendingBleConnect: $pendingBleConnect, pendingSerialOpen: $pendingSerialOpen, pendingParticipantToolApproval: $pendingParticipantToolApproval, pendingAskUserQuestion: $pendingAskUserQuestion, pendingWorkflowDecision: $pendingWorkflowDecision, isGeneratingWorkflowProposal: $isGeneratingWorkflowProposal, workflowProposalDraft: $workflowProposalDraft, workflowProposalError: $workflowProposalError, isGeneratingTaskProposal: $isGeneratingTaskProposal, taskProposalDraft: $taskProposalDraft, taskProposalError: $taskProposalError)';
}


}

/// @nodoc
abstract mixin class $ChatStateCopyWith<$Res>  {
  factory $ChatStateCopyWith(ChatState value, $Res Function(ChatState) _then) = _$ChatStateCopyWithImpl;
@useResult
$Res call({
 List<Message> messages, List<QueuedChatMessage> queuedMessages, bool isLoading, String? error, int promptTokens, int completionTokens, int totalTokens, int estimatedPromptTokens, ContextTokenPressureLevel contextTokenPressureLevel, bool promptCompactionActive, ContextSurgeryObservationSnapshot contextSurgerySnapshot, ParticipantTurnRuntime? participantTurnRuntime, PendingSshConnect? pendingSshConnect, PendingSshCommand? pendingSshCommand, PendingGitCommand? pendingGitCommand, PendingLocalCommand? pendingLocalCommand, PendingComputerUseAction? pendingComputerUseAction, PendingBrowserAction? pendingBrowserAction, PendingFileOperation? pendingFileOperation, PendingBleConnect? pendingBleConnect, PendingSerialOpen? pendingSerialOpen, PendingParticipantToolApproval? pendingParticipantToolApproval, PendingAskUserQuestion? pendingAskUserQuestion, PendingWorkflowDecision? pendingWorkflowDecision, bool isGeneratingWorkflowProposal, WorkflowProposalDraft? workflowProposalDraft, String? workflowProposalError, bool isGeneratingTaskProposal, WorkflowTaskProposalDraft? taskProposalDraft, String? taskProposalError
});


$ParticipantTurnRuntimeCopyWith<$Res>? get participantTurnRuntime;$WorkflowProposalDraftCopyWith<$Res>? get workflowProposalDraft;$WorkflowTaskProposalDraftCopyWith<$Res>? get taskProposalDraft;

}
/// @nodoc
class _$ChatStateCopyWithImpl<$Res>
    implements $ChatStateCopyWith<$Res> {
  _$ChatStateCopyWithImpl(this._self, this._then);

  final ChatState _self;
  final $Res Function(ChatState) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? messages = null,Object? queuedMessages = null,Object? isLoading = null,Object? error = freezed,Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? estimatedPromptTokens = null,Object? contextTokenPressureLevel = null,Object? promptCompactionActive = null,Object? contextSurgerySnapshot = null,Object? participantTurnRuntime = freezed,Object? pendingSshConnect = freezed,Object? pendingSshCommand = freezed,Object? pendingGitCommand = freezed,Object? pendingLocalCommand = freezed,Object? pendingComputerUseAction = freezed,Object? pendingBrowserAction = freezed,Object? pendingFileOperation = freezed,Object? pendingBleConnect = freezed,Object? pendingSerialOpen = freezed,Object? pendingParticipantToolApproval = freezed,Object? pendingAskUserQuestion = freezed,Object? pendingWorkflowDecision = freezed,Object? isGeneratingWorkflowProposal = null,Object? workflowProposalDraft = freezed,Object? workflowProposalError = freezed,Object? isGeneratingTaskProposal = null,Object? taskProposalDraft = freezed,Object? taskProposalError = freezed,}) {
  return _then(_self.copyWith(
messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,queuedMessages: null == queuedMessages ? _self.queuedMessages : queuedMessages // ignore: cast_nullable_to_non_nullable
as List<QueuedChatMessage>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,estimatedPromptTokens: null == estimatedPromptTokens ? _self.estimatedPromptTokens : estimatedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,contextTokenPressureLevel: null == contextTokenPressureLevel ? _self.contextTokenPressureLevel : contextTokenPressureLevel // ignore: cast_nullable_to_non_nullable
as ContextTokenPressureLevel,promptCompactionActive: null == promptCompactionActive ? _self.promptCompactionActive : promptCompactionActive // ignore: cast_nullable_to_non_nullable
as bool,contextSurgerySnapshot: null == contextSurgerySnapshot ? _self.contextSurgerySnapshot : contextSurgerySnapshot // ignore: cast_nullable_to_non_nullable
as ContextSurgeryObservationSnapshot,participantTurnRuntime: freezed == participantTurnRuntime ? _self.participantTurnRuntime : participantTurnRuntime // ignore: cast_nullable_to_non_nullable
as ParticipantTurnRuntime?,pendingSshConnect: freezed == pendingSshConnect ? _self.pendingSshConnect : pendingSshConnect // ignore: cast_nullable_to_non_nullable
as PendingSshConnect?,pendingSshCommand: freezed == pendingSshCommand ? _self.pendingSshCommand : pendingSshCommand // ignore: cast_nullable_to_non_nullable
as PendingSshCommand?,pendingGitCommand: freezed == pendingGitCommand ? _self.pendingGitCommand : pendingGitCommand // ignore: cast_nullable_to_non_nullable
as PendingGitCommand?,pendingLocalCommand: freezed == pendingLocalCommand ? _self.pendingLocalCommand : pendingLocalCommand // ignore: cast_nullable_to_non_nullable
as PendingLocalCommand?,pendingComputerUseAction: freezed == pendingComputerUseAction ? _self.pendingComputerUseAction : pendingComputerUseAction // ignore: cast_nullable_to_non_nullable
as PendingComputerUseAction?,pendingBrowserAction: freezed == pendingBrowserAction ? _self.pendingBrowserAction : pendingBrowserAction // ignore: cast_nullable_to_non_nullable
as PendingBrowserAction?,pendingFileOperation: freezed == pendingFileOperation ? _self.pendingFileOperation : pendingFileOperation // ignore: cast_nullable_to_non_nullable
as PendingFileOperation?,pendingBleConnect: freezed == pendingBleConnect ? _self.pendingBleConnect : pendingBleConnect // ignore: cast_nullable_to_non_nullable
as PendingBleConnect?,pendingSerialOpen: freezed == pendingSerialOpen ? _self.pendingSerialOpen : pendingSerialOpen // ignore: cast_nullable_to_non_nullable
as PendingSerialOpen?,pendingParticipantToolApproval: freezed == pendingParticipantToolApproval ? _self.pendingParticipantToolApproval : pendingParticipantToolApproval // ignore: cast_nullable_to_non_nullable
as PendingParticipantToolApproval?,pendingAskUserQuestion: freezed == pendingAskUserQuestion ? _self.pendingAskUserQuestion : pendingAskUserQuestion // ignore: cast_nullable_to_non_nullable
as PendingAskUserQuestion?,pendingWorkflowDecision: freezed == pendingWorkflowDecision ? _self.pendingWorkflowDecision : pendingWorkflowDecision // ignore: cast_nullable_to_non_nullable
as PendingWorkflowDecision?,isGeneratingWorkflowProposal: null == isGeneratingWorkflowProposal ? _self.isGeneratingWorkflowProposal : isGeneratingWorkflowProposal // ignore: cast_nullable_to_non_nullable
as bool,workflowProposalDraft: freezed == workflowProposalDraft ? _self.workflowProposalDraft : workflowProposalDraft // ignore: cast_nullable_to_non_nullable
as WorkflowProposalDraft?,workflowProposalError: freezed == workflowProposalError ? _self.workflowProposalError : workflowProposalError // ignore: cast_nullable_to_non_nullable
as String?,isGeneratingTaskProposal: null == isGeneratingTaskProposal ? _self.isGeneratingTaskProposal : isGeneratingTaskProposal // ignore: cast_nullable_to_non_nullable
as bool,taskProposalDraft: freezed == taskProposalDraft ? _self.taskProposalDraft : taskProposalDraft // ignore: cast_nullable_to_non_nullable
as WorkflowTaskProposalDraft?,taskProposalError: freezed == taskProposalError ? _self.taskProposalError : taskProposalError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ParticipantTurnRuntimeCopyWith<$Res>? get participantTurnRuntime {
    if (_self.participantTurnRuntime == null) {
    return null;
  }

  return $ParticipantTurnRuntimeCopyWith<$Res>(_self.participantTurnRuntime!, (value) {
    return _then(_self.copyWith(participantTurnRuntime: value));
  });
}/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowProposalDraftCopyWith<$Res>? get workflowProposalDraft {
    if (_self.workflowProposalDraft == null) {
    return null;
  }

  return $WorkflowProposalDraftCopyWith<$Res>(_self.workflowProposalDraft!, (value) {
    return _then(_self.copyWith(workflowProposalDraft: value));
  });
}/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowTaskProposalDraftCopyWith<$Res>? get taskProposalDraft {
    if (_self.taskProposalDraft == null) {
    return null;
  }

  return $WorkflowTaskProposalDraftCopyWith<$Res>(_self.taskProposalDraft!, (value) {
    return _then(_self.copyWith(taskProposalDraft: value));
  });
}
}


/// Adds pattern-matching-related methods to [ChatState].
extension ChatStatePatterns on ChatState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatState value)  $default,){
final _that = this;
switch (_that) {
case _ChatState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatState value)?  $default,){
final _that = this;
switch (_that) {
case _ChatState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Message> messages,  List<QueuedChatMessage> queuedMessages,  bool isLoading,  String? error,  int promptTokens,  int completionTokens,  int totalTokens,  int estimatedPromptTokens,  ContextTokenPressureLevel contextTokenPressureLevel,  bool promptCompactionActive,  ContextSurgeryObservationSnapshot contextSurgerySnapshot,  ParticipantTurnRuntime? participantTurnRuntime,  PendingSshConnect? pendingSshConnect,  PendingSshCommand? pendingSshCommand,  PendingGitCommand? pendingGitCommand,  PendingLocalCommand? pendingLocalCommand,  PendingComputerUseAction? pendingComputerUseAction,  PendingBrowserAction? pendingBrowserAction,  PendingFileOperation? pendingFileOperation,  PendingBleConnect? pendingBleConnect,  PendingSerialOpen? pendingSerialOpen,  PendingParticipantToolApproval? pendingParticipantToolApproval,  PendingAskUserQuestion? pendingAskUserQuestion,  PendingWorkflowDecision? pendingWorkflowDecision,  bool isGeneratingWorkflowProposal,  WorkflowProposalDraft? workflowProposalDraft,  String? workflowProposalError,  bool isGeneratingTaskProposal,  WorkflowTaskProposalDraft? taskProposalDraft,  String? taskProposalError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that.messages,_that.queuedMessages,_that.isLoading,_that.error,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.estimatedPromptTokens,_that.contextTokenPressureLevel,_that.promptCompactionActive,_that.contextSurgerySnapshot,_that.participantTurnRuntime,_that.pendingSshConnect,_that.pendingSshCommand,_that.pendingGitCommand,_that.pendingLocalCommand,_that.pendingComputerUseAction,_that.pendingBrowserAction,_that.pendingFileOperation,_that.pendingBleConnect,_that.pendingSerialOpen,_that.pendingParticipantToolApproval,_that.pendingAskUserQuestion,_that.pendingWorkflowDecision,_that.isGeneratingWorkflowProposal,_that.workflowProposalDraft,_that.workflowProposalError,_that.isGeneratingTaskProposal,_that.taskProposalDraft,_that.taskProposalError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Message> messages,  List<QueuedChatMessage> queuedMessages,  bool isLoading,  String? error,  int promptTokens,  int completionTokens,  int totalTokens,  int estimatedPromptTokens,  ContextTokenPressureLevel contextTokenPressureLevel,  bool promptCompactionActive,  ContextSurgeryObservationSnapshot contextSurgerySnapshot,  ParticipantTurnRuntime? participantTurnRuntime,  PendingSshConnect? pendingSshConnect,  PendingSshCommand? pendingSshCommand,  PendingGitCommand? pendingGitCommand,  PendingLocalCommand? pendingLocalCommand,  PendingComputerUseAction? pendingComputerUseAction,  PendingBrowserAction? pendingBrowserAction,  PendingFileOperation? pendingFileOperation,  PendingBleConnect? pendingBleConnect,  PendingSerialOpen? pendingSerialOpen,  PendingParticipantToolApproval? pendingParticipantToolApproval,  PendingAskUserQuestion? pendingAskUserQuestion,  PendingWorkflowDecision? pendingWorkflowDecision,  bool isGeneratingWorkflowProposal,  WorkflowProposalDraft? workflowProposalDraft,  String? workflowProposalError,  bool isGeneratingTaskProposal,  WorkflowTaskProposalDraft? taskProposalDraft,  String? taskProposalError)  $default,) {final _that = this;
switch (_that) {
case _ChatState():
return $default(_that.messages,_that.queuedMessages,_that.isLoading,_that.error,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.estimatedPromptTokens,_that.contextTokenPressureLevel,_that.promptCompactionActive,_that.contextSurgerySnapshot,_that.participantTurnRuntime,_that.pendingSshConnect,_that.pendingSshCommand,_that.pendingGitCommand,_that.pendingLocalCommand,_that.pendingComputerUseAction,_that.pendingBrowserAction,_that.pendingFileOperation,_that.pendingBleConnect,_that.pendingSerialOpen,_that.pendingParticipantToolApproval,_that.pendingAskUserQuestion,_that.pendingWorkflowDecision,_that.isGeneratingWorkflowProposal,_that.workflowProposalDraft,_that.workflowProposalError,_that.isGeneratingTaskProposal,_that.taskProposalDraft,_that.taskProposalError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Message> messages,  List<QueuedChatMessage> queuedMessages,  bool isLoading,  String? error,  int promptTokens,  int completionTokens,  int totalTokens,  int estimatedPromptTokens,  ContextTokenPressureLevel contextTokenPressureLevel,  bool promptCompactionActive,  ContextSurgeryObservationSnapshot contextSurgerySnapshot,  ParticipantTurnRuntime? participantTurnRuntime,  PendingSshConnect? pendingSshConnect,  PendingSshCommand? pendingSshCommand,  PendingGitCommand? pendingGitCommand,  PendingLocalCommand? pendingLocalCommand,  PendingComputerUseAction? pendingComputerUseAction,  PendingBrowserAction? pendingBrowserAction,  PendingFileOperation? pendingFileOperation,  PendingBleConnect? pendingBleConnect,  PendingSerialOpen? pendingSerialOpen,  PendingParticipantToolApproval? pendingParticipantToolApproval,  PendingAskUserQuestion? pendingAskUserQuestion,  PendingWorkflowDecision? pendingWorkflowDecision,  bool isGeneratingWorkflowProposal,  WorkflowProposalDraft? workflowProposalDraft,  String? workflowProposalError,  bool isGeneratingTaskProposal,  WorkflowTaskProposalDraft? taskProposalDraft,  String? taskProposalError)?  $default,) {final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that.messages,_that.queuedMessages,_that.isLoading,_that.error,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.estimatedPromptTokens,_that.contextTokenPressureLevel,_that.promptCompactionActive,_that.contextSurgerySnapshot,_that.participantTurnRuntime,_that.pendingSshConnect,_that.pendingSshCommand,_that.pendingGitCommand,_that.pendingLocalCommand,_that.pendingComputerUseAction,_that.pendingBrowserAction,_that.pendingFileOperation,_that.pendingBleConnect,_that.pendingSerialOpen,_that.pendingParticipantToolApproval,_that.pendingAskUserQuestion,_that.pendingWorkflowDecision,_that.isGeneratingWorkflowProposal,_that.workflowProposalDraft,_that.workflowProposalError,_that.isGeneratingTaskProposal,_that.taskProposalDraft,_that.taskProposalError);case _:
  return null;

}
}

}

/// @nodoc


class _ChatState implements ChatState {
  const _ChatState({required final  List<Message> messages, final  List<QueuedChatMessage> queuedMessages = const [], required this.isLoading, this.error, this.promptTokens = 0, this.completionTokens = 0, this.totalTokens = 0, this.estimatedPromptTokens = 0, this.contextTokenPressureLevel = ContextTokenPressureLevel.normal, this.promptCompactionActive = false, this.contextSurgerySnapshot = ContextSurgeryObservationSnapshot.empty, this.participantTurnRuntime, this.pendingSshConnect, this.pendingSshCommand, this.pendingGitCommand, this.pendingLocalCommand, this.pendingComputerUseAction, this.pendingBrowserAction, this.pendingFileOperation, this.pendingBleConnect, this.pendingSerialOpen, this.pendingParticipantToolApproval, this.pendingAskUserQuestion, this.pendingWorkflowDecision, this.isGeneratingWorkflowProposal = false, this.workflowProposalDraft, this.workflowProposalError, this.isGeneratingTaskProposal = false, this.taskProposalDraft, this.taskProposalError}): _messages = messages,_queuedMessages = queuedMessages;
  

 final  List<Message> _messages;
@override List<Message> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

 final  List<QueuedChatMessage> _queuedMessages;
@override@JsonKey() List<QueuedChatMessage> get queuedMessages {
  if (_queuedMessages is EqualUnmodifiableListView) return _queuedMessages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_queuedMessages);
}

@override final  bool isLoading;
@override final  String? error;
@override@JsonKey() final  int promptTokens;
@override@JsonKey() final  int completionTokens;
@override@JsonKey() final  int totalTokens;
@override@JsonKey() final  int estimatedPromptTokens;
@override@JsonKey() final  ContextTokenPressureLevel contextTokenPressureLevel;
@override@JsonKey() final  bool promptCompactionActive;
@override@JsonKey() final  ContextSurgeryObservationSnapshot contextSurgerySnapshot;
@override final  ParticipantTurnRuntime? participantTurnRuntime;
// SSH tool UI flow — holders contain Completers so they live outside
// the freezed equality graph.
@override final  PendingSshConnect? pendingSshConnect;
@override final  PendingSshCommand? pendingSshCommand;
// Git tool UI flow — same Completer-based pattern as SSH.
@override final  PendingGitCommand? pendingGitCommand;
// Local shell tool UI flow.
@override final  PendingLocalCommand? pendingLocalCommand;
// macOS computer-use tool UI flow.
@override final  PendingComputerUseAction? pendingComputerUseAction;
// Built-in browser sensitive-action UI flow.
@override final  PendingBrowserAction? pendingBrowserAction;
// File mutation tool UI flow.
@override final  PendingFileOperation? pendingFileOperation;
// BLE tool UI flow — same Completer-based pattern as SSH.
@override final  PendingBleConnect? pendingBleConnect;
// Serial port open UI flow — same Completer-based approval as BLE.
@override final  PendingSerialOpen? pendingSerialOpen;
// Participant read-only tool UI flow.
@override final  PendingParticipantToolApproval? pendingParticipantToolApproval;
// Generic model-initiated question UI flow.
@override final  PendingAskUserQuestion? pendingAskUserQuestion;
// Workflow planning choice UI flow.
@override final  PendingWorkflowDecision? pendingWorkflowDecision;
@override@JsonKey() final  bool isGeneratingWorkflowProposal;
@override final  WorkflowProposalDraft? workflowProposalDraft;
@override final  String? workflowProposalError;
@override@JsonKey() final  bool isGeneratingTaskProposal;
@override final  WorkflowTaskProposalDraft? taskProposalDraft;
@override final  String? taskProposalError;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatStateCopyWith<_ChatState> get copyWith => __$ChatStateCopyWithImpl<_ChatState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatState&&const DeepCollectionEquality().equals(other._messages, _messages)&&const DeepCollectionEquality().equals(other._queuedMessages, _queuedMessages)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.estimatedPromptTokens, estimatedPromptTokens) || other.estimatedPromptTokens == estimatedPromptTokens)&&(identical(other.contextTokenPressureLevel, contextTokenPressureLevel) || other.contextTokenPressureLevel == contextTokenPressureLevel)&&(identical(other.promptCompactionActive, promptCompactionActive) || other.promptCompactionActive == promptCompactionActive)&&(identical(other.contextSurgerySnapshot, contextSurgerySnapshot) || other.contextSurgerySnapshot == contextSurgerySnapshot)&&(identical(other.participantTurnRuntime, participantTurnRuntime) || other.participantTurnRuntime == participantTurnRuntime)&&(identical(other.pendingSshConnect, pendingSshConnect) || other.pendingSshConnect == pendingSshConnect)&&(identical(other.pendingSshCommand, pendingSshCommand) || other.pendingSshCommand == pendingSshCommand)&&(identical(other.pendingGitCommand, pendingGitCommand) || other.pendingGitCommand == pendingGitCommand)&&(identical(other.pendingLocalCommand, pendingLocalCommand) || other.pendingLocalCommand == pendingLocalCommand)&&(identical(other.pendingComputerUseAction, pendingComputerUseAction) || other.pendingComputerUseAction == pendingComputerUseAction)&&(identical(other.pendingBrowserAction, pendingBrowserAction) || other.pendingBrowserAction == pendingBrowserAction)&&(identical(other.pendingFileOperation, pendingFileOperation) || other.pendingFileOperation == pendingFileOperation)&&(identical(other.pendingBleConnect, pendingBleConnect) || other.pendingBleConnect == pendingBleConnect)&&(identical(other.pendingSerialOpen, pendingSerialOpen) || other.pendingSerialOpen == pendingSerialOpen)&&(identical(other.pendingParticipantToolApproval, pendingParticipantToolApproval) || other.pendingParticipantToolApproval == pendingParticipantToolApproval)&&(identical(other.pendingAskUserQuestion, pendingAskUserQuestion) || other.pendingAskUserQuestion == pendingAskUserQuestion)&&(identical(other.pendingWorkflowDecision, pendingWorkflowDecision) || other.pendingWorkflowDecision == pendingWorkflowDecision)&&(identical(other.isGeneratingWorkflowProposal, isGeneratingWorkflowProposal) || other.isGeneratingWorkflowProposal == isGeneratingWorkflowProposal)&&(identical(other.workflowProposalDraft, workflowProposalDraft) || other.workflowProposalDraft == workflowProposalDraft)&&(identical(other.workflowProposalError, workflowProposalError) || other.workflowProposalError == workflowProposalError)&&(identical(other.isGeneratingTaskProposal, isGeneratingTaskProposal) || other.isGeneratingTaskProposal == isGeneratingTaskProposal)&&(identical(other.taskProposalDraft, taskProposalDraft) || other.taskProposalDraft == taskProposalDraft)&&(identical(other.taskProposalError, taskProposalError) || other.taskProposalError == taskProposalError));
}


@override
int get hashCode => Object.hashAll([runtimeType,const DeepCollectionEquality().hash(_messages),const DeepCollectionEquality().hash(_queuedMessages),isLoading,error,promptTokens,completionTokens,totalTokens,estimatedPromptTokens,contextTokenPressureLevel,promptCompactionActive,contextSurgerySnapshot,participantTurnRuntime,pendingSshConnect,pendingSshCommand,pendingGitCommand,pendingLocalCommand,pendingComputerUseAction,pendingBrowserAction,pendingFileOperation,pendingBleConnect,pendingSerialOpen,pendingParticipantToolApproval,pendingAskUserQuestion,pendingWorkflowDecision,isGeneratingWorkflowProposal,workflowProposalDraft,workflowProposalError,isGeneratingTaskProposal,taskProposalDraft,taskProposalError]);

@override
String toString() {
  return 'ChatState(messages: $messages, queuedMessages: $queuedMessages, isLoading: $isLoading, error: $error, promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, estimatedPromptTokens: $estimatedPromptTokens, contextTokenPressureLevel: $contextTokenPressureLevel, promptCompactionActive: $promptCompactionActive, contextSurgerySnapshot: $contextSurgerySnapshot, participantTurnRuntime: $participantTurnRuntime, pendingSshConnect: $pendingSshConnect, pendingSshCommand: $pendingSshCommand, pendingGitCommand: $pendingGitCommand, pendingLocalCommand: $pendingLocalCommand, pendingComputerUseAction: $pendingComputerUseAction, pendingBrowserAction: $pendingBrowserAction, pendingFileOperation: $pendingFileOperation, pendingBleConnect: $pendingBleConnect, pendingSerialOpen: $pendingSerialOpen, pendingParticipantToolApproval: $pendingParticipantToolApproval, pendingAskUserQuestion: $pendingAskUserQuestion, pendingWorkflowDecision: $pendingWorkflowDecision, isGeneratingWorkflowProposal: $isGeneratingWorkflowProposal, workflowProposalDraft: $workflowProposalDraft, workflowProposalError: $workflowProposalError, isGeneratingTaskProposal: $isGeneratingTaskProposal, taskProposalDraft: $taskProposalDraft, taskProposalError: $taskProposalError)';
}


}

/// @nodoc
abstract mixin class _$ChatStateCopyWith<$Res> implements $ChatStateCopyWith<$Res> {
  factory _$ChatStateCopyWith(_ChatState value, $Res Function(_ChatState) _then) = __$ChatStateCopyWithImpl;
@override @useResult
$Res call({
 List<Message> messages, List<QueuedChatMessage> queuedMessages, bool isLoading, String? error, int promptTokens, int completionTokens, int totalTokens, int estimatedPromptTokens, ContextTokenPressureLevel contextTokenPressureLevel, bool promptCompactionActive, ContextSurgeryObservationSnapshot contextSurgerySnapshot, ParticipantTurnRuntime? participantTurnRuntime, PendingSshConnect? pendingSshConnect, PendingSshCommand? pendingSshCommand, PendingGitCommand? pendingGitCommand, PendingLocalCommand? pendingLocalCommand, PendingComputerUseAction? pendingComputerUseAction, PendingBrowserAction? pendingBrowserAction, PendingFileOperation? pendingFileOperation, PendingBleConnect? pendingBleConnect, PendingSerialOpen? pendingSerialOpen, PendingParticipantToolApproval? pendingParticipantToolApproval, PendingAskUserQuestion? pendingAskUserQuestion, PendingWorkflowDecision? pendingWorkflowDecision, bool isGeneratingWorkflowProposal, WorkflowProposalDraft? workflowProposalDraft, String? workflowProposalError, bool isGeneratingTaskProposal, WorkflowTaskProposalDraft? taskProposalDraft, String? taskProposalError
});


@override $ParticipantTurnRuntimeCopyWith<$Res>? get participantTurnRuntime;@override $WorkflowProposalDraftCopyWith<$Res>? get workflowProposalDraft;@override $WorkflowTaskProposalDraftCopyWith<$Res>? get taskProposalDraft;

}
/// @nodoc
class __$ChatStateCopyWithImpl<$Res>
    implements _$ChatStateCopyWith<$Res> {
  __$ChatStateCopyWithImpl(this._self, this._then);

  final _ChatState _self;
  final $Res Function(_ChatState) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? messages = null,Object? queuedMessages = null,Object? isLoading = null,Object? error = freezed,Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? estimatedPromptTokens = null,Object? contextTokenPressureLevel = null,Object? promptCompactionActive = null,Object? contextSurgerySnapshot = null,Object? participantTurnRuntime = freezed,Object? pendingSshConnect = freezed,Object? pendingSshCommand = freezed,Object? pendingGitCommand = freezed,Object? pendingLocalCommand = freezed,Object? pendingComputerUseAction = freezed,Object? pendingBrowserAction = freezed,Object? pendingFileOperation = freezed,Object? pendingBleConnect = freezed,Object? pendingSerialOpen = freezed,Object? pendingParticipantToolApproval = freezed,Object? pendingAskUserQuestion = freezed,Object? pendingWorkflowDecision = freezed,Object? isGeneratingWorkflowProposal = null,Object? workflowProposalDraft = freezed,Object? workflowProposalError = freezed,Object? isGeneratingTaskProposal = null,Object? taskProposalDraft = freezed,Object? taskProposalError = freezed,}) {
  return _then(_ChatState(
messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,queuedMessages: null == queuedMessages ? _self._queuedMessages : queuedMessages // ignore: cast_nullable_to_non_nullable
as List<QueuedChatMessage>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,estimatedPromptTokens: null == estimatedPromptTokens ? _self.estimatedPromptTokens : estimatedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,contextTokenPressureLevel: null == contextTokenPressureLevel ? _self.contextTokenPressureLevel : contextTokenPressureLevel // ignore: cast_nullable_to_non_nullable
as ContextTokenPressureLevel,promptCompactionActive: null == promptCompactionActive ? _self.promptCompactionActive : promptCompactionActive // ignore: cast_nullable_to_non_nullable
as bool,contextSurgerySnapshot: null == contextSurgerySnapshot ? _self.contextSurgerySnapshot : contextSurgerySnapshot // ignore: cast_nullable_to_non_nullable
as ContextSurgeryObservationSnapshot,participantTurnRuntime: freezed == participantTurnRuntime ? _self.participantTurnRuntime : participantTurnRuntime // ignore: cast_nullable_to_non_nullable
as ParticipantTurnRuntime?,pendingSshConnect: freezed == pendingSshConnect ? _self.pendingSshConnect : pendingSshConnect // ignore: cast_nullable_to_non_nullable
as PendingSshConnect?,pendingSshCommand: freezed == pendingSshCommand ? _self.pendingSshCommand : pendingSshCommand // ignore: cast_nullable_to_non_nullable
as PendingSshCommand?,pendingGitCommand: freezed == pendingGitCommand ? _self.pendingGitCommand : pendingGitCommand // ignore: cast_nullable_to_non_nullable
as PendingGitCommand?,pendingLocalCommand: freezed == pendingLocalCommand ? _self.pendingLocalCommand : pendingLocalCommand // ignore: cast_nullable_to_non_nullable
as PendingLocalCommand?,pendingComputerUseAction: freezed == pendingComputerUseAction ? _self.pendingComputerUseAction : pendingComputerUseAction // ignore: cast_nullable_to_non_nullable
as PendingComputerUseAction?,pendingBrowserAction: freezed == pendingBrowserAction ? _self.pendingBrowserAction : pendingBrowserAction // ignore: cast_nullable_to_non_nullable
as PendingBrowserAction?,pendingFileOperation: freezed == pendingFileOperation ? _self.pendingFileOperation : pendingFileOperation // ignore: cast_nullable_to_non_nullable
as PendingFileOperation?,pendingBleConnect: freezed == pendingBleConnect ? _self.pendingBleConnect : pendingBleConnect // ignore: cast_nullable_to_non_nullable
as PendingBleConnect?,pendingSerialOpen: freezed == pendingSerialOpen ? _self.pendingSerialOpen : pendingSerialOpen // ignore: cast_nullable_to_non_nullable
as PendingSerialOpen?,pendingParticipantToolApproval: freezed == pendingParticipantToolApproval ? _self.pendingParticipantToolApproval : pendingParticipantToolApproval // ignore: cast_nullable_to_non_nullable
as PendingParticipantToolApproval?,pendingAskUserQuestion: freezed == pendingAskUserQuestion ? _self.pendingAskUserQuestion : pendingAskUserQuestion // ignore: cast_nullable_to_non_nullable
as PendingAskUserQuestion?,pendingWorkflowDecision: freezed == pendingWorkflowDecision ? _self.pendingWorkflowDecision : pendingWorkflowDecision // ignore: cast_nullable_to_non_nullable
as PendingWorkflowDecision?,isGeneratingWorkflowProposal: null == isGeneratingWorkflowProposal ? _self.isGeneratingWorkflowProposal : isGeneratingWorkflowProposal // ignore: cast_nullable_to_non_nullable
as bool,workflowProposalDraft: freezed == workflowProposalDraft ? _self.workflowProposalDraft : workflowProposalDraft // ignore: cast_nullable_to_non_nullable
as WorkflowProposalDraft?,workflowProposalError: freezed == workflowProposalError ? _self.workflowProposalError : workflowProposalError // ignore: cast_nullable_to_non_nullable
as String?,isGeneratingTaskProposal: null == isGeneratingTaskProposal ? _self.isGeneratingTaskProposal : isGeneratingTaskProposal // ignore: cast_nullable_to_non_nullable
as bool,taskProposalDraft: freezed == taskProposalDraft ? _self.taskProposalDraft : taskProposalDraft // ignore: cast_nullable_to_non_nullable
as WorkflowTaskProposalDraft?,taskProposalError: freezed == taskProposalError ? _self.taskProposalError : taskProposalError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ParticipantTurnRuntimeCopyWith<$Res>? get participantTurnRuntime {
    if (_self.participantTurnRuntime == null) {
    return null;
  }

  return $ParticipantTurnRuntimeCopyWith<$Res>(_self.participantTurnRuntime!, (value) {
    return _then(_self.copyWith(participantTurnRuntime: value));
  });
}/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowProposalDraftCopyWith<$Res>? get workflowProposalDraft {
    if (_self.workflowProposalDraft == null) {
    return null;
  }

  return $WorkflowProposalDraftCopyWith<$Res>(_self.workflowProposalDraft!, (value) {
    return _then(_self.copyWith(workflowProposalDraft: value));
  });
}/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowTaskProposalDraftCopyWith<$Res>? get taskProposalDraft {
    if (_self.taskProposalDraft == null) {
    return null;
  }

  return $WorkflowTaskProposalDraftCopyWith<$Res>(_self.taskProposalDraft!, (value) {
    return _then(_self.copyWith(taskProposalDraft: value));
  });
}
}

// dart format on
