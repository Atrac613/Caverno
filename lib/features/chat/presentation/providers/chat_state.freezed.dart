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
mixin _$ChatState {

 List<Message> get messages; bool get isLoading; String? get error; int get promptTokens; int get completionTokens; int get totalTokens;// SSH tool UI flow — holders contain Completers so they live outside
// the freezed equality graph.
 PendingSshConnect? get pendingSshConnect; PendingSshCommand? get pendingSshCommand;// Git tool UI flow — same Completer-based pattern as SSH.
 PendingGitCommand? get pendingGitCommand;// Local shell tool UI flow.
 PendingLocalCommand? get pendingLocalCommand;// File mutation tool UI flow.
 PendingFileOperation? get pendingFileOperation;// BLE tool UI flow — same Completer-based pattern as SSH.
 PendingBleConnect? get pendingBleConnect;// Workflow planning choice UI flow.
 PendingWorkflowDecision? get pendingWorkflowDecision; bool get isGeneratingWorkflowProposal; WorkflowProposalDraft? get workflowProposalDraft; String? get workflowProposalError; bool get isGeneratingTaskProposal; WorkflowTaskProposalDraft? get taskProposalDraft; String? get taskProposalError;
/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatStateCopyWith<ChatState> get copyWith => _$ChatStateCopyWithImpl<ChatState>(this as ChatState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatState&&const DeepCollectionEquality().equals(other.messages, messages)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.pendingSshConnect, pendingSshConnect) || other.pendingSshConnect == pendingSshConnect)&&(identical(other.pendingSshCommand, pendingSshCommand) || other.pendingSshCommand == pendingSshCommand)&&(identical(other.pendingGitCommand, pendingGitCommand) || other.pendingGitCommand == pendingGitCommand)&&(identical(other.pendingLocalCommand, pendingLocalCommand) || other.pendingLocalCommand == pendingLocalCommand)&&(identical(other.pendingFileOperation, pendingFileOperation) || other.pendingFileOperation == pendingFileOperation)&&(identical(other.pendingBleConnect, pendingBleConnect) || other.pendingBleConnect == pendingBleConnect)&&(identical(other.pendingWorkflowDecision, pendingWorkflowDecision) || other.pendingWorkflowDecision == pendingWorkflowDecision)&&(identical(other.isGeneratingWorkflowProposal, isGeneratingWorkflowProposal) || other.isGeneratingWorkflowProposal == isGeneratingWorkflowProposal)&&(identical(other.workflowProposalDraft, workflowProposalDraft) || other.workflowProposalDraft == workflowProposalDraft)&&(identical(other.workflowProposalError, workflowProposalError) || other.workflowProposalError == workflowProposalError)&&(identical(other.isGeneratingTaskProposal, isGeneratingTaskProposal) || other.isGeneratingTaskProposal == isGeneratingTaskProposal)&&(identical(other.taskProposalDraft, taskProposalDraft) || other.taskProposalDraft == taskProposalDraft)&&(identical(other.taskProposalError, taskProposalError) || other.taskProposalError == taskProposalError));
}


@override
int get hashCode => Object.hashAll([runtimeType,const DeepCollectionEquality().hash(messages),isLoading,error,promptTokens,completionTokens,totalTokens,pendingSshConnect,pendingSshCommand,pendingGitCommand,pendingLocalCommand,pendingFileOperation,pendingBleConnect,pendingWorkflowDecision,isGeneratingWorkflowProposal,workflowProposalDraft,workflowProposalError,isGeneratingTaskProposal,taskProposalDraft,taskProposalError]);

@override
String toString() {
  return 'ChatState(messages: $messages, isLoading: $isLoading, error: $error, promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, pendingSshConnect: $pendingSshConnect, pendingSshCommand: $pendingSshCommand, pendingGitCommand: $pendingGitCommand, pendingLocalCommand: $pendingLocalCommand, pendingFileOperation: $pendingFileOperation, pendingBleConnect: $pendingBleConnect, pendingWorkflowDecision: $pendingWorkflowDecision, isGeneratingWorkflowProposal: $isGeneratingWorkflowProposal, workflowProposalDraft: $workflowProposalDraft, workflowProposalError: $workflowProposalError, isGeneratingTaskProposal: $isGeneratingTaskProposal, taskProposalDraft: $taskProposalDraft, taskProposalError: $taskProposalError)';
}


}

