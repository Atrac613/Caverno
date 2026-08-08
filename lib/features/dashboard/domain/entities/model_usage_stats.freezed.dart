// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_usage_stats.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelUsageEntry {

 String get key; String get label; String get endpointId; int get requestCount; int get errorCount; int get truncatedCount; int get durationMs; int get promptTokens; int get completionTokens; int get totalTokens; int get cachedPromptTokens; int get audioPromptTokens; int get reasoningTokens; int get audioCompletionTokens; int get acceptedPredictionTokens; int get rejectedPredictionTokens;
/// Create a copy of ModelUsageEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelUsageEntryCopyWith<ModelUsageEntry> get copyWith => _$ModelUsageEntryCopyWithImpl<ModelUsageEntry>(this as ModelUsageEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelUsageEntry&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId)&&(identical(other.requestCount, requestCount) || other.requestCount == requestCount)&&(identical(other.errorCount, errorCount) || other.errorCount == errorCount)&&(identical(other.truncatedCount, truncatedCount) || other.truncatedCount == truncatedCount)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.cachedPromptTokens, cachedPromptTokens) || other.cachedPromptTokens == cachedPromptTokens)&&(identical(other.audioPromptTokens, audioPromptTokens) || other.audioPromptTokens == audioPromptTokens)&&(identical(other.reasoningTokens, reasoningTokens) || other.reasoningTokens == reasoningTokens)&&(identical(other.audioCompletionTokens, audioCompletionTokens) || other.audioCompletionTokens == audioCompletionTokens)&&(identical(other.acceptedPredictionTokens, acceptedPredictionTokens) || other.acceptedPredictionTokens == acceptedPredictionTokens)&&(identical(other.rejectedPredictionTokens, rejectedPredictionTokens) || other.rejectedPredictionTokens == rejectedPredictionTokens));
}


@override
int get hashCode => Object.hash(runtimeType,key,label,endpointId,requestCount,errorCount,truncatedCount,durationMs,promptTokens,completionTokens,totalTokens,cachedPromptTokens,audioPromptTokens,reasoningTokens,audioCompletionTokens,acceptedPredictionTokens,rejectedPredictionTokens);

@override
String toString() {
  return 'ModelUsageEntry(key: $key, label: $label, endpointId: $endpointId, requestCount: $requestCount, errorCount: $errorCount, truncatedCount: $truncatedCount, durationMs: $durationMs, promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, cachedPromptTokens: $cachedPromptTokens, audioPromptTokens: $audioPromptTokens, reasoningTokens: $reasoningTokens, audioCompletionTokens: $audioCompletionTokens, acceptedPredictionTokens: $acceptedPredictionTokens, rejectedPredictionTokens: $rejectedPredictionTokens)';
}


}

