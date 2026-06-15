// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'personal_eval_case.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PersonalEvalCase {

 String get caseId; String get prompt; String get repoStateRef; String get title; DateTime? get createdAt; String? get verificationCommand;@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) PersonalEvalVerificationResult get verificationResult; String? get workspaceMode;@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) PersonalEvalCaseSplit get split; bool get consentGranted; DateTime? get consentedAt; String get sessionLogPath; PersonalEvalSessionLogSummary? get sessionLogSummary;
/// Create a copy of PersonalEvalCase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersonalEvalCaseCopyWith<PersonalEvalCase> get copyWith => _$PersonalEvalCaseCopyWithImpl<PersonalEvalCase>(this as PersonalEvalCase, _$identity);

  /// Serializes this PersonalEvalCase to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersonalEvalCase&&(identical(other.caseId, caseId) || other.caseId == caseId)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.repoStateRef, repoStateRef) || other.repoStateRef == repoStateRef)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.verificationCommand, verificationCommand) || other.verificationCommand == verificationCommand)&&(identical(other.verificationResult, verificationResult) || other.verificationResult == verificationResult)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.split, split) || other.split == split)&&(identical(other.consentGranted, consentGranted) || other.consentGranted == consentGranted)&&(identical(other.consentedAt, consentedAt) || other.consentedAt == consentedAt)&&(identical(other.sessionLogPath, sessionLogPath) || other.sessionLogPath == sessionLogPath)&&(identical(other.sessionLogSummary, sessionLogSummary) || other.sessionLogSummary == sessionLogSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,caseId,prompt,repoStateRef,title,createdAt,verificationCommand,verificationResult,workspaceMode,split,consentGranted,consentedAt,sessionLogPath,sessionLogSummary);

@override
String toString() {
  return 'PersonalEvalCase(caseId: $caseId, prompt: $prompt, repoStateRef: $repoStateRef, title: $title, createdAt: $createdAt, verificationCommand: $verificationCommand, verificationResult: $verificationResult, workspaceMode: $workspaceMode, split: $split, consentGranted: $consentGranted, consentedAt: $consentedAt, sessionLogPath: $sessionLogPath, sessionLogSummary: $sessionLogSummary)';
}


}

/// @nodoc
abstract mixin class $PersonalEvalCaseCopyWith<$Res>  {
  factory $PersonalEvalCaseCopyWith(PersonalEvalCase value, $Res Function(PersonalEvalCase) _then) = _$PersonalEvalCaseCopyWithImpl;
@useResult
$Res call({
 String caseId, String prompt, String repoStateRef, String title, DateTime? createdAt, String? verificationCommand,@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) PersonalEvalVerificationResult verificationResult, String? workspaceMode,@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) PersonalEvalCaseSplit split, bool consentGranted, DateTime? consentedAt, String sessionLogPath, PersonalEvalSessionLogSummary? sessionLogSummary
});


