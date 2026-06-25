// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationCheckpoint {

 String get messageId; int get messageCount; String get title; DateTime get createdAt;@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode get executionMode;@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage get workflowStage;@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? get workflowSpec; String get workflowSourceHash; DateTime? get workflowDerivedAt;@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> get executionProgress;@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> get openQuestionProgress;@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) ConversationGoal? get goal;@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? get planArtifact;@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) ConversationCompactionArtifact? get compactionArtifact;
/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCheckpointCopyWith<ConversationCheckpoint> get copyWith => _$ConversationCheckpointCopyWithImpl<ConversationCheckpoint>(this as ConversationCheckpoint, _$identity);

  /// Serializes this ConversationCheckpoint to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationCheckpoint&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.messageCount, messageCount) || other.messageCount == messageCount)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.executionMode, executionMode) || other.executionMode == executionMode)&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec)&&(identical(other.workflowSourceHash, workflowSourceHash) || other.workflowSourceHash == workflowSourceHash)&&(identical(other.workflowDerivedAt, workflowDerivedAt) || other.workflowDerivedAt == workflowDerivedAt)&&const DeepCollectionEquality().equals(other.executionProgress, executionProgress)&&const DeepCollectionEquality().equals(other.openQuestionProgress, openQuestionProgress)&&(identical(other.goal, goal) || other.goal == goal)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.compactionArtifact, compactionArtifact) || other.compactionArtifact == compactionArtifact));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,messageId,messageCount,title,createdAt,executionMode,workflowStage,workflowSpec,workflowSourceHash,workflowDerivedAt,const DeepCollectionEquality().hash(executionProgress),const DeepCollectionEquality().hash(openQuestionProgress),goal,planArtifact,compactionArtifact);

@override
String toString() {
  return 'ConversationCheckpoint(messageId: $messageId, messageCount: $messageCount, title: $title, createdAt: $createdAt, executionMode: $executionMode, workflowStage: $workflowStage, workflowSpec: $workflowSpec, workflowSourceHash: $workflowSourceHash, workflowDerivedAt: $workflowDerivedAt, executionProgress: $executionProgress, openQuestionProgress: $openQuestionProgress, goal: $goal, planArtifact: $planArtifact, compactionArtifact: $compactionArtifact)';
}


}

/// @nodoc
abstract mixin class $ConversationCheckpointCopyWith<$Res>  {
  factory $ConversationCheckpointCopyWith(ConversationCheckpoint value, $Res Function(ConversationCheckpoint) _then) = _$ConversationCheckpointCopyWithImpl;
@useResult
$Res call({
 String messageId, int messageCount, String title, DateTime createdAt,@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode executionMode,@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage workflowStage,@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? workflowSpec, String workflowSourceHash, DateTime? workflowDerivedAt,@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> executionProgress,@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> openQuestionProgress,@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) ConversationGoal? goal,@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? planArtifact,@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) ConversationCompactionArtifact? compactionArtifact
});