/// @nodoc
abstract mixin class $ModelUsageEntryCopyWith<$Res>  {
  factory $ModelUsageEntryCopyWith(ModelUsageEntry value, $Res Function(ModelUsageEntry) _then) = _$ModelUsageEntryCopyWithImpl;
@useResult
$Res call({
 String key, String label, String endpointId, int requestCount, int errorCount, int truncatedCount, int durationMs, int promptTokens, int completionTokens, int totalTokens, int cachedPromptTokens, int audioPromptTokens, int reasoningTokens, int audioCompletionTokens, int acceptedPredictionTokens, int rejectedPredictionTokens
});




}
/// @nodoc
class _$ModelUsageEntryCopyWithImpl<$Res>
    implements $ModelUsageEntryCopyWith<$Res> {
  _$ModelUsageEntryCopyWithImpl(this._self, this._then);

  final ModelUsageEntry _self;
  final $Res Function(ModelUsageEntry) _then;

/// Create a copy of ModelUsageEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? label = null,Object? endpointId = null,Object? requestCount = null,Object? errorCount = null,Object? truncatedCount = null,Object? durationMs = null,Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? cachedPromptTokens = null,Object? audioPromptTokens = null,Object? reasoningTokens = null,Object? audioCompletionTokens = null,Object? acceptedPredictionTokens = null,Object? rejectedPredictionTokens = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,requestCount: null == requestCount ? _self.requestCount : requestCount // ignore: cast_nullable_to_non_nullable
as int,errorCount: null == errorCount ? _self.errorCount : errorCount // ignore: cast_nullable_to_non_nullable
as int,truncatedCount: null == truncatedCount ? _self.truncatedCount : truncatedCount // ignore: cast_nullable_to_non_nullable
as int,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,audioPromptTokens: null == audioPromptTokens ? _self.audioPromptTokens : audioPromptTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningTokens: null == reasoningTokens ? _self.reasoningTokens : reasoningTokens // ignore: cast_nullable_to_non_nullable
as int,audioCompletionTokens: null == audioCompletionTokens ? _self.audioCompletionTokens : audioCompletionTokens // ignore: cast_nullable_to_non_nullable
as int,acceptedPredictionTokens: null == acceptedPredictionTokens ? _self.acceptedPredictionTokens : acceptedPredictionTokens // ignore: cast_nullable_to_non_nullable
as int,rejectedPredictionTokens: null == rejectedPredictionTokens ? _self.rejectedPredictionTokens : rejectedPredictionTokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelUsageEntry].
extension ModelUsageEntryPatterns on ModelUsageEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelUsageEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelUsageEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelUsageEntry value)  $default,){
final _that = this;
switch (_that) {
case _ModelUsageEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelUsageEntry value)?  $default,){
final _that = this;
switch (_that) {
case _ModelUsageEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String label,  String endpointId,  int requestCount,  int errorCount,  int truncatedCount,  int durationMs,  int promptTokens,  int completionTokens,  int totalTokens,  int cachedPromptTokens,  int audioPromptTokens,  int reasoningTokens,  int audioCompletionTokens,  int acceptedPredictionTokens,  int rejectedPredictionTokens)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelUsageEntry() when $default != null:
return $default(_that.key,_that.label,_that.endpointId,_that.requestCount,_that.errorCount,_that.truncatedCount,_that.durationMs,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.cachedPromptTokens,_that.audioPromptTokens,_that.reasoningTokens,_that.audioCompletionTokens,_that.acceptedPredictionTokens,_that.rejectedPredictionTokens);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String label,  String endpointId,  int requestCount,  int errorCount,  int truncatedCount,  int durationMs,  int promptTokens,  int completionTokens,  int totalTokens,  int cachedPromptTokens,  int audioPromptTokens,  int reasoningTokens,  int audioCompletionTokens,  int acceptedPredictionTokens,  int rejectedPredictionTokens)  $default,) {final _that = this;
switch (_that) {
case _ModelUsageEntry():
return $default(_that.key,_that.label,_that.endpointId,_that.requestCount,_that.errorCount,_that.truncatedCount,_that.durationMs,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.cachedPromptTokens,_that.audioPromptTokens,_that.reasoningTokens,_that.audioCompletionTokens,_that.acceptedPredictionTokens,_that.rejectedPredictionTokens);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String label,  String endpointId,  int requestCount,  int errorCount,  int truncatedCount,  int durationMs,  int promptTokens,  int completionTokens,  int totalTokens,  int cachedPromptTokens,  int audioPromptTokens,  int reasoningTokens,  int audioCompletionTokens,  int acceptedPredictionTokens,  int rejectedPredictionTokens)?  $default,) {final _that = this;
switch (_that) {
case _ModelUsageEntry() when $default != null:
return $default(_that.key,_that.label,_that.endpointId,_that.requestCount,_that.errorCount,_that.truncatedCount,_that.durationMs,_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.cachedPromptTokens,_that.audioPromptTokens,_that.reasoningTokens,_that.audioCompletionTokens,_that.acceptedPredictionTokens,_that.rejectedPredictionTokens);case _:
  return null;

}
}

}

/// @nodoc


