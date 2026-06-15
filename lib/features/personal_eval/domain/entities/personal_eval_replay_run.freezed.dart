// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'personal_eval_replay_run.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PersonalEvalReplayCaseResult {

 String get caseId; String get title;@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) PersonalEvalCaseSplit get split; String get logPath;@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) PersonalEvalVerificationResult get verificationResult; PersonalEvalSessionLogSummary get summary; String? get error;
/// Create a copy of PersonalEvalReplayCaseResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersonalEvalReplayCaseResultCopyWith<PersonalEvalReplayCaseResult> get copyWith => _$PersonalEvalReplayCaseResultCopyWithImpl<PersonalEvalReplayCaseResult>(this as PersonalEvalReplayCaseResult, _$identity);

  /// Serializes this PersonalEvalReplayCaseResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersonalEvalReplayCaseResult&&(identical(other.caseId, caseId) || other.caseId == caseId)&&(identical(other.title, title) || other.title == title)&&(identical(other.split, split) || other.split == split)&&(identical(other.logPath, logPath) || other.logPath == logPath)&&(identical(other.verificationResult, verificationResult) || other.verificationResult == verificationResult)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,caseId,title,split,logPath,verificationResult,summary,error);

@override
String toString() {
  return 'PersonalEvalReplayCaseResult(caseId: $caseId, title: $title, split: $split, logPath: $logPath, verificationResult: $verificationResult, summary: $summary, error: $error)';
}


}

/// @nodoc
abstract mixin class $PersonalEvalReplayCaseResultCopyWith<$Res>  {
  factory $PersonalEvalReplayCaseResultCopyWith(PersonalEvalReplayCaseResult value, $Res Function(PersonalEvalReplayCaseResult) _then) = _$PersonalEvalReplayCaseResultCopyWithImpl;
@useResult
$Res call({
 String caseId, String title,@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) PersonalEvalCaseSplit split, String logPath,@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) PersonalEvalVerificationResult verificationResult, PersonalEvalSessionLogSummary summary, String? error
});


$PersonalEvalSessionLogSummaryCopyWith<$Res> get summary;

}
/// @nodoc
class _$PersonalEvalReplayCaseResultCopyWithImpl<$Res>
    implements $PersonalEvalReplayCaseResultCopyWith<$Res> {
  _$PersonalEvalReplayCaseResultCopyWithImpl(this._self, this._then);

  final PersonalEvalReplayCaseResult _self;
  final $Res Function(PersonalEvalReplayCaseResult) _then;

/// Create a copy of PersonalEvalReplayCaseResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? caseId = null,Object? title = null,Object? split = null,Object? logPath = null,Object? verificationResult = null,Object? summary = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
caseId: null == caseId ? _self.caseId : caseId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,split: null == split ? _self.split : split // ignore: cast_nullable_to_non_nullable
as PersonalEvalCaseSplit,logPath: null == logPath ? _self.logPath : logPath // ignore: cast_nullable_to_non_nullable
as String,verificationResult: null == verificationResult ? _self.verificationResult : verificationResult // ignore: cast_nullable_to_non_nullable
as PersonalEvalVerificationResult,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as PersonalEvalSessionLogSummary,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of PersonalEvalReplayCaseResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersonalEvalSessionLogSummaryCopyWith<$Res> get summary {
  
  return $PersonalEvalSessionLogSummaryCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersonalEvalReplayCaseResult].
extension PersonalEvalReplayCaseResultPatterns on PersonalEvalReplayCaseResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersonalEvalReplayCaseResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersonalEvalReplayCaseResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersonalEvalReplayCaseResult value)  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalReplayCaseResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersonalEvalReplayCaseResult value)?  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalReplayCaseResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String caseId,  String title, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)  PersonalEvalCaseSplit split,  String logPath, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)  PersonalEvalVerificationResult verificationResult,  PersonalEvalSessionLogSummary summary,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersonalEvalReplayCaseResult() when $default != null:
return $default(_that.caseId,_that.title,_that.split,_that.logPath,_that.verificationResult,_that.summary,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String caseId,  String title, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)  PersonalEvalCaseSplit split,  String logPath, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)  PersonalEvalVerificationResult verificationResult,  PersonalEvalSessionLogSummary summary,  String? error)  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalReplayCaseResult():
return $default(_that.caseId,_that.title,_that.split,_that.logPath,_that.verificationResult,_that.summary,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String caseId,  String title, @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)  PersonalEvalCaseSplit split,  String logPath, @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)  PersonalEvalVerificationResult verificationResult,  PersonalEvalSessionLogSummary summary,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalReplayCaseResult() when $default != null:
return $default(_that.caseId,_that.title,_that.split,_that.logPath,_that.verificationResult,_that.summary,_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PersonalEvalReplayCaseResult extends PersonalEvalReplayCaseResult {
  const _PersonalEvalReplayCaseResult({required this.caseId, this.title = '', @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) this.split = PersonalEvalCaseSplit.heldIn, this.logPath = '', @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) this.verificationResult = PersonalEvalVerificationResult.inconclusive, this.summary = const PersonalEvalSessionLogSummary(), this.error}): super._();
  factory _PersonalEvalReplayCaseResult.fromJson(Map<String, dynamic> json) => _$PersonalEvalReplayCaseResultFromJson(json);

