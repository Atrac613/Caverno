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
mixin _$Conversation {

 String get id; String get title; List<Message> get messages; DateTime get createdAt; DateTime get updatedAt;@JsonKey(unknownEnumValue: WorkspaceMode.chat) WorkspaceMode get workspaceMode; String get projectId;@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode get executionMode;@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage get workflowStage;@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? get workflowSpec; String get workflowSourceHash; DateTime? get workflowDerivedAt;@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? get planArtifact;
/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCopyWith<Conversation> get copyWith => _$ConversationCopyWithImpl<Conversation>(this as Conversation, _$identity);

  /// Serializes this Conversation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.messages, messages)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.executionMode, executionMode) || other.executionMode == executionMode)&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec)&&(identical(other.workflowSourceHash, workflowSourceHash) || other.workflowSourceHash == workflowSourceHash)&&(identical(other.workflowDerivedAt, workflowDerivedAt) || other.workflowDerivedAt == workflowDerivedAt)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(messages),createdAt,updatedAt,workspaceMode,projectId,executionMode,workflowStage,workflowSpec,workflowSourceHash,workflowDerivedAt,planArtifact);

@override
String toString() {
  return 'Conversation(id: $id, title: $title, messages: $messages, createdAt: $createdAt, updatedAt: $updatedAt, workspaceMode: $workspaceMode, projectId: $projectId, executionMode: $executionMode, workflowStage: $workflowStage, workflowSpec: $workflowSpec, workflowSourceHash: $workflowSourceHash, workflowDerivedAt: $workflowDerivedAt, planArtifact: $planArtifact)';
}


}

/// @nodoc
abstract mixin class $ConversationCopyWith<$Res>  {
  factory $ConversationCopyWith(Conversation value, $Res Function(Conversation) _then) = _$ConversationCopyWithImpl;
@useResult
$Res call({
 String id, String title, List<Message> messages, DateTime createdAt, DateTime updatedAt,@JsonKey(unknownEnumValue: WorkspaceMode.chat) WorkspaceMode workspaceMode, String projectId,@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode executionMode,@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage workflowStage,@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? workflowSpec, String workflowSourceHash, DateTime? workflowDerivedAt,@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? planArtifact
});


$ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec;$ConversationPlanArtifactCopyWith<$Res>? get planArtifact;

}
/// @nodoc
class _$ConversationCopyWithImpl<$Res>
    implements $ConversationCopyWith<$Res> {
  _$ConversationCopyWithImpl(this._self, this._then);

  final Conversation _self;
  final $Res Function(Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? messages = null,Object? createdAt = null,Object? updatedAt = null,Object? workspaceMode = null,Object? projectId = null,Object? executionMode = null,Object? workflowStage = null,Object? workflowSpec = freezed,Object? workflowSourceHash = null,Object? workflowDerivedAt = freezed,Object? planArtifact = freezed,}) {
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
as DateTime?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as ConversationPlanArtifact?,
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
$ConversationPlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $ConversationPlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  List<Message> messages,  DateTime createdAt,  DateTime updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat)  WorkspaceMode workspaceMode,  String projectId, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.title,_that.messages,_that.createdAt,_that.updatedAt,_that.workspaceMode,_that.projectId,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.planArtifact);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  List<Message> messages,  DateTime createdAt,  DateTime updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat)  WorkspaceMode workspaceMode,  String projectId, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact)  $default,) {final _that = this;
switch (_that) {
case _Conversation():
return $default(_that.id,_that.title,_that.messages,_that.createdAt,_that.updatedAt,_that.workspaceMode,_that.projectId,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.planArtifact);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  List<Message> messages,  DateTime createdAt,  DateTime updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat)  WorkspaceMode workspaceMode,  String projectId, @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)  ConversationExecutionMode executionMode, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)  ConversationWorkflowStage workflowStage, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)  ConversationWorkflowSpec? workflowSpec,  String workflowSourceHash,  DateTime? workflowDerivedAt, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)  ConversationPlanArtifact? planArtifact)?  $default,) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.title,_that.messages,_that.createdAt,_that.updatedAt,_that.workspaceMode,_that.projectId,_that.executionMode,_that.workflowStage,_that.workflowSpec,_that.workflowSourceHash,_that.workflowDerivedAt,_that.planArtifact);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Conversation extends Conversation {
  const _Conversation({required this.id, required this.title, required final  List<Message> messages, required this.createdAt, required this.updatedAt, @JsonKey(unknownEnumValue: WorkspaceMode.chat) this.workspaceMode = WorkspaceMode.chat, this.projectId = '', @JsonKey(unknownEnumValue: ConversationExecutionMode.normal) this.executionMode = ConversationExecutionMode.normal, @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) this.workflowStage = ConversationWorkflowStage.idle, @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) this.workflowSpec, this.workflowSourceHash = '', this.workflowDerivedAt, @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) this.planArtifact}): _messages = messages,super._();
  factory _Conversation.fromJson(Map<String, dynamic> json) => _$ConversationFromJson(json);

