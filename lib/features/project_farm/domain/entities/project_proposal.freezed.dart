// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project_proposal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProjectProposal {

 String get projectId; String get inputHash; DateTime get proposedAt;/// Empty when the orchestrator proposed starting nothing, or failed.
 String get taskId; String get taskTitle; String get rationale;/// `unattended` or `needsHuman`; empty when there is no proposal.
 String get automatability; String get automatabilityReason; String? get error;
/// Create a copy of ProjectProposal
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectProposalCopyWith<ProjectProposal> get copyWith => _$ProjectProposalCopyWithImpl<ProjectProposal>(this as ProjectProposal, _$identity);

  /// Serializes this ProjectProposal to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectProposal&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.inputHash, inputHash) || other.inputHash == inputHash)&&(identical(other.proposedAt, proposedAt) || other.proposedAt == proposedAt)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.taskTitle, taskTitle) || other.taskTitle == taskTitle)&&(identical(other.rationale, rationale) || other.rationale == rationale)&&(identical(other.automatability, automatability) || other.automatability == automatability)&&(identical(other.automatabilityReason, automatabilityReason) || other.automatabilityReason == automatabilityReason)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,projectId,inputHash,proposedAt,taskId,taskTitle,rationale,automatability,automatabilityReason,error);

@override
String toString() {
  return 'ProjectProposal(projectId: $projectId, inputHash: $inputHash, proposedAt: $proposedAt, taskId: $taskId, taskTitle: $taskTitle, rationale: $rationale, automatability: $automatability, automatabilityReason: $automatabilityReason, error: $error)';
}


}