@override final  String caseId;
@override@JsonKey() final  String title;
@override@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) final  PersonalEvalCaseSplit split;
@override@JsonKey() final  String logPath;
@override@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) final  PersonalEvalVerificationResult verificationResult;
@override@JsonKey() final  PersonalEvalSessionLogSummary summary;
@override final  String? error;

/// Create a copy of PersonalEvalReplayCaseResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersonalEvalReplayCaseResultCopyWith<_PersonalEvalReplayCaseResult> get copyWith => __$PersonalEvalReplayCaseResultCopyWithImpl<_PersonalEvalReplayCaseResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PersonalEvalReplayCaseResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersonalEvalReplayCaseResult&&(identical(other.caseId, caseId) || other.caseId == caseId)&&(identical(other.title, title) || other.title == title)&&(identical(other.split, split) || other.split == split)&&(identical(other.logPath, logPath) || other.logPath == logPath)&&(identical(other.verificationResult, verificationResult) || other.verificationResult == verificationResult)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,caseId,title,split,logPath,verificationResult,summary,error);

@override
String toString() {
  return 'PersonalEvalReplayCaseResult(caseId: $caseId, title: $title, split: $split, logPath: $logPath, verificationResult: $verificationResult, summary: $summary, error: $error)';
}


}

/// @nodoc
abstract mixin class _$PersonalEvalReplayCaseResultCopyWith<$Res> implements $PersonalEvalReplayCaseResultCopyWith<$Res> {
  factory _$PersonalEvalReplayCaseResultCopyWith(_PersonalEvalReplayCaseResult value, $Res Function(_PersonalEvalReplayCaseResult) _then) = __$PersonalEvalReplayCaseResultCopyWithImpl;
@override @useResult
$Res call({
 String caseId, String title,@JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn) PersonalEvalCaseSplit split, String logPath,@JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive) PersonalEvalVerificationResult verificationResult, PersonalEvalSessionLogSummary summary, String? error
});


