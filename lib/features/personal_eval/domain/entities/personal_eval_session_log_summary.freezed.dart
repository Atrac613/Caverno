// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'personal_eval_session_log_summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PersonalEvalSessionLogSummary {

 String get result; int get entryCount; int get turnCount; int get malformedLineCount; int get toolCallCount; int get totalDurationMs; Map<String, int> get operationCounts; Map<String, int> get finishReasonCounts; List<String> get warningCodes;@JsonKey(includeIfNull: false) int? get finalAnswerLineNumber;
/// Create a copy of PersonalEvalSessionLogSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersonalEvalSessionLogSummaryCopyWith<PersonalEvalSessionLogSummary> get copyWith => _$PersonalEvalSessionLogSummaryCopyWithImpl<PersonalEvalSessionLogSummary>(this as PersonalEvalSessionLogSummary, _$identity);

  /// Serializes this PersonalEvalSessionLogSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersonalEvalSessionLogSummary&&(identical(other.result, result) || other.result == result)&&(identical(other.entryCount, entryCount) || other.entryCount == entryCount)&&(identical(other.turnCount, turnCount) || other.turnCount == turnCount)&&(identical(other.malformedLineCount, malformedLineCount) || other.malformedLineCount == malformedLineCount)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&(identical(other.totalDurationMs, totalDurationMs) || other.totalDurationMs == totalDurationMs)&&const DeepCollectionEquality().equals(other.operationCounts, operationCounts)&&const DeepCollectionEquality().equals(other.finishReasonCounts, finishReasonCounts)&&const DeepCollectionEquality().equals(other.warningCodes, warningCodes)&&(identical(other.finalAnswerLineNumber, finalAnswerLineNumber) || other.finalAnswerLineNumber == finalAnswerLineNumber));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,result,entryCount,turnCount,malformedLineCount,toolCallCount,totalDurationMs,const DeepCollectionEquality().hash(operationCounts),const DeepCollectionEquality().hash(finishReasonCounts),const DeepCollectionEquality().hash(warningCodes),finalAnswerLineNumber);

@override
String toString() {
  return 'PersonalEvalSessionLogSummary(result: $result, entryCount: $entryCount, turnCount: $turnCount, malformedLineCount: $malformedLineCount, toolCallCount: $toolCallCount, totalDurationMs: $totalDurationMs, operationCounts: $operationCounts, finishReasonCounts: $finishReasonCounts, warningCodes: $warningCodes, finalAnswerLineNumber: $finalAnswerLineNumber)';
}


}

