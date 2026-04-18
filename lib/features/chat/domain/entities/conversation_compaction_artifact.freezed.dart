// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_compaction_artifact.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationCompactionArtifact {

 String get summary; int get compactedMessageCount; int get retainedMessageCount; int get estimatedPromptTokens; DateTime? get updatedAt;
/// Create a copy of ConversationCompactionArtifact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCompactionArtifactCopyWith<ConversationCompactionArtifact> get copyWith => _$ConversationCompactionArtifactCopyWithImpl<ConversationCompactionArtifact>(this as ConversationCompactionArtifact, _$identity);

  /// Serializes this ConversationCompactionArtifact to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationCompactionArtifact&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.compactedMessageCount, compactedMessageCount) || other.compactedMessageCount == compactedMessageCount)&&(identical(other.retainedMessageCount, retainedMessageCount) || other.retainedMessageCount == retainedMessageCount)&&(identical(other.estimatedPromptTokens, estimatedPromptTokens) || other.estimatedPromptTokens == estimatedPromptTokens)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,summary,compactedMessageCount,retainedMessageCount,estimatedPromptTokens,updatedAt);

@override
String toString() {
  return 'ConversationCompactionArtifact(summary: $summary, compactedMessageCount: $compactedMessageCount, retainedMessageCount: $retainedMessageCount, estimatedPromptTokens: $estimatedPromptTokens, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ConversationCompactionArtifactCopyWith<$Res>  {
  factory $ConversationCompactionArtifactCopyWith(ConversationCompactionArtifact value, $Res Function(ConversationCompactionArtifact) _then) = _$ConversationCompactionArtifactCopyWithImpl;
@useResult
$Res call({
 String summary, int compactedMessageCount, int retainedMessageCount, int estimatedPromptTokens, DateTime? updatedAt
});




}
/// @nodoc
class _$ConversationCompactionArtifactCopyWithImpl<$Res>
    implements $ConversationCompactionArtifactCopyWith<$Res> {
  _$ConversationCompactionArtifactCopyWithImpl(this._self, this._then);

  final ConversationCompactionArtifact _self;
  final $Res Function(ConversationCompactionArtifact) _then;

/// Create a copy of ConversationCompactionArtifact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = null,Object? compactedMessageCount = null,Object? retainedMessageCount = null,Object? estimatedPromptTokens = null,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,compactedMessageCount: null == compactedMessageCount ? _self.compactedMessageCount : compactedMessageCount // ignore: cast_nullable_to_non_nullable
as int,retainedMessageCount: null == retainedMessageCount ? _self.retainedMessageCount : retainedMessageCount // ignore: cast_nullable_to_non_nullable
as int,estimatedPromptTokens: null == estimatedPromptTokens ? _self.estimatedPromptTokens : estimatedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationCompactionArtifact].
extension ConversationCompactionArtifactPatterns on ConversationCompactionArtifact {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationCompactionArtifact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationCompactionArtifact() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationCompactionArtifact value)  $default,){
final _that = this;
switch (_that) {
case _ConversationCompactionArtifact():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationCompactionArtifact value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationCompactionArtifact() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String summary,  int compactedMessageCount,  int retainedMessageCount,  int estimatedPromptTokens,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationCompactionArtifact() when $default != null:
return $default(_that.summary,_that.compactedMessageCount,_that.retainedMessageCount,_that.estimatedPromptTokens,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String summary,  int compactedMessageCount,  int retainedMessageCount,  int estimatedPromptTokens,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ConversationCompactionArtifact():
return $default(_that.summary,_that.compactedMessageCount,_that.retainedMessageCount,_that.estimatedPromptTokens,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String summary,  int compactedMessageCount,  int retainedMessageCount,  int estimatedPromptTokens,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ConversationCompactionArtifact() when $default != null:
return $default(_that.summary,_that.compactedMessageCount,_that.retainedMessageCount,_that.estimatedPromptTokens,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationCompactionArtifact extends ConversationCompactionArtifact {
  const _ConversationCompactionArtifact({this.summary = '', this.compactedMessageCount = 0, this.retainedMessageCount = 0, this.estimatedPromptTokens = 0, this.updatedAt}): super._();
  factory _ConversationCompactionArtifact.fromJson(Map<String, dynamic> json) => _$ConversationCompactionArtifactFromJson(json);

@override@JsonKey() final  String summary;
@override@JsonKey() final  int compactedMessageCount;
@override@JsonKey() final  int retainedMessageCount;
@override@JsonKey() final  int estimatedPromptTokens;
@override final  DateTime? updatedAt;

/// Create a copy of ConversationCompactionArtifact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationCompactionArtifactCopyWith<_ConversationCompactionArtifact> get copyWith => __$ConversationCompactionArtifactCopyWithImpl<_ConversationCompactionArtifact>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationCompactionArtifactToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationCompactionArtifact&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.compactedMessageCount, compactedMessageCount) || other.compactedMessageCount == compactedMessageCount)&&(identical(other.retainedMessageCount, retainedMessageCount) || other.retainedMessageCount == retainedMessageCount)&&(identical(other.estimatedPromptTokens, estimatedPromptTokens) || other.estimatedPromptTokens == estimatedPromptTokens)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,summary,compactedMessageCount,retainedMessageCount,estimatedPromptTokens,updatedAt);

@override
String toString() {
  return 'ConversationCompactionArtifact(summary: $summary, compactedMessageCount: $compactedMessageCount, retainedMessageCount: $retainedMessageCount, estimatedPromptTokens: $estimatedPromptTokens, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ConversationCompactionArtifactCopyWith<$Res> implements $ConversationCompactionArtifactCopyWith<$Res> {
  factory _$ConversationCompactionArtifactCopyWith(_ConversationCompactionArtifact value, $Res Function(_ConversationCompactionArtifact) _then) = __$ConversationCompactionArtifactCopyWithImpl;
@override @useResult
$Res call({
 String summary, int compactedMessageCount, int retainedMessageCount, int estimatedPromptTokens, DateTime? updatedAt
});




}
/// @nodoc
class __$ConversationCompactionArtifactCopyWithImpl<$Res>
    implements _$ConversationCompactionArtifactCopyWith<$Res> {
  __$ConversationCompactionArtifactCopyWithImpl(this._self, this._then);

  final _ConversationCompactionArtifact _self;
  final $Res Function(_ConversationCompactionArtifact) _then;

/// Create a copy of ConversationCompactionArtifact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? summary = null,Object? compactedMessageCount = null,Object? retainedMessageCount = null,Object? estimatedPromptTokens = null,Object? updatedAt = freezed,}) {
  return _then(_ConversationCompactionArtifact(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,compactedMessageCount: null == compactedMessageCount ? _self.compactedMessageCount : compactedMessageCount // ignore: cast_nullable_to_non_nullable
as int,retainedMessageCount: null == retainedMessageCount ? _self.retainedMessageCount : retainedMessageCount // ignore: cast_nullable_to_non_nullable
as int,estimatedPromptTokens: null == estimatedPromptTokens ? _self.estimatedPromptTokens : estimatedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