$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec;$ConversationGoalCopyWith<$Res>? get goal;$ConversationPlanArtifactCopyWith<$Res>? get planArtifact;$ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact;

}
/// @nodoc
class _$ConversationCheckpointCopyWithImpl<$Res>
    implements $ConversationCheckpointCopyWith<$Res> {
  _$ConversationCheckpointCopyWithImpl(this._self, this._then);

  final ConversationCheckpoint _self;
  final $Res Function(ConversationCheckpoint) _then;

/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? messageId = null,Object? messageCount = null,Object? title = null,Object? createdAt = null,Object? executionMode = null,Object? workflowStage = null,Object? workflowSpec = freezed,Object? workflowSourceHash = null,Object? workflowDerivedAt = freezed,Object? executionProgress = null,Object? openQuestionProgress = null,Object? goal = freezed,Object? planArtifact = freezed,Object? compactionArtifact = freezed,}) {
  return _then(_self.copyWith(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,messageCount: null == messageCount ? _self.messageCount : messageCount // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,executionMode: null == executionMode ? _self.executionMode : executionMode // ignore: cast_nullable_to_non_nullable
as ConversationExecutionMode,workflowStage: null == workflowStage ? _self.workflowStage : workflowStage // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowStage,workflowSpec: freezed == workflowSpec ? _self.workflowSpec : workflowSpec // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowSpec?,workflowSourceHash: null == workflowSourceHash ? _self.workflowSourceHash : workflowSourceHash // ignore: cast_nullable_to_non_nullable
as String,workflowDerivedAt: freezed == workflowDerivedAt ? _self.workflowDerivedAt : workflowDerivedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,executionProgress: null == executionProgress ? _self.executionProgress : executionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationExecutionTaskProgress>,openQuestionProgress: null == openQuestionProgress ? _self.openQuestionProgress : openQuestionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationOpenQuestionProgress>,goal: freezed == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as ConversationGoal?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as ConversationPlanArtifact?,compactionArtifact: freezed == compactionArtifact ? _self.compactionArtifact : compactionArtifact // ignore: cast_nullable_to_non_nullable
as ConversationCompactionArtifact?,
  ));
}
/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec {
    if (_self.workflowSpec == null) {
    return null;
  }

  return $ConversationWorkflowSpecCopyWith<$Res>(_self.workflowSpec!, (value) {
    return _then(_self.copyWith(workflowSpec: value));
  });
}/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationGoalCopyWith<$Res>? get goal {
    if (_self.goal == null) {
    return null;
  }

  return $ConversationGoalCopyWith<$Res>(_self.goal!, (value) {
    return _then(_self.copyWith(goal: value));
  });
}/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationPlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $ConversationPlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact {
    if (_self.compactionArtifact == null) {
    return null;
  }

  return $ConversationCompactionArtifactCopyWith<$Res>(_self.compactionArtifact!, (value) {
    return _then(_self.copyWith(compactionArtifact: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConversationCheckpoint].
extension ConversationCheckpointPatterns on ConversationCheckpoint {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationCheckpoint value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationCheckpoint() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationCheckpoint value)  $default,){
final _that = this;
switch (_that) {
case _ConversationCheckpoint():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationCheckpoint value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationCheckpoint() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String messageId,  int messageCount,  String title,  DateTime createdAt, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson)  List<ConversationExecutionTaskProgress> executionProgress, @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson)  List<ConversationOpenQuestionProgress> openQuestionProgress, @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson)  ConversationGoal? goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson)  ConversationCompactionArtifact? compactionArtifact)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationCheckpoint() when $default != null:
return $default(_that.messageId,_that.messageCount,_that.title,_that.createdAt,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.executionProgress,_that.openQuestionProgress,_that.goal,_that.planArtifact,_that.compactionArtifact);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String messageId,  int messageCount,  String title,  DateTime createdAt, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson)  List<ConversationExecutionTaskProgress> executionProgress, @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson)  List<ConversationOpenQuestionProgress> openQuestionProgress, @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson)  ConversationGoal? goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson)  ConversationCompactionArtifact? compactionArtifact)  $default,) {final _that = this;
switch (_that) {
case _ConversationCheckpoint():
return $default(_that.messageId,_that.messageCount,_that.title,_that.createdAt,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.executionProgress,_that.openQuestionProgress,_that.goal,_that.planArtifact,_that.compactionArtifact);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String messageId,  int messageCount,  String title,  DateTime createdAt, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson)  List<ConversationExecutionTaskProgress> executionProgress, @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson)  List<ConversationOpenQuestionProgress> openQuestionProgress, @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson)  ConversationGoal? goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson)  ConversationCompactionArtifact? compactionArtifact)?  $default,) {final _that = this;
switch (_that) {
case _ConversationCheckpoint() when $default != null:
return $default(_that.messageId,_that.messageCount,_that.title,_that.createdAt,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.executionProgress,_that.openQuestionProgress,_that.goal,_that.planArtifact,_that.compactionArtifact);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationCheckpoint extends ConversationCheckpoint {
  const _ConversationCheckpoint({required this.messageId, required this.messageCount, required this.title, required this.createdAt, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal) this.executionMode = ConversationExecutionMode.normal, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) this.workflowStage = ConversationWorkflowStage.idle, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) this.workflowSpec, this.workflowSourceHash = '', this.workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) final  List<ConversationExecutionTaskProgress> executionProgress = const <ConversationExecutionTaskProgress>[], @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) final  List<ConversationOpenQuestionProgress> openQuestionProgress = const <ConversationOpenQuestionProgress>[], @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) this.goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) this.planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) this.compactionArtifact}): _executionProgress = executionProgress,_openQuestionProgress = openQuestionProgress,super._();
  factory _ConversationCheckpoint.fromJson(Map<String, dynamic> json) => _$ConversationCheckpointFromJson(json);

@override final  String messageId;
@override final  int messageCount;
@override final  String title;
@override final  DateTime createdAt;
@override@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) final  ConversationExecutionMode executionMode;
@override@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) final  ConversationWorkflowStage workflowStage;
@override@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) final  ConversationWorkflowSpec? workflowSpec;
@override@JsonKey() final  String workflowSourceHash;
@override final  DateTime? workflowDerivedAt;
 final  List<ConversationExecutionTaskProgress> _executionProgress;
@override@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> get executionProgress {
  if (_executionProgress is EqualUnmodifiableListView) return _executionProgress;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_executionProgress);
}

 final  List<ConversationOpenQuestionProgress> _openQuestionProgress;
@override@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> get openQuestionProgress {
  if (_openQuestionProgress is EqualUnmodifiableListView) return _openQuestionProgress;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_openQuestionProgress);
}