/// @nodoc
abstract mixin class $ChatStateCopyWith<$Res>  {
  factory $ChatStateCopyWith(ChatState value, $Res Function(ChatState) _then) = _$ChatStateCopyWithImpl;
@useResult
$Res call({
 List<Message> messages, bool isLoading, String? error, int promptTokens, int completionTokens, int totalTokens, PendingSshConnect? pendingSshConnect, PendingSshCommand? pendingSshCommand, PendingGitCommand? pendingGitCommand, PendingLocalCommand? pendingLocalCommand, PendingFileOperation? pendingFileOperation, PendingBleConnect? pendingBleConnect, PendingWorkflowDecision? pendingWorkflowDecision, bool isGeneratingWorkflowProposal, WorkflowProposalDraft? workflowProposalDraft, String? workflowProposalError, bool isGeneratingTaskProposal, WorkflowTaskProposalDraft? taskProposalDraft, String? taskProposalError
});


$WorkflowProposalDraftCopyWith<$Res>? get workflowProposalDraft;$WorkflowTaskProposalDraftCopyWith<$Res>? get taskProposalDraft;

}
/// @nodoc
class _$ChatStateCopyWithImpl<$Res>
    implements $ChatStateCopyWith<$Res> {
  _$ChatStateCopyWithImpl(this._self, this._then);

  final ChatState _self;
  final $Res Function(ChatState) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? messages = null,Object? isLoading = null,Object? error = freezed,Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? pendingSshConnect = freezed,Object? pendingSshCommand = freezed,Object? pendingGitCommand = freezed,Object? pendingLocalCommand = freezed,Object? pendingFileOperation = freezed,Object? pendingBleConnect = freezed,Object? pendingWorkflowDecision = freezed,Object? isGeneratingWorkflowProposal = null,Object? workflowProposalDraft = freezed,Object? workflowProposalError = freezed,Object? isGeneratingTaskProposal = null,Object? taskProposalDraft = freezed,Object? taskProposalError = freezed,}) {
  return _then(_self.copyWith(
messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,pendingSshConnect: freezed == pendingSshConnect ? _self.pendingSshConnect : pendingSshConnect // ignore: cast_nullable_to_non_nullable
as PendingSshConnect?,pendingSshCommand: freezed == pendingSshCommand ? _self.pendingSshCommand : pendingSshCommand // ignore: cast_nullable_to_non_nullable
as PendingSshCommand?,pendingGitCommand: freezed == pendingGitCommand ? _self.pendingGitCommand : pendingGitCommand // ignore: cast_nullable_to_non_nullable
as PendingGitCommand?,pendingLocalCommand: freezed == pendingLocalCommand ? _self.pendingLocalCommand : pendingLocalCommand // ignore: cast_nullable_to_non_nullable
as PendingLocalCommand?,pendingFileOperation: freezed == pendingFileOperation ? _self.pendingFileOperation : pendingFileOperation // ignore: cast_nullable_to_non_nullable
as PendingFileOperation?,pendingBleConnect: freezed == pendingBleConnect ? _self.pendingBleConnect : pendingBleConnect // ignore: cast_nullable_to_non_nullable
as PendingBleConnect?,pendingWorkflowDecision: freezed == pendingWorkflowDecision ? _self.pendingWorkflowDecision : pendingWorkflowDecision // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Message> messages,  bool isLoading,  String? error,  int promptTokens,  int completionTokens,  int totalTokens,  PendingSshConnect? pendingSshConnect,  PendingSshCommand? pendingSshCommand,  PendingGitCommand? pendingGitCommand,  PendingLocalCommand? pendingLocalCommand,  PendingFileOperation? pendingFileOperation,  PendingBleConnect? pendingBleConnect,  PendingWorkflowDecision? pendingWorkflowDecision,  bool isGeneratingWorkflowProposal,  WorkflowProposalDraft? workflowProposalDraft,  String? workflowProposalError,  bool isGeneratingTaskProposal,  WorkflowTaskProposalDraft? taskProposalDraft,  String? taskProposalError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that.messages,_that.isLoading,_that.error,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.pendingSshConnect,_that.pendingSshCommand,_that.pendingGitCommand,_that.pendingLocalCommand,_that.pendingFileOperation,_that.pendingBleConnect,_that.pendingWorkflowDecision,_that.isGeneratingWorkflowProposal,_that.workflowProposalDraft,_that.workflowProposalError,_that.isGeneratingTaskProposal,_that.taskProposalDraft,_that.taskProposalError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Message> messages,  bool isLoading,  String? error,  int promptTokens,  int completionTokens,  int totalTokens,  PendingSshConnect? pendingSshConnect,  PendingSshCommand? pendingSshCommand,  PendingGitCommand? pendingGitCommand,  PendingLocalCommand? pendingLocalCommand,  PendingFileOperation? pendingFileOperation,  PendingBleConnect? pendingBleConnect,  PendingWorkflowDecision? pendingWorkflowDecision,  bool isGeneratingWorkflowProposal,  WorkflowProposalDraft? workflowProposalDraft,  String? workflowProposalError,  bool isGeneratingTaskProposal,  WorkflowTaskProposalDraft? taskProposalDraft,  String? taskProposalError)  $default,) {final _that = this;
switch (_that) {
case _ChatState():
return $default(_that.messages,_that.isLoading,_that.error,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.pendingSshConnect,_that.pendingSshCommand,_that.pendingGitCommand,_that.pendingLocalCommand,_that.pendingFileOperation,_that.pendingBleConnect,_that.pendingWorkflowDecision,_that.isGeneratingWorkflowProposal,_that.workflowProposalDraft,_that.workflowProposalError,_that.isGeneratingTaskProposal,_that.taskProposalDraft,_that.taskProposalError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Message> messages,  bool isLoading,  String? error,  int promptTokens,  int completionTokens,  int totalTokens,  PendingSshConnect? pendingSshConnect,  PendingSshCommand? pendingSshCommand,  PendingGitCommand? pendingGitCommand,  PendingLocalCommand? pendingLocalCommand,  PendingFileOperation? pendingFileOperation,  PendingBleConnect? pendingBleConnect,  PendingWorkflowDecision? pendingWorkflowDecision,  bool isGeneratingWorkflowProposal,  WorkflowProposalDraft? workflowProposalDraft,  String? workflowProposalError,  bool isGeneratingTaskProposal,  WorkflowTaskProposalDraft? taskProposalDraft,  String? taskProposalError)?  $default,) {final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that.messages,_that.isLoading,_that.error,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.pendingSshConnect,_that.pendingSshCommand,_that.pendingGitCommand,_that.pendingLocalCommand,_that.pendingFileOperation,_that.pendingBleConnect,_that.pendingWorkflowDecision,_that.isGeneratingWorkflowProposal,_that.workflowProposalDraft,_that.workflowProposalError,_that.isGeneratingTaskProposal,_that.taskProposalDraft,_that.taskProposalError);case _:
  return null;

}
}

}