class _ModelUsageEntry extends ModelUsageEntry {
  const _ModelUsageEntry({required this.key, required this.label, this.endpointId = '', this.requestCount = 0, this.errorCount = 0, this.truncatedCount = 0, this.durationMs = 0, this.promptTokens = 0, this.completionTokens = 0, this.totalTokens = 0, this.cachedPromptTokens = 0, this.audioPromptTokens = 0, this.reasoningTokens = 0, this.audioCompletionTokens = 0, this.acceptedPredictionTokens = 0, this.rejectedPredictionTokens = 0}): super._();
  

@override final  String key;
@override final  String label;
@override@JsonKey() final  String endpointId;
@override@JsonKey() final  int requestCount;
@override@JsonKey() final  int errorCount;
@override@JsonKey() final  int truncatedCount;
@override@JsonKey() final  int durationMs;
@override@JsonKey() final  int promptTokens;
@override@JsonKey() final  int completionTokens;
@override@JsonKey() final  int totalTokens;
@override@JsonKey() final  int cachedPromptTokens;
@override@JsonKey() final  int audioPromptTokens;
@override@JsonKey() final  int reasoningTokens;
@override@JsonKey() final  int audioCompletionTokens;
@override@JsonKey() final  int acceptedPredictionTokens;
@override@JsonKey() final  int rejectedPredictionTokens;

/// Create a copy of ModelUsageEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelUsageEntryCopyWith<_ModelUsageEntry> get copyWith => __$ModelUsageEntryCopyWithImpl<_ModelUsageEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelUsageEntry&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label)&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId)&&(identical(other.requestCount, requestCount) || other.requestCount == requestCount)&&(identical(other.errorCount, errorCount) || other.errorCount == errorCount)&&(identical(other.truncatedCount, truncatedCount) || other.truncatedCount == truncatedCount)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.cachedPromptTokens, cachedPromptTokens) || other.cachedPromptTokens == cachedPromptTokens)&&(identical(other.audioPromptTokens, audioPromptTokens) || other.audioPromptTokens == audioPromptTokens)&&(identical(other.reasoningTokens, reasoningTokens) || other.reasoningTokens == reasoningTokens)&&(identical(other.audioCompletionTokens, audioCompletionTokens) || other.audioCompletionTokens == audioCompletionTokens)&&(identical(other.acceptedPredictionTokens, acceptedPredictionTokens) || other.acceptedPredictionTokens == acceptedPredictionTokens)&&(identical(other.rejectedPredictionTokens, rejectedPredictionTokens) || other.rejectedPredictionTokens == rejectedPredictionTokens));
}


@override
int get hashCode => Object.hash(runtimeType,key,label,endpointId,requestCount,errorCount,truncatedCount,durationMs,promptTokens,completionTokens,totalTokens,cachedPromptTokens,audioPromptTokens,reasoningTokens,audioCompletionTokens,acceptedPredictionTokens,rejectedPredictionTokens);

@override
String toString() {
  return 'ModelUsageEntry(key: $key, label: $label, endpointId: $endpointId, requestCount: $requestCount, errorCount: $errorCount, truncatedCount: $truncatedCount, durationMs: $durationMs, promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, cachedPromptTokens: $cachedPromptTokens, audioPromptTokens: $audioPromptTokens, reasoningTokens: $reasoningTokens, audioCompletionTokens: $audioCompletionTokens, acceptedPredictionTokens: $acceptedPredictionTokens, rejectedPredictionTokens: $rejectedPredictionTokens)';
}


}