@override@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) final  ConversationGoal? goal;
@override@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) final  ConversationPlanArtifact? planArtifact;
@override@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) final  ConversationCompactionArtifact? compactionArtifact;

/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationCheckpointCopyWith<_ConversationCheckpoint> get copyWith => __$ConversationCheckpointCopyWithImpl<_ConversationCheckpoint>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationCheckpointToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationCheckpoint&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.messageCount, messageCount) || other.messageCount == messageCount)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.executionMode, executionMode) || other.executionMode == executionMode)&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec)&&(identical(other.workflowSourceHash, workflowSourceHash) || other.workflowSourceHash == workflowSourceHash)&&(identical(other.workflowDerivedAt, workflowDerivedAt) || other.workflowDerivedAt == workflowDerivedAt)&&const DeepCollectionEquality().equals(other._executionProgress, _executionProgress)&&const DeepCollectionEquality().equals(other._openQuestionProgress, _openQuestionProgress)&&(identical(other.goal, goal) || other.goal == goal)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.compactionArtifact, compactionArtifact) || other.compactionArtifact == compactionArtifact));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,messageId,messageCount,title,createdAt,executionMode,workflowStage,workflowSpec,workflowSourceHash,workflowDerivedAt,const DeepCollectionEquality().hash(_executionProgress),const DeepCollectionEquality().hash(_openQuestionProgress),goal,planArtifact,compactionArtifact);

@override
String toString() {
  return 'ConversationCheckpoint(messageId: $messageId, messageCount: $messageCount, title: $title, createdAt: $createdAt, executionMode: $executionMode, workflowStage: $workflowStage, workflowSpec: $workflowSpec, workflowSourceHash: $workflowSourceHash, workflowDerivedAt: $workflowDerivedAt, executionProgress: $executionProgress, openQuestionProgress: $openQuestionProgress, goal: $goal, planArtifact: $planArtifact, compactionArtifact: $compactionArtifact)';
}


}

/// @nodoc
abstract mixin class _$ConversationCheckpointCopyWith<$Res> implements $ConversationCheckpointCopyWith<$Res> {
  factory _$ConversationCheckpointCopyWith(_ConversationCheckpoint value, $Res Function(_ConversationCheckpoint) _then) = __$ConversationCheckpointCopyWithImpl;
@override @useResult
$Res call({
 String messageId, int messageCount, String title, DateTime createdAt,@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode executionMode,@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage workflowStage,@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? workflowSpec, String workflowSourceHash, DateTime? workflowDerivedAt,@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> executionProgress,@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> openQuestionProgress,@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) ConversationGoal? goal,@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? planArtifact,@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) ConversationCompactionArtifact? compactionArtifact
});


@override $ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec;@override $ConversationGoalCopyWith<$Res>? get goal;@override $ConversationPlanArtifactCopyWith<$Res>? get planArtifact;@override $ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact;

}
/// @nodoc
class __$ConversationCheckpointCopyWithImpl<$Res>
    implements _$ConversationCheckpointCopyWith<$Res> {
  __$ConversationCheckpointCopyWithImpl(this._self, this._then);

  final _ConversationCheckpoint _self;
  final $Res Function(_ConversationCheckpoint) _then;

/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? messageId = null,Object? messageCount = null,Object? title = null,Object? createdAt = null,Object? executionMode = null,Object? workflowStage = null,Object? workflowSpec = freezed,Object? workflowSourceHash = null,Object? workflowDerivedAt = freezed,Object? executionProgress = null,Object? openQuestionProgress = null,Object? goal = freezed,Object? planArtifact = freezed,Object? compactionArtifact = freezed,}) {
  return _then(_ConversationCheckpoint(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,messageCount: null == messageCount ? _self.messageCount : messageCount // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,executionMode: null == executionMode ? _self.executionMode : executionMode // ignore: cast_nullable_to_non_nullable
as ConversationExecutionMode,workflowStage: null == workflowStage ? _self.workflowStage : workflowStage // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowStage,workflowSpec: freezed == workflowSpec ? _self.workflowSpec : workflowSpec // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowSpec?,workflowSourceHash: null == workflowSourceHash ? _self.workflowSourceHash : workflowSourceHash // ignore: cast_nullable_to_non_nullable
as String,workflowDerivedAt: freezed == workflowDerivedAt ? _self.workflowDerivedAt : workflowDerivedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,executionProgress: null == executionProgress ? _self._executionProgress : executionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationExecutionTaskProgress>,openQuestionProgress: null == openQuestionProgress ? _self._openQuestionProgress : openQuestionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationOpenQuestionProgress>,goal: freezed == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as ConversationGoal?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as ConversationPlanArtifact?,compactionArtifact: freezed == compactionArtifact ? _self.compactionArtifact : compactionArtifact // ignore: cast_nullable_to_non_nullable
as ConversationCompactionArtifact?,
  ));
}