/// @nodoc


class _ChatState implements ChatState {
  const _ChatState({required final  List<Message> messages, required this.isLoading, this.error, this.promptTokens = 0, this.completionTokens = 0, this.totalTokens = 0, this.pendingSshConnect, this.pendingSshCommand, this.pendingGitCommand, this.pendingLocalCommand, this.pendingFileOperation, this.pendingBleConnect, this.pendingWorkflowDecision, this.isGeneratingWorkflowProposal = false, this.workflowProposalDraft, this.workflowProposalError, this.isGeneratingTaskProposal = false, this.taskProposalDraft, this.taskProposalError}): _messages = messages;
  

 final  List<Message> _messages;
@override List<Message> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

@override final  bool isLoading;
@override final  String? error;
@override@JsonKey() final  int promptTokens;
@override@JsonKey() final  int completionTokens;
@override@JsonKey() final  int totalTokens;
// SSH tool UI flow — holders contain Completers so they live outside
// the freezed equality graph.
@override final  PendingSshConnect? pendingSshConnect;
@override final  PendingSshCommand? pendingSshCommand;
// Git tool UI flow — same Completer-based pattern as SSH.
@override final  PendingGitCommand? pendingGitCommand;
// Local shell tool UI flow.
@override final  PendingLocalCommand? pendingLocalCommand;
// File mutation tool UI flow.
@override final  PendingFileOperation? pendingFileOperation;
// BLE tool UI flow — same Completer-based pattern as SSH.
@override final  PendingBleConnect? pendingBleConnect;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatState&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.pendingSshConnect, pendingSshConnect) || other.pendingSshConnect == pendingSshConnect)&&(identical(other.pendingSshCommand, pendingSshCommand) || other.pendingSshCommand == pendingSshCommand)&&(identical(other.pendingGitCommand, pendingGitCommand) || other.pendingGitCommand == pendingGitCommand)&&(identical(other.pendingLocalCommand, pendingLocalCommand) || other.pendingLocalCommand == pendingLocalCommand)&&(identical(other.pendingFileOperation, pendingFileOperation) || other.pendingFileOperation == pendingFileOperation)&&(identical(other.pendingBleConnect, pendingBleConnect) || other.pendingBleConnect == pendingBleConnect)&&(identical(other.pendingWorkflowDecision, pendingWorkflowDecision) || other.pendingWorkflowDecision == pendingWorkflowDecision)&&(identical(other.isGeneratingWorkflowProposal, isGeneratingWorkflowProposal) || other.isGeneratingWorkflowProposal == isGeneratingWorkflowProposal)&&(identical(other.workflowProposalDraft, workflowProposalDraft) || other.workflowProposalDraft == workflowProposalDraft)&&(identical(other.workflowProposalError, workflowProposalError) || other.workflowProposalError == workflowProposalError)&&(identical(other.isGeneratingTaskProposal, isGeneratingTaskProposal) || other.isGeneratingTaskProposal == isGeneratingTaskProposal)&&(identical(other.taskProposalDraft, taskProposalDraft) || other.taskProposalDraft == taskProposalDraft)&&(identical(other.taskProposalError, taskProposalError) || other.taskProposalError == taskProposalError));
}


