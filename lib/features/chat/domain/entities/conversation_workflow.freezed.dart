// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_workflow.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationWorkflowSpec {

 String get goal; List<String> get constraints; List<String> get acceptanceCriteria; List<String> get openQuestions;
/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationWorkflowSpecCopyWith<ConversationWorkflowSpec> get copyWith => _$ConversationWorkflowSpecCopyWithImpl<ConversationWorkflowSpec>(this as ConversationWorkflowSpec, _$identity);

  /// Serializes this ConversationWorkflowSpec to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationWorkflowSpec&&(identical(other.goal, goal) || other.goal == goal)&&const DeepCollectionEquality().equals(other.constraints, constraints)&&const DeepCollectionEquality().equals(other.acceptanceCriteria, acceptanceCriteria)&&const DeepCollectionEquality().equals(other.openQuestions, openQuestions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goal,const DeepCollectionEquality().hash(constraints),const DeepCollectionEquality().hash(acceptanceCriteria),const DeepCollectionEquality().hash(openQuestions));

@override
String toString() {
  return 'ConversationWorkflowSpec(goal: $goal, constraints: $constraints, acceptanceCriteria: $acceptanceCriteria, openQuestions: $openQuestions)';
}


}

/// @nodoc
abstract mixin class $ConversationWorkflowSpecCopyWith<$Res>  {
  factory $ConversationWorkflowSpecCopyWith(ConversationWorkflowSpec value, $Res Function(ConversationWorkflowSpec) _then) = _$ConversationWorkflowSpecCopyWithImpl;
@useResult
$Res call({
 String goal, List<String> constraints, List<String> acceptanceCriteria, List<String> openQuestions
});




}
/// @nodoc
class _$ConversationWorkflowSpecCopyWithImpl<$Res>
    implements $ConversationWorkflowSpecCopyWith<$Res> {
  _$ConversationWorkflowSpecCopyWithImpl(this._self, this._then);

  final ConversationWorkflowSpec _self;
  final $Res Function(ConversationWorkflowSpec) _then;

/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? goal = null,Object? constraints = null,Object? acceptanceCriteria = null,Object? openQuestions = null,}) {
  return _then(_self.copyWith(
goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,constraints: null == constraints ? _self.constraints : constraints // ignore: cast_nullable_to_non_nullable
as List<String>,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,openQuestions: null == openQuestions ? _self.openQuestions : openQuestions // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationWorkflowSpec].
extension ConversationWorkflowSpecPatterns on ConversationWorkflowSpec {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationWorkflowSpec value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationWorkflowSpec value)  $default,){
final _that = this;
switch (_that) {
case _ConversationWorkflowSpec():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationWorkflowSpec value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions)  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec():
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String goal,  List<String> constraints,  List<String> acceptanceCriteria,  List<String> openQuestions)?  $default,) {final _that = this;
switch (_that) {
case _ConversationWorkflowSpec() when $default != null:
return $default(_that.goal,_that.constraints,_that.acceptanceCriteria,_that.openQuestions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationWorkflowSpec extends ConversationWorkflowSpec {
  const _ConversationWorkflowSpec({this.goal = '', final  List<String> constraints = const <String>[], final  List<String> acceptanceCriteria = const <String>[], final  List<String> openQuestions = const <String>[]}): _constraints = constraints,_acceptanceCriteria = acceptanceCriteria,_openQuestions = openQuestions,super._();
  factory _ConversationWorkflowSpec.fromJson(Map<String, dynamic> json) => _$ConversationWorkflowSpecFromJson(json);

@override@JsonKey() final  String goal;
 final  List<String> _constraints;
@override@JsonKey() List<String> get constraints {
  if (_constraints is EqualUnmodifiableListView) return _constraints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_constraints);
}

 final  List<String> _acceptanceCriteria;
@override@JsonKey() List<String> get acceptanceCriteria {
  if (_acceptanceCriteria is EqualUnmodifiableListView) return _acceptanceCriteria;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_acceptanceCriteria);
}

 final  List<String> _openQuestions;
@override@JsonKey() List<String> get openQuestions {
  if (_openQuestions is EqualUnmodifiableListView) return _openQuestions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_openQuestions);
}


/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationWorkflowSpecCopyWith<_ConversationWorkflowSpec> get copyWith => __$ConversationWorkflowSpecCopyWithImpl<_ConversationWorkflowSpec>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationWorkflowSpecToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationWorkflowSpec&&(identical(other.goal, goal) || other.goal == goal)&&const DeepCollectionEquality().equals(other._constraints, _constraints)&&const DeepCollectionEquality().equals(other._acceptanceCriteria, _acceptanceCriteria)&&const DeepCollectionEquality().equals(other._openQuestions, _openQuestions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goal,const DeepCollectionEquality().hash(_constraints),const DeepCollectionEquality().hash(_acceptanceCriteria),const DeepCollectionEquality().hash(_openQuestions));

@override
String toString() {
  return 'ConversationWorkflowSpec(goal: $goal, constraints: $constraints, acceptanceCriteria: $acceptanceCriteria, openQuestions: $openQuestions)';
}


}

/// @nodoc
abstract mixin class _$ConversationWorkflowSpecCopyWith<$Res> implements $ConversationWorkflowSpecCopyWith<$Res> {
  factory _$ConversationWorkflowSpecCopyWith(_ConversationWorkflowSpec value, $Res Function(_ConversationWorkflowSpec) _then) = __$ConversationWorkflowSpecCopyWithImpl;
@override @useResult
$Res call({
 String goal, List<String> constraints, List<String> acceptanceCriteria, List<String> openQuestions
});




}
/// @nodoc
class __$ConversationWorkflowSpecCopyWithImpl<$Res>
    implements _$ConversationWorkflowSpecCopyWith<$Res> {
  __$ConversationWorkflowSpecCopyWithImpl(this._self, this._then);

  final _ConversationWorkflowSpec _self;
  final $Res Function(_ConversationWorkflowSpec) _then;

/// Create a copy of ConversationWorkflowSpec
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? goal = null,Object? constraints = null,Object? acceptanceCriteria = null,Object? openQuestions = null,}) {
  return _then(_ConversationWorkflowSpec(
goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,constraints: null == constraints ? _self._constraints : constraints // ignore: cast_nullable_to_non_nullable
as List<String>,acceptanceCriteria: null == acceptanceCriteria ? _self._acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,openQuestions: null == openQuestions ? _self._openQuestions : openQuestions // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