@override $PersonalEvalSessionLogSummaryCopyWith<$Res> get summary;

}
/// @nodoc
class __$PersonalEvalReplayCaseResultCopyWithImpl<$Res>
    implements _$PersonalEvalReplayCaseResultCopyWith<$Res> {
  __$PersonalEvalReplayCaseResultCopyWithImpl(this._self, this._then);

  final _PersonalEvalReplayCaseResult _self;
  final $Res Function(_PersonalEvalReplayCaseResult) _then;

/// Create a copy of PersonalEvalReplayCaseResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? caseId = null,Object? title = null,Object? split = null,Object? logPath = null,Object? verificationResult = null,Object? summary = null,Object? error = freezed,}) {
  return _then(_PersonalEvalReplayCaseResult(
caseId: null == caseId ? _self.caseId : caseId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,split: null == split ? _self.split : split // ignore: cast_nullable_to_non_nullable
as PersonalEvalCaseSplit,logPath: null == logPath ? _self.logPath : logPath // ignore: cast_nullable_to_non_nullable
as String,verificationResult: null == verificationResult ? _self.verificationResult : verificationResult // ignore: cast_nullable_to_non_nullable
as PersonalEvalVerificationResult,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as PersonalEvalSessionLogSummary,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of PersonalEvalReplayCaseResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersonalEvalSessionLogSummaryCopyWith<$Res> get summary {
  
  return $PersonalEvalSessionLogSummaryCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}
}


/// @nodoc
mixin _$PersonalEvalReplayRun {

 String get label; String? get model; String? get baseUrl; DateTime? get generatedAt; List<String> get manifestPaths; List<PersonalEvalReplayCaseResult> get cases;
/// Create a copy of PersonalEvalReplayRun
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersonalEvalReplayRunCopyWith<PersonalEvalReplayRun> get copyWith => _$PersonalEvalReplayRunCopyWithImpl<PersonalEvalReplayRun>(this as PersonalEvalReplayRun, _$identity);

  /// Serializes this PersonalEvalReplayRun to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersonalEvalReplayRun&&(identical(other.label, label) || other.label == label)&&(identical(other.model, model) || other.model == model)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&const DeepCollectionEquality().equals(other.manifestPaths, manifestPaths)&&const DeepCollectionEquality().equals(other.cases, cases));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,label,model,baseUrl,generatedAt,const DeepCollectionEquality().hash(manifestPaths),const DeepCollectionEquality().hash(cases));

@override
String toString() {
  return 'PersonalEvalReplayRun(label: $label, model: $model, baseUrl: $baseUrl, generatedAt: $generatedAt, manifestPaths: $manifestPaths, cases: $cases)';
}


}

/// @nodoc
abstract mixin class $PersonalEvalReplayRunCopyWith<$Res>  {
  factory $PersonalEvalReplayRunCopyWith(PersonalEvalReplayRun value, $Res Function(PersonalEvalReplayRun) _then) = _$PersonalEvalReplayRunCopyWithImpl;
@useResult
$Res call({
 String label, String? model, String? baseUrl, DateTime? generatedAt, List<String> manifestPaths, List<PersonalEvalReplayCaseResult> cases
});




}
/// @nodoc
class _$PersonalEvalReplayRunCopyWithImpl<$Res>
    implements $PersonalEvalReplayRunCopyWith<$Res> {
  _$PersonalEvalReplayRunCopyWithImpl(this._self, this._then);

  final PersonalEvalReplayRun _self;
  final $Res Function(PersonalEvalReplayRun) _then;

/// Create a copy of PersonalEvalReplayRun
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? model = freezed,Object? baseUrl = freezed,Object? generatedAt = freezed,Object? manifestPaths = null,Object? cases = null,}) {
  return _then(_self.copyWith(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,baseUrl: freezed == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String?,generatedAt: freezed == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,manifestPaths: null == manifestPaths ? _self.manifestPaths : manifestPaths // ignore: cast_nullable_to_non_nullable
as List<String>,cases: null == cases ? _self.cases : cases // ignore: cast_nullable_to_non_nullable
as List<PersonalEvalReplayCaseResult>,
  ));
}

}