@override
int get hashCode => Object.hashAll([runtimeType,const DeepCollectionEquality().hash(_messages),isLoading,error,promptTokens,completionTokens,totalTokens,pendingSshConnect,pendingSshCommand,pendingGitCommand,pendingLocalCommand,pendingFileOperation,pendingBleConnect,pendingWorkflowDecision,isGeneratingWorkflowProposal,workflowProposalDraft,workflowProposalError,isGeneratingTaskProposal,taskProposalDraft,taskProposalError]);

@override
String toString() {
  return 'ChatState(messages: $messages, isLoading: $isLoading, error: $error, promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, pendingSshConnect: $pendingSshConnect, pendingSshCommand: $pendingSshCommand, pendingGitCommand: $pendingGitCommand, pendingLocalCommand: $pendingLocalCommand, pendingFileOperation: $pendingFileOperation, pendingBleConnect: $pendingBleConnect, pendingWorkflowDecision: $pendingWorkflowDecision, isGeneratingWorkflowProposal: $isGeneratingWorkflowProposal, workflowProposalDraft: $workflowProposalDraft, workflowProposalError: $workflowProposalError, isGeneratingTaskProposal: $isGeneratingTaskProposal, taskProposalDraft: $taskProposalDraft, taskProposalError: $taskProposalError)';
}


}

/// @nodoc
abstract mixin class _$ChatStateCopyWith<$Res> implements $ChatStateCopyWith<$Res> {
  factory _$ChatStateCopyWith(_ChatState value, $Res Function(_ChatState) _then) = __$ChatStateCopyWithImpl;
@override @useResult
$Res call({
 List<Message> messages, bool isLoading, String? error, int promptTokens, int completionTokens, int totalTokens, PendingSshConnect? pendingSshConnect, PendingSshCommand? pendingSshCommand, PendingGitCommand? pendingGitCommand, PendingLocalCommand? pendingLocalCommand, PendingFileOperation? pendingFileOperation, PendingBleConnect? pendingBleConnect, PendingWorkflowDecision? pendingWorkflowDecision, bool isGeneratingWorkflowProposal, WorkflowProposalDraft? workflowProposalDraft, String? workflowProposalError, bool isGeneratingTaskProposal, WorkflowTaskProposalDraft? taskProposalDraft, String? taskProposalError
});


@override $WorkflowProposalDraftCopyWith<$Res>? get workflowProposalDraft;@override $WorkflowTaskProposalDraftCopyWith<$Res>? get taskProposalDraft;

}
/// @nodoc
class __$ChatStateCopyWithImpl<$Res>
    implements _$ChatStateCopyWith<$Res> {
  __$ChatStateCopyWithImpl(this._self, this._then);

  final _ChatState _self;
  final $Res Function(_ChatState) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? messages = null,Object? isLoading = null,Object? error = freezed,Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? pendingSshConnect = freezed,Object? pendingSshCommand = freezed,Object? pendingGitCommand = freezed,Object? pendingLocalCommand = freezed,Object? pendingFileOperation = freezed,Object? pendingBleConnect = freezed,Object? pendingWorkflowDecision = freezed,Object? isGeneratingWorkflowProposal = null,Object? workflowProposalDraft = freezed,Object? workflowProposalError = freezed,Object? isGeneratingTaskProposal = null,Object? taskProposalDraft = freezed,Object? taskProposalError = freezed,}) {
  return _then(_ChatState(
messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,pendingSshConnect: freezed == pendingSshConnect ? _self.pendingSshConnect : pendingSshConnect // ignore: cast_nullable_to_non_nullable
as PendingSshConnect?,pendingSshCommand: freezed == pendingSshCommand ? _self.pendingSshCommand : pendingSshCommand // ignore: cast_nullable_to_non_nullable
as PendingSshCommand?,pendingGitCommand: freezed == pendingGitCommand ? _self.pendingGitCommand : pendingGitCommand // ignore: cast_nullable_to_non_nullable
as PendingGitCommand?,pendingLocalCommand: freezed == pendingLocalCommand ? _self.pendingLocalCommand : pendingLocalCommand // ignore: cast_nullable_to_non_nullable
as PendingLocalCommand?,pendingFileOperation: freezed == pendingFileOperation ? _self.pendingFileOperation : pendingFileOperation // ignore: cast_nullable_to_non_nullable
as PendingFileOperation?,pendingBleConnect: freezed == pendingBleConnect ? _self.pendingBleConnect : pendingBleConnect // ignore: cast_nullable_to_non_nullable
as PendingBleConnect?,pendingWorkflowDecision: freezed == pendingWorkflowDecision ? _self.pendingWorkflowDecision : pendingWorkflowDecision // ignore: cast_nullable_to_non_nullable
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