/// @nodoc
abstract mixin class _$ModelUsageEntryCopyWith<$Res> implements $ModelUsageEntryCopyWith<$Res> {
  factory _$ModelUsageEntryCopyWith(_ModelUsageEntry value, $Res Function(_ModelUsageEntry) _then) = __$ModelUsageEntryCopyWithImpl;
@override @useResult
$Res call({
 String key, String label, String endpointId, int requestCount, int errorCount, int truncatedCount, int durationMs, int promptTokens, int completionTokens, int totalTokens, int cachedPromptTokens, int audioPromptTokens, int reasoningTokens, int audioCompletionTokens, int acceptedPredictionTokens, int rejectedPredictionTokens
});




}
/// @nodoc
class __$ModelUsageEntryCopyWithImpl<$Res>
    implements _$ModelUsageEntryCopyWith<$Res> {
  __$ModelUsageEntryCopyWithImpl(this._self, this._then);

  final _ModelUsageEntry _self;
  final $Res Function(_ModelUsageEntry) _then;

/// Create a copy of ModelUsageEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? label = null,Object? endpointId = null,Object? requestCount = null,Object? errorCount = null,Object? truncatedCount = null,Object? durationMs = null,Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? cachedPromptTokens = null,Object? audioPromptTokens = null,Object? reasoningTokens = null,Object? audioCompletionTokens = null,Object? acceptedPredictionTokens = null,Object? rejectedPredictionTokens = null,}) {
  return _then(_ModelUsageEntry(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,requestCount: null == requestCount ? _self.requestCount : requestCount // ignore: cast_nullable_to_non_nullable
as int,errorCount: null == errorCount ? _self.errorCount : errorCount // ignore: cast_nullable_to_non_nullable
as int,truncatedCount: null == truncatedCount ? _self.truncatedCount : truncatedCount // ignore: cast_nullable_to_non_nullable
as int,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,audioPromptTokens: null == audioPromptTokens ? _self.audioPromptTokens : audioPromptTokens // ignore: cast_nullable_to_non_nullable
as int,reasoningTokens: null == reasoningTokens ? _self.reasoningTokens : reasoningTokens // ignore: cast_nullable_to_non_nullable
as int,audioCompletionTokens: null == audioCompletionTokens ? _self.audioCompletionTokens : audioCompletionTokens // ignore: cast_nullable_to_non_nullable
as int,acceptedPredictionTokens: null == acceptedPredictionTokens ? _self.acceptedPredictionTokens : acceptedPredictionTokens // ignore: cast_nullable_to_non_nullable
as int,rejectedPredictionTokens: null == rejectedPredictionTokens ? _self.rejectedPredictionTokens : rejectedPredictionTokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ModelUsageDaySlice {

 int get dayNumber; Map<String, int> get tokensByModelKey;
/// Create a copy of ModelUsageDaySlice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelUsageDaySliceCopyWith<ModelUsageDaySlice> get copyWith => _$ModelUsageDaySliceCopyWithImpl<ModelUsageDaySlice>(this as ModelUsageDaySlice, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelUsageDaySlice&&(identical(other.dayNumber, dayNumber) || other.dayNumber == dayNumber)&&const DeepCollectionEquality().equals(other.tokensByModelKey, tokensByModelKey));
}


@override
int get hashCode => Object.hash(runtimeType,dayNumber,const DeepCollectionEquality().hash(tokensByModelKey));

@override
String toString() {
  return 'ModelUsageDaySlice(dayNumber: $dayNumber, tokensByModelKey: $tokensByModelKey)';
}


}

/// @nodoc
abstract mixin class $ModelUsageDaySliceCopyWith<$Res>  {
  factory $ModelUsageDaySliceCopyWith(ModelUsageDaySlice value, $Res Function(ModelUsageDaySlice) _then) = _$ModelUsageDaySliceCopyWithImpl;
@useResult
$Res call({
 int dayNumber, Map<String, int> tokensByModelKey
});




}
/// @nodoc
class _$ModelUsageDaySliceCopyWithImpl<$Res>
    implements $ModelUsageDaySliceCopyWith<$Res> {
  _$ModelUsageDaySliceCopyWithImpl(this._self, this._then);

  final ModelUsageDaySlice _self;
  final $Res Function(ModelUsageDaySlice) _then;

/// Create a copy of ModelUsageDaySlice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? dayNumber = null,Object? tokensByModelKey = null,}) {
  return _then(_self.copyWith(
dayNumber: null == dayNumber ? _self.dayNumber : dayNumber // ignore: cast_nullable_to_non_nullable
as int,tokensByModelKey: null == tokensByModelKey ? _self.tokensByModelKey : tokensByModelKey // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelUsageDaySlice].
extension ModelUsageDaySlicePatterns on ModelUsageDaySlice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelUsageDaySlice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelUsageDaySlice() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelUsageDaySlice value)  $default,){
final _that = this;
switch (_that) {
case _ModelUsageDaySlice():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelUsageDaySlice value)?  $default,){
final _that = this;
switch (_that) {
case _ModelUsageDaySlice() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int dayNumber,  Map<String, int> tokensByModelKey)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelUsageDaySlice() when $default != null:
return $default(_that.dayNumber,_that.tokensByModelKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int dayNumber,  Map<String, int> tokensByModelKey)  $default,) {final _that = this;
switch (_that) {
case _ModelUsageDaySlice():
return $default(_that.dayNumber,_that.tokensByModelKey);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int dayNumber,  Map<String, int> tokensByModelKey)?  $default,) {final _that = this;
switch (_that) {
case _ModelUsageDaySlice() when $default != null:
return $default(_that.dayNumber,_that.tokensByModelKey);case _:
  return null;

}
}

}

/// @nodoc


class _ModelUsageDaySlice extends ModelUsageDaySlice {
  const _ModelUsageDaySlice({required this.dayNumber, final  Map<String, int> tokensByModelKey = const <String, int>{}}): _tokensByModelKey = tokensByModelKey,super._();
  

@override final  int dayNumber;
 final  Map<String, int> _tokensByModelKey;
@override@JsonKey() Map<String, int> get tokensByModelKey {
  if (_tokensByModelKey is EqualUnmodifiableMapView) return _tokensByModelKey;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_tokensByModelKey);
}


/// Create a copy of ModelUsageDaySlice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelUsageDaySliceCopyWith<_ModelUsageDaySlice> get copyWith => __$ModelUsageDaySliceCopyWithImpl<_ModelUsageDaySlice>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelUsageDaySlice&&(identical(other.dayNumber, dayNumber) || other.dayNumber == dayNumber)&&const DeepCollectionEquality().equals(other._tokensByModelKey, _tokensByModelKey));
}


@override
int get hashCode => Object.hash(runtimeType,dayNumber,const DeepCollectionEquality().hash(_tokensByModelKey));

@override
String toString() {
  return 'ModelUsageDaySlice(dayNumber: $dayNumber, tokensByModelKey: $tokensByModelKey)';
}


}