/// @nodoc
abstract mixin class $ProjectProposalCopyWith<$Res>  {
  factory $ProjectProposalCopyWith(ProjectProposal value, $Res Function(ProjectProposal) _then) = _$ProjectProposalCopyWithImpl;
@useResult
$Res call({
 String projectId, String inputHash, DateTime proposedAt, String taskId, String taskTitle, String rationale, String automatability, String automatabilityReason, String? error
});




}
/// @nodoc
class _$ProjectProposalCopyWithImpl<$Res>
    implements $ProjectProposalCopyWith<$Res> {
  _$ProjectProposalCopyWithImpl(this._self, this._then);

  final ProjectProposal _self;
  final $Res Function(ProjectProposal) _then;

/// Create a copy of ProjectProposal
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? inputHash = null,Object? proposedAt = null,Object? taskId = null,Object? taskTitle = null,Object? rationale = null,Object? automatability = null,Object? automatabilityReason = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,inputHash: null == inputHash ? _self.inputHash : inputHash // ignore: cast_nullable_to_non_nullable
as String,proposedAt: null == proposedAt ? _self.proposedAt : proposedAt // ignore: cast_nullable_to_non_nullable
as DateTime,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,taskTitle: null == taskTitle ? _self.taskTitle : taskTitle // ignore: cast_nullable_to_non_nullable
as String,rationale: null == rationale ? _self.rationale : rationale // ignore: cast_nullable_to_non_nullable
as String,automatability: null == automatability ? _self.automatability : automatability // ignore: cast_nullable_to_non_nullable
as String,automatabilityReason: null == automatabilityReason ? _self.automatabilityReason : automatabilityReason // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectProposal].
extension ProjectProposalPatterns on ProjectProposal {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectProposal value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectProposal() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectProposal value)  $default,){
final _that = this;
switch (_that) {
case _ProjectProposal():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectProposal value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectProposal() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  String inputHash,  DateTime proposedAt,  String taskId,  String taskTitle,  String rationale,  String automatability,  String automatabilityReason,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectProposal() when $default != null:
return $default(_that.projectId,_that.inputHash,_that.proposedAt,_that.taskId,_that.taskTitle,_that.rationale,_that.automatability,_that.automatabilityReason,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  String inputHash,  DateTime proposedAt,  String taskId,  String taskTitle,  String rationale,  String automatability,  String automatabilityReason,  String? error)  $default,) {final _that = this;
switch (_that) {
case _ProjectProposal():
return $default(_that.projectId,_that.inputHash,_that.proposedAt,_that.taskId,_that.taskTitle,_that.rationale,_that.automatability,_that.automatabilityReason,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  String inputHash,  DateTime proposedAt,  String taskId,  String taskTitle,  String rationale,  String automatability,  String automatabilityReason,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _ProjectProposal() when $default != null:
return $default(_that.projectId,_that.inputHash,_that.proposedAt,_that.taskId,_that.taskTitle,_that.rationale,_that.automatability,_that.automatabilityReason,_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProjectProposal implements ProjectProposal {
  const _ProjectProposal({required this.projectId, required this.inputHash, required this.proposedAt, this.taskId = '', this.taskTitle = '', this.rationale = '', this.automatability = '', this.automatabilityReason = '', this.error});
  factory _ProjectProposal.fromJson(Map<String, dynamic> json) => _$ProjectProposalFromJson(json);

@override final  String projectId;
@override final  String inputHash;
@override final  DateTime proposedAt;
/// Empty when the orchestrator proposed starting nothing, or failed.
@override@JsonKey() final  String taskId;
@override@JsonKey() final  String taskTitle;
@override@JsonKey() final  String rationale;
/// `unattended` or `needsHuman`; empty when there is no proposal.
@override@JsonKey() final  String automatability;
@override@JsonKey() final  String automatabilityReason;
@override final  String? error;

/// Create a copy of ProjectProposal
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectProposalCopyWith<_ProjectProposal> get copyWith => __$ProjectProposalCopyWithImpl<_ProjectProposal>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProjectProposalToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectProposal&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.inputHash, inputHash) || other.inputHash == inputHash)&&(identical(other.proposedAt, proposedAt) || other.proposedAt == proposedAt)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.taskTitle, taskTitle) || other.taskTitle == taskTitle)&&(identical(other.rationale, rationale) || other.rationale == rationale)&&(identical(other.automatability, automatability) || other.automatability == automatability)&&(identical(other.automatabilityReason, automatabilityReason) || other.automatabilityReason == automatabilityReason)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,projectId,inputHash,proposedAt,taskId,taskTitle,rationale,automatability,automatabilityReason,error);

@override
String toString() {
  return 'ProjectProposal(projectId: $projectId, inputHash: $inputHash, proposedAt: $proposedAt, taskId: $taskId, taskTitle: $taskTitle, rationale: $rationale, automatability: $automatability, automatabilityReason: $automatabilityReason, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ProjectProposalCopyWith<$Res> implements $ProjectProposalCopyWith<$Res> {
  factory _$ProjectProposalCopyWith(_ProjectProposal value, $Res Function(_ProjectProposal) _then) = __$ProjectProposalCopyWithImpl;
@override @useResult
$Res call({
 String projectId, String inputHash, DateTime proposedAt, String taskId, String taskTitle, String rationale, String automatability, String automatabilityReason, String? error
});




}
/// @nodoc
class __$ProjectProposalCopyWithImpl<$Res>
    implements _$ProjectProposalCopyWith<$Res> {
  __$ProjectProposalCopyWithImpl(this._self, this._then);

  final _ProjectProposal _self;
  final $Res Function(_ProjectProposal) _then;

/// Create a copy of ProjectProposal
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? inputHash = null,Object? proposedAt = null,Object? taskId = null,Object? taskTitle = null,Object? rationale = null,Object? automatability = null,Object? automatabilityReason = null,Object? error = freezed,}) {
  return _then(_ProjectProposal(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,inputHash: null == inputHash ? _self.inputHash : inputHash // ignore: cast_nullable_to_non_nullable
as String,proposedAt: null == proposedAt ? _self.proposedAt : proposedAt // ignore: cast_nullable_to_non_nullable
as DateTime,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,taskTitle: null == taskTitle ? _self.taskTitle : taskTitle // ignore: cast_nullable_to_non_nullable
as String,rationale: null == rationale ? _self.rationale : rationale // ignore: cast_nullable_to_non_nullable
as String,automatability: null == automatability ? _self.automatability : automatability // ignore: cast_nullable_to_non_nullable
as String,automatabilityReason: null == automatabilityReason ? _self.automatabilityReason : automatabilityReason // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