/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec {
    if (_self.workflowSpec == null) {
    return null;
  }

  return $ConversationWorkflowSpecCopyWith<$Res>(_self.workflowSpec!, (value) {
    return _then(_self.copyWith(workflowSpec: value));
  });
}/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationGoalCopyWith<$Res>? get goal {
    if (_self.goal == null) {
    return null;
  }

  return $ConversationGoalCopyWith<$Res>(_self.goal!, (value) {
    return _then(_self.copyWith(goal: value));
  });
}/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationPlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $ConversationPlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}/// Create a copy of ConversationCheckpoint
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact {
    if (_self.compactionArtifact == null) {
    return null;
  }

  return $ConversationCompactionArtifactCopyWith<$Res>(_self.compactionArtifact!, (value) {
    return _then(_self.copyWith(compactionArtifact: value));
  });
}
}


/// @nodoc
mixin _$Conversation {

 String get id; String get title;@JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson) List<Message> get messages; DateTime get createdAt; DateTime get updatedAt;@JsonKey(unknownEnumValue: WorkspaceMode.chat) WorkspaceMode get workspaceMode; String get projectId;@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode get executionMode;@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage get workflowStage;@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? get workflowSpec; String get workflowSourceHash; DateTime? get workflowDerivedAt;@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> get executionProgress;@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> get openQuestionProgress;@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) ConversationGoal? get goal;@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? get planArtifact;@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) ConversationCompactionArtifact? get compactionArtifact;@JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson) List<ConversationCheckpoint> get checkpoints;@JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson) List<TurnDiff> get turnDiffs;@JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson) List<ConversationParticipant> get participants;@JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson) ParticipantTurnConfig get participantTurnConfig;
/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCopyWith<Conversation> get copyWith => _$ConversationCopyWithImpl<Conversation>(this as Conversation, _$identity);

  /// Serializes this Conversation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.messages, messages)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.executionMode, executionMode) || other.executionMode == executionMode)&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec)&&(identical(other.workflowSourceHash, workflowSourceHash) || other.workflowSourceHash == workflowSourceHash)&&(identical(other.workflowDerivedAt, workflowDerivedAt) || other.workflowDerivedAt == workflowDerivedAt)&&const DeepCollectionEquality().equals(other.executionProgress, executionProgress)&&const DeepCollectionEquality().equals(other.openQuestionProgress, openQuestionProgress)&&(identical(other.goal, goal) || other.goal == goal)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.compactionArtifact, compactionArtifact) || other.compactionArtifact == compactionArtifact)&&const DeepCollectionEquality().equals(other.checkpoints, checkpoints)&&const DeepCollectionEquality().equals(other.turnDiffs, turnDiffs)&&const DeepCollectionEquality().equals(other.participants, participants)&&(identical(other.participantTurnConfig, participantTurnConfig) || other.participantTurnConfig == participantTurnConfig));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,const DeepCollectionEquality().hash(messages),createdAt,updatedAt,workspaceMode,projectId,executionMode,workflowStage,workflowSpec,workflowSourceHash,workflowDerivedAt,const DeepCollectionEquality().hash(executionProgress),const DeepCollectionEquality().hash(openQuestionProgress),goal,planArtifact,compactionArtifact,const DeepCollectionEquality().hash(checkpoints),const DeepCollectionEquality().hash(turnDiffs),const DeepCollectionEquality().hash(participants),participantTurnConfig]);

@override
String toString() {
  return 'Conversation(id: $id, title: $title, messages: $messages, createdAt: $createdAt, updatedAt: $updatedAt, workspaceMode: $workspaceMode, projectId: $projectId, executionMode: $executionMode, workflowStage: $workflowStage, workflowSpec: $workflowSpec, workflowSourceHash: $workflowSourceHash, workflowDerivedAt: $workflowDerivedAt, executionProgress: $executionProgress, openQuestionProgress: $openQuestionProgress, goal: $goal, planArtifact: $planArtifact, compactionArtifact: $compactionArtifact, checkpoints: $checkpoints, turnDiffs: $turnDiffs, participants: $participants, participantTurnConfig: $participantTurnConfig)';
}


}

/// @nodoc
abstract mixin class $ConversationCopyWith<$Res>  {
  factory $ConversationCopyWith(Conversation value, $Res Function(Conversation) _then) = _$ConversationCopyWithImpl;
@useResult
$Res call({
 String id, String title,@JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson) List<Message> messages, DateTime createdAt, DateTime updatedAt,@JsonKey(unknownEnumValue: WorkspaceMode.chat) WorkspaceMode workspaceMode, String projectId,@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode executionMode,@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage workflowStage,@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? workflowSpec, String workflowSourceHash, DateTime? workflowDerivedAt,@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> executionProgress,@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> openQuestionProgress,@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) ConversationGoal? goal,@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? planArtifact,@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) ConversationCompactionArtifact? compactionArtifact,@JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson) List<ConversationCheckpoint> checkpoints,@JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson) List<TurnDiff> turnDiffs,@JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson) List<ConversationParticipant> participants,@JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson) ParticipantTurnConfig participantTurnConfig
});