$PersonalEvalSessionLogSummaryCopyWith<$Res>? get sessionLogSummary;

}
/// @nodoc
class _$PersonalEvalCaseCopyWithImpl<$Res>
    implements $PersonalEvalCaseCopyWith<$Res> {
  _$PersonalEvalCaseCopyWithImpl(this._self, this._then);

  final PersonalEvalCase _self;
  final $Res Function(PersonalEvalCase) _then;

/// Create a copy of PersonalEvalCase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? caseId = null,Object? prompt = null,Object? repoStateRef = null,Object? title = null,Object? createdAt = freezed,Object? verificationCommand = freezed,Object? verificationResult = null,Object? workspaceMode = freezed,Object? split = null,Object? consentGranted = null,Object? consentedAt = freezed,Object? sessionLogPath = null,Object? sessionLogSummary = freezed,}) {
  return _then(_self.copyWith(
caseId: null == caseId ? _self.caseId : caseId // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,repoStateRef: null == repoStateRef ? _self.repoStateRef : repoStateRef // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,verificationCommand: freezed == verificationCommand ? _self.verificationCommand : verificationCommand // ignore: cast_nullable_to_non_nullable
as String?,verificationResult: null == verificationResult ? _self.verificationResult : verificationResult // ignore: cast_nullable_to_non_nullable
as PersonalEvalVerificationResult,workspaceMode: freezed == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as String?,split: null == split ? _self.split : split // ignore: cast_nullable_to_non_nullable
as PersonalEvalCaseSplit,consentGranted: null == consentGranted ? _self.consentGranted : consentGranted // ignore: cast_nullable_to_non_nullable
as bool,consentedAt: freezed == consentedAt ? _self.consentedAt : consentedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sessionLogPath: null == sessionLogPath ? _self.sessionLogPath : sessionLogPath // ignore: cast_nullable_to_non_nullable
as String,sessionLogSummary: freezed == sessionLogSummary ? _self.sessionLogSummary : sessionLogSummary // ignore: cast_nullable_to_non_nullable
as PersonalEvalSessionLogSummary?,
  ));
}
/// Create a copy of PersonalEvalCase
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersonalEvalSessionLogSummaryCopyWith<$Res>? get sessionLogSummary {
    if (_self.sessionLogSummary == null) {
    return null;
  }

  return $PersonalEvalSessionLogSummaryCopyWith<$Res>(_self.sessionLogSummary!, (value) {
    return _then(_self.copyWith(sessionLogSummary: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersonalEvalCase].
extension PersonalEvalCasePatterns on PersonalEvalCase {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersonalEvalCase value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersonalEvalCase() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersonalEvalCase value)  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalCase():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersonalEvalCase value)?  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalCase() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String caseId,  String prompt,  String repoStateRef,  String title,  DateTime? createdAt,  String? verificationCommand, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)  PersonalEvalVerificationResult verificationResult,  String? workspaceMode, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)  PersonalEvalCaseSplit split,  bool consentGranted,  DateTime? consentedAt,  String sessionLogPath,  PersonalEvalSessionLogSummary? sessionLogSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersonalEvalCase() when $default != null:
return $default(_that.caseId,_that.prompt,_that.repoStateRef,_that.title,_that.createdAt,_that.verificationCommand,_that.verificationResult,_that.workspaceMode,_that.split,_that.consentGranted,_that.consentedAt,_that.sessionLogPath,_that.sessionLogSummary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String caseId,  String prompt,  String repoStateRef,  String title,  DateTime? createdAt,  String? verificationCommand, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)  PersonalEvalVerificationResult verificationResult,  String? workspaceMode, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)  PersonalEvalCaseSplit split,  bool consentGranted,  DateTime? consentedAt,  String sessionLogPath,  PersonalEvalSessionLogSummary? sessionLogSummary)  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalCase():
return $default(_that.caseId,_that.prompt,_that.repoStateRef,_that.title,_that.createdAt,_that.verificationCommand,_that.verificationResult,_that.workspaceMode,_that.split,_that.consentGranted,_that.consentedAt,_that.sessionLogPath,_that.sessionLogSummary);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String caseId,  String prompt,  String repoStateRef,  String title,  DateTime? createdAt,  String? verificationCommand, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)  PersonalEvalVerificationResult verificationResult,  String? workspaceMode, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)  PersonalEvalCaseSplit split,  bool consentGranted,  DateTime? consentedAt,  String sessionLogPath,  PersonalEvalSessionLogSummary? sessionLogSummary)?  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalCase() when $default != null:
return $default(_that.caseId,_that.prompt,_that.repoStateRef,_that.title,_that.createdAt,_that.verificationCommand,_that.verificationResult,_that.workspaceMode,_that.split,_that.consentGranted,_that.consentedAt,_that.sessionLogPath,_that.sessionLogSummary);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PersonalEvalCase extends PersonalEvalCase {
  const _PersonalEvalCase({required this.caseId, required this.prompt, required this.repoStateRef, this.title = '', this.createdAt, this.verificationCommand, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) this.verificationResult = PersonalEvalVerificationResult.inconclusive, this.workspaceMode, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) this.split = PersonalEvalCaseSplit.heldIn, this.consentGranted = false, this.consentedAt, this.sessionLogPath = '', this.sessionLogSummary}): super._();
  factory _PersonalEvalCase.fromJson(Map<String, dynamic> json) => _$PersonalEvalCaseFromJson(json);

@override final  String caseId;
@override final  String prompt;
@override final  String repoStateRef;
@override@JsonKey() final  String title;
@override final  DateTime? createdAt;
@override final  String? verificationCommand;
@override@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) final  PersonalEvalVerificationResult verificationResult;
@override final  String? workspaceMode;
@override@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) final  PersonalEvalCaseSplit split;
@override@JsonKey() final  bool consentGranted;
@override final  DateTime? consentedAt;
@override@JsonKey() final  String sessionLogPath;
@override final  PersonalEvalSessionLogSummary? sessionLogSummary;

