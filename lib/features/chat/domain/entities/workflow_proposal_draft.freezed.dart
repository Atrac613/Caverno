// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workflow_proposal_draft.dart';

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

// dart format on