$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec;$ConversationGoalCopyWith<$Res>? get goal;$ConversationPlanArtifactCopyWith<$Res>? get planArtifact;$ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact;$ParticipantTurnConfigCopyWith<$Res> get participantTurnConfig;

}
/// @nodoc
class _$ConversationCopyWithImpl<$Res>
    implements $ConversationCopyWith<$Res> {
  _$ConversationCopyWithImpl(this._self, this._then);

  final Conversation _self;
  final $Res Function(Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? messages = null,Object? createdAt = null,Object? updatedAt = null,Object? workspaceMode = null,Object? projectId = null,Object? executionMode = null,Object? workflowStage = null,Object? workflowSpec = freezed,Object? workflowSourceHash = null,Object? workflowDerivedAt = freezed,Object? executionProgress = null,Object? openQuestionProgress = null,Object? goal = freezed,Object? planArtifact = freezed,Object? compactionArtifact = freezed,Object? checkpoints = null,Object? turnDiffs = null,Object? participants = null,Object? participantTurnConfig = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as WorkspaceMode,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,executionMode: null == executionMode ? _self.executionMode : executionMode // ignore: cast_nullable_to_non_nullable
as ConversationExecutionMode,workflowStage: null == workflowStage ? _self.workflowStage : workflowStage // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowStage,workflowSpec: freezed == workflowSpec ? _self.workflowSpec : workflowSpec // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowSpec?,workflowSourceHash: null == workflowSourceHash ? _self.workflowSourceHash : workflowSourceHash // ignore: cast_nullable_to_non_nullable
as String,workflowDerivedAt: freezed == workflowDerivedAt ? _self.workflowDerivedAt : workflowDerivedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,executionProgress: null == executionProgress ? _self.executionProgress : executionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationExecutionTaskProgress>,openQuestionProgress: null == openQuestionProgress ? _self.openQuestionProgress : openQuestionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationOpenQuestionProgress>,goal: freezed == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as ConversationGoal?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as ConversationPlanArtifact?,compactionArtifact: freezed == compactionArtifact ? _self.compactionArtifact : compactionArtifact // ignore: cast_nullable_to_non_nullable
as ConversationCompactionArtifact?,checkpoints: null == checkpoints ? _self.checkpoints : checkpoints // ignore: cast_nullable_to_non_nullable
as List<ConversationCheckpoint>,turnDiffs: null == turnDiffs ? _self.turnDiffs : turnDiffs // ignore: cast_nullable_to_non_nullable
as List<TurnDiff>,participants: null == participants ? _self.participants : participants // ignore: cast_nullable_to_non_nullable
as List<ConversationParticipant>,participantTurnConfig: null == participantTurnConfig ? _self.participantTurnConfig : participantTurnConfig // ignore: cast_nullable_to_non_nullable
as ParticipantTurnConfig,
  ));
}
/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec {
    if (_self.workflowSpec == null) {
    return null;
  }

  return $ConversationWorkflowSpecCopyWith<$Res>(_self.workflowSpec!, (value) {
    return _then(_self.copyWith(workflowSpec: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationGoalCopyWith<$Res>? get goal {
    if (_self.goal == null) {
    return null;
  }

  return $ConversationGoalCopyWith<$Res>(_self.goal!, (value) {
    return _then(_self.copyWith(goal: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationPlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $ConversationPlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact {
    if (_self.compactionArtifact == null) {
    return null;
  }

  return $ConversationCompactionArtifactCopyWith<$Res>(_self.compactionArtifact!, (value) {
    return _then(_self.copyWith(compactionArtifact: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ParticipantTurnConfigCopyWith<$Res> get participantTurnConfig {
  
  return $ParticipantTurnConfigCopyWith<$Res>(_self.participantTurnConfig, (value) {
    return _then(_self.copyWith(participantTurnConfig: value));
  });
}
}


/// Adds pattern-matching-related methods to [Conversation].
extension ConversationPatterns on Conversation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Conversation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Conversation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Conversation value)  $default,){
final _that = this;
switch (_that) {
case _Conversation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Conversation value)?  $default,){
final _that = this;
switch (_that) {
case _Conversation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title, @JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson)  List<Message> messages,  DateTime createdAt,  DateTime updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat)  WorkspaceMode workspaceMode,  String projectId, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson)  List<ConversationExecutionTaskProgress> executionProgress, @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson)  List<ConversationOpenQuestionProgress> openQuestionProgress, @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson)  ConversationGoal? goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson)  ConversationCompactionArtifact? compactionArtifact, @JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson)  List<ConversationCheckpoint> checkpoints, @JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson)  List<TurnDiff> turnDiffs, @JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson)  List<ConversationParticipant> participants, @JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson)  ParticipantTurnConfig participantTurnConfig)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.title,_that.messages,_that.createdAt,_that.updatedAt,_that.workspaceMode,_that.projectId,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.executionProgress,_that.openQuestionProgress,_that.goal,_that.planArtifact,_that.compactionArtifact,_that.checkpoints,_that.turnDiffs,_that.participants,_that.participantTurnConfig);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title, @JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson)  List<Message> messages,  DateTime createdAt,  DateTime updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat)  WorkspaceMode workspaceMode,  String projectId, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson)  List<ConversationExecutionTaskProgress> executionProgress, @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson)  List<ConversationOpenQuestionProgress> openQuestionProgress, @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson)  ConversationGoal? goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson)  ConversationCompactionArtifact? compactionArtifact, @JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson)  List<ConversationCheckpoint> checkpoints, @JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson)  List<TurnDiff> turnDiffs, @JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson)  List<ConversationParticipant> participants, @JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson)  ParticipantTurnConfig participantTurnConfig)  $default,) {final _that = this;
switch (_that) {
case _Conversation():
return $default(_that.id,_that.title,_that.messages,_that.createdAt,_that.updatedAt,_that.workspaceMode,_that.projectId,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.executionProgress,_that.openQuestionProgress,_that.goal,_that.planArtifact,_that.compactionArtifact,_that.checkpoints,_that.turnDiffs,_that.participants,_that.participantTurnConfig);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title, @JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson)  List<Message> messages,  DateTime createdAt,  DateTime updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat)  WorkspaceMode workspaceMode,  String projectId, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson)  List<ConversationExecutionTaskProgress> executionProgress, @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson)  List<ConversationOpenQuestionProgress> openQuestionProgress, @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson)  ConversationGoal? goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson)  ConversationCompactionArtifact? compactionArtifact, @JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson)  List<ConversationCheckpoint> checkpoints, @JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson)  List<TurnDiff> turnDiffs, @JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson)  List<ConversationParticipant> participants, @JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson)  ParticipantTurnConfig participantTurnConfig)?  $default,) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.title,_that.messages,_that.createdAt,_that.updatedAt,_that.workspaceMode,_that.projectId,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.executionProgress,_that.openQuestionProgress,_that.goal,_that.planArtifact,_that.compactionArtifact,_that.checkpoints,_that.turnDiffs,_that.participants,_that.participantTurnConfig);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Conversation extends Conversation {
  const _Conversation({required this.id, required this.title, @JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson) required final  List<Message> messages, required this.createdAt, required this.updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat) this.workspaceMode = WorkspaceMode.chat, this.projectId = '', @JsonKey(unknownEnumValue: ConversationExecutionMode.normal) this.executionMode = ConversationExecutionMode.normal, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) this.workflowStage = ConversationWorkflowStage.idle, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) this.workflowSpec, this.workflowSourceHash = '', this.workflowDerivedAt, @JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) final  List<ConversationExecutionTaskProgress> executionProgress = const <ConversationExecutionTaskProgress>[], @JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) final  List<ConversationOpenQuestionProgress> openQuestionProgress = const <ConversationOpenQuestionProgress>[], @JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) this.goal, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) this.planArtifact, @JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) this.compactionArtifact, @JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson) final  List<ConversationCheckpoint> checkpoints = const <ConversationCheckpoint>[], @JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson) final  List<TurnDiff> turnDiffs = const <TurnDiff>[], @JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson) final  List<ConversationParticipant> participants = const <ConversationParticipant>[], @JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson) this.participantTurnConfig = const ParticipantTurnConfig()}): _messages = messages,_executionProgress = executionProgress,_openQuestionProgress = openQuestionProgress,_checkpoints = checkpoints,_turnDiffs = turnDiffs,_participants = participants,super._();
  factory _Conversation.fromJson(Map<String, dynamic> json) => _$ConversationFromJson(json);