/// Create a copy of PersonalEvalCase
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersonalEvalCaseCopyWith<_PersonalEvalCase> get copyWith => __$PersonalEvalCaseCopyWithImpl<_PersonalEvalCase>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PersonalEvalCaseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersonalEvalCase&&(identical(other.caseId, caseId) || other.caseId == caseId)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.repoStateRef, repoStateRef) || other.repoStateRef == repoStateRef)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.verificationCommand, verificationCommand) || other.verificationCommand == verificationCommand)&&(identical(other.verificationResult, verificationResult) || other.verificationResult == verificationResult)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.split, split) || other.split == split)&&(identical(other.consentGranted, consentGranted) || other.consentGranted == consentGranted)&&(identical(other.consentedAt, consentedAt) || other.consentedAt == consentedAt)&&(identical(other.sessionLogPath, sessionLogPath) || other.sessionLogPath == sessionLogPath)&&(identical(other.sessionLogSummary, sessionLogSummary) || other.sessionLogSummary == sessionLogSummary));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,caseId,prompt,repoStateRef,title,createdAt,verificationCommand,verificationResult,workspaceMode,split,consentGranted,consentedAt,sessionLogPath,sessionLogSummary);

@override
String toString() {
  return 'PersonalEvalCase(caseId: $caseId, prompt: $prompt, repoStateRef: $repoStateRef, title: $title, createdAt: $createdAt, verificationCommand: $verificationCommand, verificationResult: $verificationResult, workspaceMode: $workspaceMode, split: $split, consentGranted: $consentGranted, consentedAt: $consentedAt, sessionLogPath: $sessionLogPath, sessionLogSummary: $sessionLogSummary)';
}


}

/// @nodoc
abstract mixin class _$PersonalEvalCaseCopyWith<$Res> implements $PersonalEvalCaseCopyWith<$Res> {
  factory _$PersonalEvalCaseCopyWith(_PersonalEvalCase value, $Res Function(_PersonalEvalCase) _then) = __$PersonalEvalCaseCopyWithImpl;
@override @useResult
$Res call({
 String caseId, String prompt, String repoStateRef, String title, DateTime? createdAt, String? verificationCommand,@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) PersonalEvalVerificationResult verificationResult, String? workspaceMode,@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) PersonalEvalCaseSplit split, bool consentGranted, DateTime? consentedAt, String sessionLogPath, PersonalEvalSessionLogSummary? sessionLogSummary
});


@override $PersonalEvalSessionLogSummaryCopyWith<$Res>? get sessionLogSummary;

}
/// @nodoc
class __$PersonalEvalCaseCopyWithImpl<$Res>
    implements _$PersonalEvalCaseCopyWith<$Res> {
  __$PersonalEvalCaseCopyWithImpl(this._self, this._then);

  final _PersonalEvalCase _self;
  final $Res Function(_PersonalEvalCase) _then;

/// Create a copy of PersonalEvalCase
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? caseId = null,Object? prompt = null,Object? repoStateRef = null,Object? title = null,Object? createdAt = freezed,Object? verificationCommand = freezed,Object? verificationResult = null,Object? workspaceMode = freezed,Object? split = null,Object? consentGranted = null,Object? consentedAt = freezed,Object? sessionLogPath = null,Object? sessionLogSummary = freezed,}) {
  return _then(_PersonalEvalCase(
caseId: null == caseId ? _self.caseId : caseId // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,repoStateRef: null == repoStateRef ? _self.repoStateRef : repoStateRef // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,verificationCommand: freezed == verificationCommand ? _self.verificationCommand : verificationCommand // ignore: cast_nullable_to_non_nullable
as String?,verificationResult: null == verificationResult ? _self.verificationResult : verificationResult // ignore: cast_nullable_to_non_nullable
as PersonalEvalVerificationResult,workspaceMode: freezed == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as String?,split: null == split ? _self.split : split // ignore: cast_nullable_to_non_nullable
as PersonalEvalCaseSplit,consentGranted: null == consentGranted ? _self.consentGranted : consentGranted // ignore: cast_nullable_to_non_nullable
as bool,consentedAt: freezed == consentedAt ? _self.consentedAt : consentedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sessionLogPath: null == sessionLogPath ? _self.sessionLogPath : sessionLogPath // ignore: cast_nullable_to_non_nullable
as String,sessionLogSummary: freezed == sessionLogSummary ? _self.sessionLogSummary : sessionLogSummary // ignore: cast_nullable_to_non_nullable
as PersonalEvalSessionLogSummary?,
  ));
}

/// Create a copy of PersonalEvalCase
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersonalEvalSessionLogSummaryCopyWith<$Res>? get sessionLogSummary {
    if (_self.sessionLogSummary == null) {
    return null;
  }

  return $PersonalEvalSessionLogSummaryCopyWith<$Res>(_self.sessionLogSummary!, (value) {
    return _then(_self.copyWith(sessionLogSummary: value));
  });
}
}

// dart format on