/// Adds pattern-matching-related methods to [PersonalEvalReplayRun].
extension PersonalEvalReplayRunPatterns on PersonalEvalReplayRun {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersonalEvalReplayRun value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersonalEvalReplayRun() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersonalEvalReplayRun value)  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalReplayRun():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersonalEvalReplayRun value)?  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalReplayRun() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  String? model,  String? baseUrl,  DateTime? generatedAt,  List<String> manifestPaths,  List<PersonalEvalReplayCaseResult> cases)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersonalEvalReplayRun() when $default != null:
return $default(_that.label,_that.model,_that.baseUrl,_that.generatedAt,_that.manifestPaths,_that.cases);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  String? model,  String? baseUrl,  DateTime? generatedAt,  List<String> manifestPaths,  List<PersonalEvalReplayCaseResult> cases)  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalReplayRun():
return $default(_that.label,_that.model,_that.baseUrl,_that.generatedAt,_that.manifestPaths,_that.cases);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  String? model,  String? baseUrl,  DateTime? generatedAt,  List<String> manifestPaths,  List<PersonalEvalReplayCaseResult> cases)?  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalReplayRun() when $default != null:
return $default(_that.label,_that.model,_that.baseUrl,_that.generatedAt,_that.manifestPaths,_that.cases);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PersonalEvalReplayRun extends PersonalEvalReplayRun {
  const _PersonalEvalReplayRun({required this.label, this.model, this.baseUrl, this.generatedAt, final  List<String> manifestPaths = const <String>[], final  List<PersonalEvalReplayCaseResult> cases = const <PersonalEvalReplayCaseResult>[]}): _manifestPaths = manifestPaths,_cases = cases,super._();
  factory _PersonalEvalReplayRun.fromJson(Map<String, dynamic> json) => _$PersonalEvalReplayRunFromJson(json);

@override final  String label;
@override final  String? model;
@override final  String? baseUrl;
@override final  DateTime? generatedAt;
 final  List<String> _manifestPaths;
@override@JsonKey() List<String> get manifestPaths {
  if (_manifestPaths is EqualUnmodifiableListView) return _manifestPaths;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_manifestPaths);
}

 final  List<PersonalEvalReplayCaseResult> _cases;
@override@JsonKey() List<PersonalEvalReplayCaseResult> get cases {
  if (_cases is EqualUnmodifiableListView) return _cases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_cases);
}


/// Create a copy of PersonalEvalReplayRun
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersonalEvalReplayRunCopyWith<_PersonalEvalReplayRun> get copyWith => __$PersonalEvalReplayRunCopyWithImpl<_PersonalEvalReplayRun>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PersonalEvalReplayRunToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersonalEvalReplayRun&&(identical(other.label, label) || other.label == label)&&(identical(other.model, model) || other.model == model)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&const DeepCollectionEquality().equals(other._manifestPaths, _manifestPaths)&&const DeepCollectionEquality().equals(other._cases, _cases));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,label,model,baseUrl,generatedAt,const DeepCollectionEquality().hash(_manifestPaths),const DeepCollectionEquality().hash(_cases));

@override
String toString() {
  return 'PersonalEvalReplayRun(label: $label, model: $model, baseUrl: $baseUrl, generatedAt: $generatedAt, manifestPaths: $manifestPaths, cases: $cases)';
}


}

/// @nodoc
abstract mixin class _$PersonalEvalReplayRunCopyWith<$Res> implements $PersonalEvalReplayRunCopyWith<$Res> {
  factory _$PersonalEvalReplayRunCopyWith(_PersonalEvalReplayRun value, $Res Function(_PersonalEvalReplayRun) _then) = __$PersonalEvalReplayRunCopyWithImpl;
@override @useResult
$Res call({
 String label, String? model, String? baseUrl, DateTime? generatedAt, List<String> manifestPaths, List<PersonalEvalReplayCaseResult> cases
});




}
/// @nodoc
class __$PersonalEvalReplayRunCopyWithImpl<$Res>
    implements _$PersonalEvalReplayRunCopyWith<$Res> {
  __$PersonalEvalReplayRunCopyWithImpl(this._self, this._then);

  final _PersonalEvalReplayRun _self;
  final $Res Function(_PersonalEvalReplayRun) _then;

/// Create a copy of PersonalEvalReplayRun
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? model = freezed,Object? baseUrl = freezed,Object? generatedAt = freezed,Object? manifestPaths = null,Object? cases = null,}) {
  return _then(_PersonalEvalReplayRun(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,baseUrl: freezed == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String?,generatedAt: freezed == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,manifestPaths: null == manifestPaths ? _self._manifestPaths : manifestPaths // ignore: cast_nullable_to_non_nullable
as List<String>,cases: null == cases ? _self._cases : cases // ignore: cast_nullable_to_non_nullable
as List<PersonalEvalReplayCaseResult>,
  ));
}


}

// dart format on