/// @nodoc
abstract mixin class _$ModelUsageDaySliceCopyWith<$Res> implements $ModelUsageDaySliceCopyWith<$Res> {
  factory _$ModelUsageDaySliceCopyWith(_ModelUsageDaySlice value, $Res Function(_ModelUsageDaySlice) _then) = __$ModelUsageDaySliceCopyWithImpl;
@override @useResult
$Res call({
 int dayNumber, Map<String, int> tokensByModelKey
});




}
/// @nodoc
class __$ModelUsageDaySliceCopyWithImpl<$Res>
    implements _$ModelUsageDaySliceCopyWith<$Res> {
  __$ModelUsageDaySliceCopyWithImpl(this._self, this._then);

  final _ModelUsageDaySlice _self;
  final $Res Function(_ModelUsageDaySlice) _then;

/// Create a copy of ModelUsageDaySlice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? dayNumber = null,Object? tokensByModelKey = null,}) {
  return _then(_ModelUsageDaySlice(
dayNumber: null == dayNumber ? _self.dayNumber : dayNumber // ignore: cast_nullable_to_non_nullable
as int,tokensByModelKey: null == tokensByModelKey ? _self._tokensByModelKey : tokensByModelKey // ignore: cast_nullable_to_non_nullable
as Map<String, int>,
  ));
}


}