@override final  String id;
@override final  String title;
 final  List<Message> _messages;
@override List<Message> get messages {
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
@override@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) final  ConversationPlanArtifact? planArtifact;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.executionMode, executionMode) || other.executionMode == executionMode)&&(identical(other.workflowStage, workflowStage) || other.workflowStage == workflowStage)&&(identical(other.workflowSpec, workflowSpec) || other.workflowSpec == workflowSpec)&&(identical(other.workflowSourceHash, workflowSourceHash) || other.workflowSourceHash == workflowSourceHash)&&(identical(other.workflowDerivedAt, workflowDerivedAt) || other.workflowDerivedAt == workflowDerivedAt)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(_messages),createdAt,updatedAt,workspaceMode,projectId,executionMode,workflowStage,workflowSpec,workflowSourceHash,workflowDerivedAt,planArtifact);

@override
String toString() {
  return 'Conversation(id: $id, title: $title, messages: $messages, createdAt: $createdAt, updatedAt: $updatedAt, workspaceMode: $workspaceMode, projectId: $projectId, executionMode: $executionMode, workflowStage: $workflowStage, workflowSpec: $workflowSpec, workflowSourceHash: $workflowSourceHash, workflowDerivedAt: $workflowDerivedAt, planArtifact: $planArtifact)';
}


}

/// @nodoc
abstract mixin class _$ConversationCopyWith<$Res> implements $ConversationCopyWith<$Res> {
  factory _$ConversationCopyWith(_Conversation value, $Res Function(_Conversation) _then) = __$ConversationCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, List<Message> messages, DateTime createdAt, DateTime updatedAt,@JsonKey(unknownEnumValue: WorkspaceMode.chat) WorkspaceMode workspaceMode, String projectId,@JsonKey(unknownEnumValue: ConversationExecutionMode.normal) ConversationExecutionMode executionMode,@JsonKey(unknownEnumValue: ConversationWorkflowStage.idle) ConversationWorkflowStage workflowStage,@JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson) ConversationWorkflowSpec? workflowSpec, String workflowSourceHash, DateTime? workflowDerivedAt,@JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson) ConversationPlanArtifact? planArtifact
});


@override $ConversationWorkflowSpecCopyWith<$Res>? get workflowSpec;@override $ConversationPlanArtifactCopyWith<$Res>? get planArtifact;

}
/// @nodoc
class __$ConversationCopyWithImpl<$Res>
    implements _$ConversationCopyWith<$Res> {
  __$ConversationCopyWithImpl(this._self, this._then);

  final _Conversation _self;
  final $Res Function(_Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? messages = null,Object? createdAt = null,Object? updatedAt = null,Object? workspaceMode = null,Object? projectId = null,Object? executionMode = null,Object? workflowStage = null,Object? workflowSpec = freezed,Object? workflowSourceHash = null,Object? workflowDerivedAt = freezed,Object? planArtifact = freezed,}) {
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
as DateTime?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as ConversationPlanArtifact?,
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
$ConversationPlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $ConversationPlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}
}

// dart format on