@override final  String id;
@override final  String title;
 final  List<Message> _messages;
@override@JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson) List<Message> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey(unknownEnumValue: WorkspaceMode.chat) final  WorkspaceMode workspaceMode;
@override@JsonKey() final  String projectId;
@override@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) final  ConversationExecutionMode executionMode;
@override@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) final  ConversationWorkflowStage workflowStage;
@override@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) final  ConversationWorkflowSpec? workflowSpec;
@override@JsonKey() final  String workflowSourceHash;
@override final  DateTime? workflowDerivedAt;
 final  List<ConversationExecutionTaskProgress> _executionProgress;
@override@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> get executionProgress {
  if (_executionProgress is EqualUnmodifiableListView) return _executionProgress;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_executionProgress);
}

 final  List<ConversationOpenQuestionProgress> _openQuestionProgress;
@override@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> get openQuestionProgress {
  if (_openQuestionProgress is EqualUnmodifiableListView) return _openQuestionProgress;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_openQuestionProgress);
}

@override@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) final  ConversationGoal? goal;
@override@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) final  ConversationPlanArtifact? planArtifact;
@override@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) final  ConversationCompactionArtifact? compactionArtifact;
 final  List<ConversationCheckpoint> _checkpoints;
@override@JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson) List<ConversationCheckpoint> get checkpoints {
  if (_checkpoints is EqualUnmodifiableListView) return _checkpoints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_checkpoints);
}

 final  List<TurnDiff> _turnDiffs;