/// @nodoc
abstract mixin class $PersonalEvalSessionLogSummaryCopyWith<$Res>  {
  factory $PersonalEvalSessionLogSummaryCopyWith(PersonalEvalSessionLogSummary value, $Res Function(PersonalEvalSessionLogSummary) _then) = _$PersonalEvalSessionLogSummaryCopyWithImpl;
@useResult
$Res call({
 String result, int entryCount, int turnCount, int malformedLineCount, int toolCallCount, int totalDurationMs, Map<String, int> operationCounts, Map<String, int> finishReasonCounts, List<String> warningCodes,@JsonKey(includeIfNull: false) int? finalAnswerLineNumber
});




}
/// @nodoc
class _$PersonalEvalSessionLogSummaryCopyWithImpl<$Res>
    implements $PersonalEvalSessionLogSummaryCopyWith<$Res> {
  _$PersonalEvalSessionLogSummaryCopyWithImpl(this._self, this._then);

  final PersonalEvalSessionLogSummary _self;
  final $Res Function(PersonalEvalSessionLogSummary) _then;

/// Create a copy of PersonalEvalSessionLogSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? result = null,Object? entryCount = null,Object? turnCount = null,Object? malformedLineCount = null,Object? toolCallCount = null,Object? totalDurationMs = null,Object? operationCounts = null,Object? finishReasonCounts = null,Object? warningCodes = null,Object? finalAnswerLineNumber = freezed,}) {
  return _then(_self.copyWith(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,entryCount: null == entryCount ? _self.entryCount : entryCount // ignore: cast_nullable_to_non_nullable
as int,turnCount: null == turnCount ? _self.turnCount : turnCount // ignore: cast_nullable_to_non_nullable
as int,malformedLineCount: null == malformedLineCount ? _self.malformedLineCount : malformedLineCount // ignore: cast_nullable_to_non_nullable
as int,toolCallCount: null == toolCallCount ? _self.toolCallCount : toolCallCount // ignore: cast_nullable_to_non_nullable
as int,totalDurationMs: null == totalDurationMs ? _self.totalDurationMs : totalDurationMs // ignore: cast_nullable_to_non_nullable
as int,operationCounts: null == operationCounts ? _self.operationCounts : operationCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,finishReasonCounts: null == finishReasonCounts ? _self.finishReasonCounts : finishReasonCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,warningCodes: null == warningCodes ? _self.warningCodes : warningCodes // ignore: cast_nullable_to_non_nullable
as List<String>,finalAnswerLineNumber: freezed == finalAnswerLineNumber ? _self.finalAnswerLineNumber : finalAnswerLineNumber // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PersonalEvalSessionLogSummary].
extension PersonalEvalSessionLogSummaryPatterns on PersonalEvalSessionLogSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersonalEvalSessionLogSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersonalEvalSessionLogSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersonalEvalSessionLogSummary value)  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalSessionLogSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersonalEvalSessionLogSummary value)?  $default,){
final _that = this;
switch (_that) {
case _PersonalEvalSessionLogSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String result,  int entryCount,  int turnCount,  int malformedLineCount,  int toolCallCount,  int totalDurationMs,  Map<String, int> operationCounts,  Map<String, int> finishReasonCounts,  List<String> warningCodes, @JsonKey(includeIfNull: false)  int? finalAnswerLineNumber)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersonalEvalSessionLogSummary() when $default != null:
return $default(_that.result,_that.entryCount,_that.turnCount,_that.malformedLineCount,_that.toolCallCount,_that.totalDurationMs,_that.operationCounts,_that.finishReasonCounts,_that.warningCodes,_that.finalAnswerLineNumber);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String result,  int entryCount,  int turnCount,  int malformedLineCount,  int toolCallCount,  int totalDurationMs,  Map<String, int> operationCounts,  Map<String, int> finishReasonCounts,  List<String> warningCodes, @JsonKey(includeIfNull: false)  int? finalAnswerLineNumber)  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalSessionLogSummary():
return $default(_that.result,_that.entryCount,_that.turnCount,_that.malformedLineCount,_that.toolCallCount,_that.totalDurationMs,_that.operationCounts,_that.finishReasonCounts,_that.warningCodes,_that.finalAnswerLineNumber);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String result,  int entryCount,  int turnCount,  int malformedLineCount,  int toolCallCount,  int totalDurationMs,  Map<String, int> operationCounts,  Map<String, int> finishReasonCounts,  List<String> warningCodes, @JsonKey(includeIfNull: false)  int? finalAnswerLineNumber)?  $default,) {final _that = this;
switch (_that) {
case _PersonalEvalSessionLogSummary() when $default != null:
return $default(_that.result,_that.entryCount,_that.turnCount,_that.malformedLineCount,_that.toolCallCount,_that.totalDurationMs,_that.operationCounts,_that.finishReasonCounts,_that.warningCodes,_that.finalAnswerLineNumber);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PersonalEvalSessionLogSummary extends PersonalEvalSessionLogSummary {
  const _PersonalEvalSessionLogSummary({this.result = 'incomplete', this.entryCount = 0, this.turnCount = 0, this.malformedLineCount = 0, this.toolCallCount = 0, this.totalDurationMs = 0, final  Map<String, int> operationCounts = const <String, int>{}, final  Map<String, int> finishReasonCounts = const <String, int>{}, final  List<String> warningCodes = const <String>[], @JsonKey(includeIfNull: false) this.finalAnswerLineNumber}): _operationCounts = operationCounts,_finishReasonCounts = finishReasonCounts,_warningCodes = warningCodes,super._();
  factory _PersonalEvalSessionLogSummary.fromJson(Map<String, dynamic> json) => _$PersonalEvalSessionLogSummaryFromJson(json);

@override@JsonKey() final  String result;
@override@JsonKey() final  int entryCount;
@override@JsonKey() final  int turnCount;
@override@JsonKey() final  int malformedLineCount;
@override@JsonKey() final  int toolCallCount;
@override@JsonKey() final  int totalDurationMs;
 final  Map<String, int> _operationCounts;
@override@JsonKey() Map<String, int> get operationCounts {
  if (_operationCounts is EqualUnmodifiableMapView) return _operationCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_operationCounts);
}

 final  Map<String, int> _finishReasonCounts;
@override@JsonKey() Map<String, int> get finishReasonCounts {
  if (_finishReasonCounts is EqualUnmodifiableMapView) return _finishReasonCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_finishReasonCounts);
}

 final  List<String> _warningCodes;
@override@JsonKey() List<String> get warningCodes {
  if (_warningCodes is EqualUnmodifiableListView) return _warningCodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warningCodes);
}

@override@JsonKey(includeIfNull: false) final  int? finalAnswerLineNumber;

/// Create a copy of PersonalEvalSessionLogSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersonalEvalSessionLogSummaryCopyWith<_PersonalEvalSessionLogSummary> get copyWith => __$PersonalEvalSessionLogSummaryCopyWithImpl<_PersonalEvalSessionLogSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PersonalEvalSessionLogSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersonalEvalSessionLogSummary&&(identical(other.result, result) || other.result == result)&&(identical(other.entryCount, entryCount) || other.entryCount == entryCount)&&(identical(other.turnCount, turnCount) || other.turnCount == turnCount)&&(identical(other.malformedLineCount, malformedLineCount) || other.malformedLineCount == malformedLineCount)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&(identical(other.totalDurationMs, totalDurationMs) || other.totalDurationMs == totalDurationMs)&&const DeepCollectionEquality().equals(other._operationCounts, _operationCounts)&&const DeepCollectionEquality().equals(other._finishReasonCounts, _finishReasonCounts)&&const DeepCollectionEquality().equals(other._warningCodes, _warningCodes)&&(identical(other.finalAnswerLineNumber, finalAnswerLineNumber) || other.finalAnswerLineNumber == finalAnswerLineNumber));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,result,entryCount,turnCount,malformedLineCount,toolCallCount,totalDurationMs,const DeepCollectionEquality().hash(_operationCounts),const DeepCollectionEquality().hash(_finishReasonCounts),const DeepCollectionEquality().hash(_warningCodes),finalAnswerLineNumber);

@override
String toString() {
  return 'PersonalEvalSessionLogSummary(result: $result, entryCount: $entryCount, turnCount: $turnCount, malformedLineCount: $malformedLineCount, toolCallCount: $toolCallCount, totalDurationMs: $totalDurationMs, operationCounts: $operationCounts, finishReasonCounts: $finishReasonCounts, warningCodes: $warningCodes, finalAnswerLineNumber: $finalAnswerLineNumber)';
}


}

/// @nodoc
abstract mixin class _$PersonalEvalSessionLogSummaryCopyWith<$Res> implements $PersonalEvalSessionLogSummaryCopyWith<$Res> {
  factory _$PersonalEvalSessionLogSummaryCopyWith(_PersonalEvalSessionLogSummary value, $Res Function(_PersonalEvalSessionLogSummary) _then) = __$PersonalEvalSessionLogSummaryCopyWithImpl;
@override @useResult
$Res call({
 String result, int entryCount, int turnCount, int malformedLineCount, int toolCallCount, int totalDurationMs, Map<String, int> operationCounts, Map<String, int> finishReasonCounts, List<String> warningCodes,@JsonKey(includeIfNull: false) int? finalAnswerLineNumber
});




}
/// @nodoc
class __$PersonalEvalSessionLogSummaryCopyWithImpl<$Res>
    implements _$PersonalEvalSessionLogSummaryCopyWith<$Res> {
  __$PersonalEvalSessionLogSummaryCopyWithImpl(this._self, this._then);

  final _PersonalEvalSessionLogSummary _self;
  final $Res Function(_PersonalEvalSessionLogSummary) _then;

/// Create a copy of PersonalEvalSessionLogSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? result = null,Object? entryCount = null,Object? turnCount = null,Object? malformedLineCount = null,Object? toolCallCount = null,Object? totalDurationMs = null,Object? operationCounts = null,Object? finishReasonCounts = null,Object? warningCodes = null,Object? finalAnswerLineNumber = freezed,}) {
  return _then(_PersonalEvalSessionLogSummary(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,entryCount: null == entryCount ? _self.entryCount : entryCount // ignore: cast_nullable_to_non_nullable
as int,turnCount: null == turnCount ? _self.turnCount : turnCount // ignore: cast_nullable_to_non_nullable
as int,malformedLineCount: null == malformedLineCount ? _self.malformedLineCount : malformedLineCount // ignore: cast_nullable_to_non_nullable
as int,toolCallCount: null == toolCallCount ? _self.toolCallCount : toolCallCount // ignore: cast_nullable_to_non_nullable
as int,totalDurationMs: null == totalDurationMs ? _self.totalDurationMs : totalDurationMs // ignore: cast_nullable_to_non_nullable
as int,operationCounts: null == operationCounts ? _self._operationCounts : operationCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,finishReasonCounts: null == finishReasonCounts ? _self._finishReasonCounts : finishReasonCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,warningCodes: null == warningCodes ? _self._warningCodes : warningCodes // ignore: cast_nullable_to_non_nullable
as List<String>,finalAnswerLineNumber: freezed == finalAnswerLineNumber ? _self.finalAnswerLineNumber : finalAnswerLineNumber // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