/// @nodoc
mixin _$ModelUsageStats {

 List<ModelUsageEntry> get models; List<ModelUsageEntry> get roles; List<ModelUsageDaySlice> get daily; Map<String, List<ModelUsageEntry>> get labelsByModelKey;
/// Create a copy of ModelUsageStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelUsageStatsCopyWith<ModelUsageStats> get copyWith => _$ModelUsageStatsCopyWithImpl<ModelUsageStats>(this as ModelUsageStats, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelUsageStats&&const DeepCollectionEquality().equals(other.models, models)&&const DeepCollectionEquality().equals(other.roles, roles)&&const DeepCollectionEquality().equals(other.daily, daily)&&const DeepCollectionEquality().equals(other.labelsByModelKey, labelsByModelKey));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(models),const DeepCollectionEquality().hash(roles),const DeepCollectionEquality().hash(daily),const DeepCollectionEquality().hash(labelsByModelKey));

@override
String toString() {
  return 'ModelUsageStats(models: $models, roles: $roles, daily: $daily, labelsByModelKey: $labelsByModelKey)';
}


}

/// @nodoc
abstract mixin class $ModelUsageStatsCopyWith<$Res>  {
  factory $ModelUsageStatsCopyWith(ModelUsageStats value, $Res Function(ModelUsageStats) _then) = _$ModelUsageStatsCopyWithImpl;
@useResult
$Res call({
 List<ModelUsageEntry> models, List<ModelUsageEntry> roles, List<ModelUsageDaySlice> daily, Map<String, List<ModelUsageEntry>> labelsByModelKey
});




}
/// @nodoc
class _$ModelUsageStatsCopyWithImpl<$Res>
    implements $ModelUsageStatsCopyWith<$Res> {
  _$ModelUsageStatsCopyWithImpl(this._self, this._then);

  final ModelUsageStats _self;
  final $Res Function(ModelUsageStats) _then;

/// Create a copy of ModelUsageStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? models = null,Object? roles = null,Object? daily = null,Object? labelsByModelKey = null,}) {
  return _then(_self.copyWith(
models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as List<ModelUsageEntry>,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as List<ModelUsageEntry>,daily: null == daily ? _self.daily : daily // ignore: cast_nullable_to_non_nullable
as List<ModelUsageDaySlice>,labelsByModelKey: null == labelsByModelKey ? _self.labelsByModelKey : labelsByModelKey // ignore: cast_nullable_to_non_nullable
as Map<String, List<ModelUsageEntry>>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelUsageStats].
extension ModelUsageStatsPatterns on ModelUsageStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelUsageStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelUsageStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelUsageStats value)  $default,){
final _that = this;
switch (_that) {
case _ModelUsageStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelUsageStats value)?  $default,){
final _that = this;
switch (_that) {
case _ModelUsageStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ModelUsageEntry> models,  List<ModelUsageEntry> roles,  List<ModelUsageDaySlice> daily,  Map<String, List<ModelUsageEntry>> labelsByModelKey)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelUsageStats() when $default != null:
return $default(_that.models,_that.roles,_that.daily,_that.labelsByModelKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ModelUsageEntry> models,  List<ModelUsageEntry> roles,  List<ModelUsageDaySlice> daily,  Map<String, List<ModelUsageEntry>> labelsByModelKey)  $default,) {final _that = this;
switch (_that) {
case _ModelUsageStats():
return $default(_that.models,_that.roles,_that.daily,_that.labelsByModelKey);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ModelUsageEntry> models,  List<ModelUsageEntry> roles,  List<ModelUsageDaySlice> daily,  Map<String, List<ModelUsageEntry>> labelsByModelKey)?  $default,) {final _that = this;
switch (_that) {
case _ModelUsageStats() when $default != null:
return $default(_that.models,_that.roles,_that.daily,_that.labelsByModelKey);case _:
  return null;

}
}

}

/// @nodoc