@override@JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson) List<TurnDiff> get turnDiffs {
  if (_turnDiffs is EqualUnmodifiableListView) return _turnDiffs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_turnDiffs);
}

 final  List<ConversationParticipant> _participants;
@override@JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson) List<ConversationParticipant> get participants {
  if (_participants is EqualUnmodifiableListView) return _participants;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_participants);
}

@override@JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson) final  ParticipantTurnConfig participantTurnConfig;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationCopyWith<_Conversation> get copyWith => __$ConversationCopyWithImpl<_Conversation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.executionMode, executionMode) || other.executionMode == executionMode)&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec)&&(identical(other.workflowSourceHash, workflowSourceHash) || other.workflowSourceHash == workflowSourceHash)&&(identical(other.workflowDerivedAt, workflowDerivedAt) || other.workflowDerivedAt == workflowDerivedAt)&&const DeepCollectionEquality().equals(other._executionProgress, _executionProgress)&&const DeepCollectionEquality().equals(other._openQuestionProgress, _openQuestionProgress)&&(identical(other.goal, goal) || other.goal == goal)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.compactionArtifact, compactionArtifact) || other.compactionArtifact == compactionArtifact)&&const DeepCollectionEquality().equals(other._checkpoints, _checkpoints)&&const DeepCollectionEquality().equals(other._turnDiffs, _turnDiffs)&&const DeepCollectionEquality().equals(other._participants, _participants)&&(identical(other.participantTurnConfig, participantTurnConfig) || other.participantTurnConfig == participantTurnConfig));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,const DeepCollectionEquality().hash(_messages),createdAt,updatedAt,workspaceMode,projectId,executionMode,workflowStage,workflowSpec,workflowSourceHash,workflowDerivedAt,const DeepCollectionEquality().hash(_executionProgress),const DeepCollectionEquality().hash(_openQuestionProgress),goal,planArtifact,compactionArtifact,const DeepCollectionEquality().hash(_checkpoints),const DeepCollectionEquality().hash(_turnDiffs),const DeepCollectionEquality().hash(_participants),participantTurnConfig]);

@override
String toString() {
  return 'Conversation(id: $id, title: $title, messages: $messages, createdAt: $createdAt, updatedAt: $updatedAt, workspaceMode: $workspaceMode, projectId: $projectId, executionMode: $executionMode, workflowStage: $workflowStage, workflowSpec: $workflowSpec, workflowSourceHash: $workflowSourceHash, workflowDerivedAt: $workflowDerivedAt, executionProgress: $executionProgress, openQuestionProgress: $openQuestionProgress, goal: $goal, planArtifact: $planArtifact, compactionArtifact: $compactionArtifact, checkpoints: $checkpoints, turnDiffs: $turnDiffs, participants: $participants, participantTurnConfig: $participantTurnConfig)';
}


}

