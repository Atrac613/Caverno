// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_plan_artifact.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationPlanArtifact {

 String get draftMarkdown; String get approvedMarkdown; DateTime? get updatedAt;
/// Create a copy of ConversationPlanArtifact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationPlanArtifactCopyWith<ConversationPlanArtifact> get copyWith => _$ConversationPlanArtifactCopyWithImpl<ConversationPlanArtifact>(this as ConversationPlanArtifact, _$identity);

  /// Serializes this ConversationPlanArtifact to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationPlanArtifact&&(identical(other.draftMarkdown, draftMarkdown) || other.draftMarkdown == draftMarkdown)&&(identical(other.approvedMarkdown, approvedMarkdown) || other.approvedMarkdown == approvedMarkdown)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,draftMarkdown,approvedMarkdown,updatedAt);

@override
String toString() {
  return 'ConversationPlanArtifact(draftMarkdown: $draftMarkdown, approvedMarkdown: $approvedMarkdown, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ConversationPlanArtifactCopyWith<$Res>  {
  factory $ConversationPlanArtifactCopyWith(ConversationPlanArtifact value, $Res Function(ConversationPlanArtifact) _then) = _$ConversationPlanArtifactCopyWithImpl;
@useResult
$Res call({
 String draftMarkdown, String approvedMarkdown, DateTime? updatedAt
});




}
/// @nodoc
class _$ConversationPlanArtifactCopyWithImpl<$Res>
    implements $ConversationPlanArtifactCopyWith<$Res> {
  _$ConversationPlanArtifactCopyWithImpl(this._self, this._then);

  final ConversationPlanArtifact _self;
  final $Res Function(ConversationPlanArtifact) _then;

/// Create a copy of ConversationPlanArtifact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draftMarkdown = null,Object? approvedMarkdown = null,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
draftMarkdown: null == draftMarkdown ? _self.draftMarkdown : draftMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedMarkdown: null == approvedMarkdown ? _self.approvedMarkdown : approvedMarkdown // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationPlanArtifact].
extension ConversationPlanArtifactPatterns on ConversationPlanArtifact {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationPlanArtifact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationPlanArtifact() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationPlanArtifact value)  $default,){
final _that = this;
switch (_that) {
case _ConversationPlanArtifact():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationPlanArtifact value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationPlanArtifact() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String draftMarkdown,  String approvedMarkdown,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationPlanArtifact() when $default != null:
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String draftMarkdown,  String approvedMarkdown,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ConversationPlanArtifact():
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String draftMarkdown,  String approvedMarkdown,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ConversationPlanArtifact() when $default != null:
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationPlanArtifact extends ConversationPlanArtifact {
  const _ConversationPlanArtifact({this.draftMarkdown = '', this.approvedMarkdown = '', this.updatedAt}): super._();
  factory _ConversationPlanArtifact.fromJson(Map<String, dynamic> json) => _$ConversationPlanArtifactFromJson(json);

@override@JsonKey() final  String draftMarkdown;
@override@JsonKey() final  String approvedMarkdown;
@override final  DateTime? updatedAt;

/// Create a copy of ConversationPlanArtifact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationPlanArtifactCopyWith<_ConversationPlanArtifact> get copyWith => __$ConversationPlanArtifactCopyWithImpl<_ConversationPlanArtifact>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationPlanArtifactToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationPlanArtifact&&(identical(other.draftMarkdown, draftMarkdown) || other.draftMarkdown == draftMarkdown)&&(identical(other.approvedMarkdown, approvedMarkdown) || other.approvedMarkdown == approvedMarkdown)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,draftMarkdown,approvedMarkdown,updatedAt);

@override
String toString() {
  return 'ConversationPlanArtifact(draftMarkdown: $draftMarkdown, approvedMarkdown: $approvedMarkdown, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ConversationPlanArtifactCopyWith<$Res> implements $ConversationPlanArtifactCopyWith<$Res> {
  factory _$ConversationPlanArtifactCopyWith(_ConversationPlanArtifact value, $Res Function(_ConversationPlanArtifact) _then) = __$ConversationPlanArtifactCopyWithImpl;
@override @useResult
$Res call({
 String draftMarkdown, String approvedMarkdown, DateTime? updatedAt
});




}
/// @nodoc
class __$ConversationPlanArtifactCopyWithImpl<$Res>
    implements _$ConversationPlanArtifactCopyWith<$Res> {
  __$ConversationPlanArtifactCopyWithImpl(this._self, this._then);

  final _ConversationPlanArtifact _self;
  final $Res Function(_ConversationPlanArtifact) _then;

/// Create a copy of ConversationPlanArtifact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draftMarkdown = null,Object? approvedMarkdown = null,Object? updatedAt = freezed,}) {
  return _then(_ConversationPlanArtifact(
draftMarkdown: null == draftMarkdown ? _self.draftMarkdown : draftMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedMarkdown: null == approvedMarkdown ? _self.approvedMarkdown : approvedMarkdown // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