class _ModelUsageStats extends ModelUsageStats {
  const _ModelUsageStats({final  List<ModelUsageEntry> models = const <ModelUsageEntry>[], final  List<ModelUsageEntry> roles = const <ModelUsageEntry>[], final  List<ModelUsageDaySlice> daily = const <ModelUsageDaySlice>[], final  Map<String, List<ModelUsageEntry>> labelsByModelKey = const <String, List<ModelUsageEntry>>{}}): _models = models,_roles = roles,_daily = daily,_labelsByModelKey = labelsByModelKey,super._();
  

 final  List<ModelUsageEntry> _models;
@override@JsonKey() List<ModelUsageEntry> get models {
  if (_models is EqualUnmodifiableListView) return _models;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_models);
}

 final  List<ModelUsageEntry> _roles;
@override@JsonKey() List<ModelUsageEntry> get roles {
  if (_roles is EqualUnmodifiableListView) return _roles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roles);
}

 final  List<ModelUsageDaySlice> _daily;
@override@JsonKey() List<ModelUsageDaySlice> get daily {
  if (_daily is EqualUnmodifiableListView) return _daily;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_daily);
}

 final  Map<String, List<ModelUsageEntry>> _labelsByModelKey;
@override@JsonKey() Map<String, List<ModelUsageEntry>> get labelsByModelKey {
  if (_labelsByModelKey is EqualUnmodifiableMapView) return _labelsByModelKey;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_labelsByModelKey);
}


/// Create a copy of ModelUsageStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelUsageStatsCopyWith<_ModelUsageStats> get copyWith => __$ModelUsageStatsCopyWithImpl<_ModelUsageStats>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelUsageStats&&const DeepCollectionEquality().equals(other._models, _models)&&const DeepCollectionEquality().equals(other._roles, _roles)&&const DeepCollectionEquality().equals(other._daily, _daily)&&const DeepCollectionEquality().equals(other._labelsByModelKey, _labelsByModelKey));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_models),const DeepCollectionEquality().hash(_roles),const DeepCollectionEquality().hash(_daily),const DeepCollectionEquality().hash(_labelsByModelKey));

@override
String toString() {
  return 'ModelUsageStats(models: $models, roles: $roles, daily: $daily, labelsByModelKey: $labelsByModelKey)';
}


}

/// @nodoc
abstract mixin class _$ModelUsageStatsCopyWith<$Res> implements $ModelUsageStatsCopyWith<$Res> {
  factory _$ModelUsageStatsCopyWith(_ModelUsageStats value, $Res Function(_ModelUsageStats) _then) = __$ModelUsageStatsCopyWithImpl;
@override @useResult
$Res call({
 List<ModelUsageEntry> models, List<ModelUsageEntry> roles, List<ModelUsageDaySlice> daily, Map<String, List<ModelUsageEntry>> labelsByModelKey
});




}
/// @nodoc
class __$ModelUsageStatsCopyWithImpl<$Res>
    implements _$ModelUsageStatsCopyWith<$Res> {
  __$ModelUsageStatsCopyWithImpl(this._self, this._then);

  final _ModelUsageStats _self;
  final $Res Function(_ModelUsageStats) _then;

/// Create a copy of ModelUsageStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? models = null,Object? roles = null,Object? daily = null,Object? labelsByModelKey = null,}) {
  return _then(_ModelUsageStats(
models: null == models ? _self._models : models // ignore: cast_nullable_to_non_nullable
as List<ModelUsageEntry>,roles: null == roles ? _self._roles : roles // ignore: cast_nullable_to_non_nullable
as List<ModelUsageEntry>,daily: null == daily ? _self._daily : daily // ignore: cast_nullable_to_non_nullable
as List<ModelUsageDaySlice>,labelsByModelKey: null == labelsByModelKey ? _self._labelsByModelKey : labelsByModelKey // ignore: cast_nullable_to_non_nullable
as Map<String, List<ModelUsageEntry>>,
  ));
}


}

// dart format on