/// @nodoc
abstract mixin class _$ConversationCopyWith<$Res> implements $ConversationCopyWith<$Res> {
  factory _$ConversationCopyWith(_Conversation value, $Res Function(_Conversation) _then) = __$ConversationCopyWithImpl;
@override @useResult
$Res call({
 String id, String title,@JsonKey(fromJson: _messagesFromJson, toJson: _messagesToJson) List<Message> messages, DateTime createdAt, DateTime updatedAt,@JsonKey(unknownEnumValue: WorkspaceMode.chat) WorkspaceMode workspaceMode, String projectId,@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode executionMode,@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage workflowStage,@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? workflowSpec, String workflowSourceHash, DateTime? workflowDerivedAt,@JsonKey(fromJson: _executionProgressFromJson, toJson: _executionProgressToJson) List<ConversationExecutionTaskProgress> executionProgress,@JsonKey(fromJson: _openQuestionProgressFromJson, toJson: _openQuestionProgressToJson) List<ConversationOpenQuestionProgress> openQuestionProgress,@JsonKey(fromJson: _goalFromJson, toJson: _goalToJson) ConversationGoal? goal,@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? planArtifact,@JsonKey(fromJson: _compactionArtifactFromJson, toJson: _compactionArtifactToJson) ConversationCompactionArtifact? compactionArtifact,@JsonKey(fromJson: _checkpointsFromJson, toJson: _checkpointsToJson) List<ConversationCheckpoint> checkpoints,@JsonKey(fromJson: _turnDiffsFromJson, toJson: _turnDiffsToJson) List<TurnDiff> turnDiffs,@JsonKey(fromJson: _participantsFromJson, toJson: _participantsToJson) List<ConversationParticipant> participants,@JsonKey(fromJson: _participantTurnConfigFromJson, toJson: _participantTurnConfigToJson) ParticipantTurnConfig participantTurnConfig
});


@override $ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec;@override $ConversationGoalCopyWith<$Res>? get goal;@override $ConversationPlanArtifactCopyWith<$Res>? get planArtifact;@override $ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact;@override $ParticipantTurnConfigCopyWith<$Res> get participantTurnConfig;

}
/// @nodoc
class __$ConversationCopyWithImpl<$Res>
    implements _$ConversationCopyWith<$Res> {
  __$ConversationCopyWithImpl(this._self, this._then);

  final _Conversation _self;
  final $Res Function(_Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? messages = null,Object? createdAt = null,Object? updatedAt = null,Object? workspaceMode = null,Object? projectId = null,Object? executionMode = null,Object? workflowStage = null,Object? workflowSpec = freezed,Object? workflowSourceHash = null,Object? workflowDerivedAt = freezed,Object? executionProgress = null,Object? openQuestionProgress = null,Object? goal = freezed,Object? planArtifact = freezed,Object? compactionArtifact = freezed,Object? checkpoints = null,Object? turnDiffs = null,Object? participants = null,Object? participantTurnConfig = null,}) {
  return _then(_Conversation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as WorkspaceMode,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,executionMode: null == executionMode ? _self.executionMode : executionMode // ignore: cast_nullable_to_non_nullable
as ConversationExecutionMode,workflowStage: null == workflowStage ? _self.workflowStage : workflowStage // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowStage,workflowSpec: freezed == workflowSpec ? _self.workflowSpec : workflowSpec // ignore: cast_nullable_to_non_nullable
as ConversationWorkflowSpec?,workflowSourceHash: null == workflowSourceHash ? _self.workflowSourceHash : workflowSourceHash // ignore: cast_nullable_to_non_nullable
as String,workflowDerivedAt: freezed == workflowDerivedAt ? _self.workflowDerivedAt : workflowDerivedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,executionProgress: null == executionProgress ? _self._executionProgress : executionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationExecutionTaskProgress>,openQuestionProgress: null == openQuestionProgress ? _self._openQuestionProgress : openQuestionProgress // ignore: cast_nullable_to_non_nullable
as List<ConversationOpenQuestionProgress>,goal: freezed == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as ConversationGoal?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as ConversationPlanArtifact?,compactionArtifact: freezed == compactionArtifact ? _self.compactionArtifact : compactionArtifact // ignore: cast_nullable_to_non_nullable
as ConversationCompactionArtifact?,checkpoints: null == checkpoints ? _self._checkpoints : checkpoints // ignore: cast_nullable_to_non_nullable
as List<ConversationCheckpoint>,turnDiffs: null == turnDiffs ? _self._turnDiffs : turnDiffs // ignore: cast_nullable_to_non_nullable
as List<TurnDiff>,participants: null == participants ? _self._participants : participants // ignore: cast_nullable_to_non_nullable
as List<ConversationParticipant>,participantTurnConfig: null == participantTurnConfig ? _self.participantTurnConfig : participantTurnConfig // ignore: cast_nullable_to_non_nullable
as ParticipantTurnConfig,
  ));
}

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec {
    if (_self.workflowSpec == null) {
    return null;
  }

  return $ConversationWorkflowSpecCopyWith<$Res>(_self.workflowSpec!, (value) {
    return _then(_self.copyWith(workflowSpec: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationGoalCopyWith<$Res>? get goal {
    if (_self.goal == null) {
    return null;
  }

  return $ConversationGoalCopyWith<$Res>(_self.goal!, (value) {
    return _then(_self.copyWith(goal: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationPlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $ConversationPlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCompactionArtifactCopyWith<$Res>? get compactionArtifact {
    if (_self.compactionArtifact == null) {
    return null;
  }

  return $ConversationCompactionArtifactCopyWith<$Res>(_self.compactionArtifact!, (value) {
    return _then(_self.copyWith(compactionArtifact: value));
  });
}/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ParticipantTurnConfigCopyWith<$Res> get participantTurnConfig {
  
  return $ParticipantTurnConfigCopyWith<$Res>(_self.participantTurnConfig, (value) {
    return _then(_self.copyWith(participantTurnConfig: value));
  });
}
}

// dart format on
