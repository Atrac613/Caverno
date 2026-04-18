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
mixin _$ConversationPlanRevision {

 String get markdown; DateTime get createdAt; ConversationPlanRevisionKind get kind; String get label;
/// Create a copy of ConversationPlanRevision
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationPlanRevisionCopyWith<ConversationPlanRevision> get copyWith => _$ConversationPlanRevisionCopyWithImpl<ConversationPlanRevision>(this as ConversationPlanRevision, _$identity);

  /// Serializes this ConversationPlanRevision to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationPlanRevision&&(identical(other.markdown, markdown) || other.markdown == markdown)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,markdown,createdAt,kind,label);

@override
String toString() {
  return 'ConversationPlanRevision(markdown: $markdown, createdAt: $createdAt, kind: $kind, label: $label)';
}


}

/// @nodoc
abstract mixin class $ConversationPlanRevisionCopyWith<$Res>  {
  factory $ConversationPlanRevisionCopyWith(ConversationPlanRevision value, $Res Function(ConversationPlanRevision) _then) = _$ConversationPlanRevisionCopyWithImpl;
@useResult
$Res call({
 String markdown, DateTime createdAt, ConversationPlanRevisionKind kind, String label
});




}
/// @nodoc
class _$ConversationPlanRevisionCopyWithImpl<$Res>
    implements $ConversationPlanRevisionCopyWith<$Res> {
  _$ConversationPlanRevisionCopyWithImpl(this._self, this._then);

  final ConversationPlanRevision _self;
  final $Res Function(ConversationPlanRevision) _then;

/// Create a copy of ConversationPlanRevision
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? markdown = null,Object? createdAt = null,Object? kind = null,Object? label = null,}) {
  return _then(_self.copyWith(
markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ConversationPlanRevisionKind,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationPlanRevision].
extension ConversationPlanRevisionPatterns on ConversationPlanRevision {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationPlanRevision value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationPlanRevision() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationPlanRevision value)  $default,){
final _that = this;
switch (_that) {
case _ConversationPlanRevision():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationPlanRevision value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationPlanRevision() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String markdown,  DateTime createdAt,  ConversationPlanRevisionKind kind,  String label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationPlanRevision() when $default != null:
return $default(_that.markdown,_that.createdAt,_that.kind,_that.label);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String markdown,  DateTime createdAt,  ConversationPlanRevisionKind kind,  String label)  $default,) {final _that = this;
switch (_that) {
case _ConversationPlanRevision():
return $default(_that.markdown,_that.createdAt,_that.kind,_that.label);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String markdown,  DateTime createdAt,  ConversationPlanRevisionKind kind,  String label)?  $default,) {final _that = this;
switch (_that) {
case _ConversationPlanRevision() when $default != null:
return $default(_that.markdown,_that.createdAt,_that.kind,_that.label);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationPlanRevision extends ConversationPlanRevision {
  const _ConversationPlanRevision({required this.markdown, required this.createdAt, this.kind = ConversationPlanRevisionKind.draft, this.label = ''}): super._();
  factory _ConversationPlanRevision.fromJson(Map<String, dynamic> json) => _$ConversationPlanRevisionFromJson(json);

@override final  String markdown;
@override final  DateTime createdAt;
@override@JsonKey() final  ConversationPlanRevisionKind kind;
@override@JsonKey() final  String label;

/// Create a copy of ConversationPlanRevision
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationPlanRevisionCopyWith<_ConversationPlanRevision> get copyWith => __$ConversationPlanRevisionCopyWithImpl<_ConversationPlanRevision>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationPlanRevisionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationPlanRevision&&(identical(other.markdown, markdown) || other.markdown == markdown)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,markdown,createdAt,kind,label);

@override
String toString() {
  return 'ConversationPlanRevision(markdown: $markdown, createdAt: $createdAt, kind: $kind, label: $label)';
}


}

/// @nodoc
abstract mixin class _$ConversationPlanRevisionCopyWith<$Res> implements $ConversationPlanRevisionCopyWith<$Res> {
  factory _$ConversationPlanRevisionCopyWith(_ConversationPlanRevision value, $Res Function(_ConversationPlanRevision) _then) = __$ConversationPlanRevisionCopyWithImpl;
@override @useResult
$Res call({
 String markdown, DateTime createdAt, ConversationPlanRevisionKind kind, String label
});




}
/// @nodoc
class __$ConversationPlanRevisionCopyWithImpl<$Res>
    implements _$ConversationPlanRevisionCopyWith<$Res> {
  __$ConversationPlanRevisionCopyWithImpl(this._self, this._then);

  final _ConversationPlanRevision _self;
  final $Res Function(_ConversationPlanRevision) _then;

/// Create a copy of ConversationPlanRevision
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? markdown = null,Object? createdAt = null,Object? kind = null,Object? label = null,}) {
  return _then(_ConversationPlanRevision(
markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ConversationPlanRevisionKind,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConversationPlanArtifact {

 String get draftMarkdown; String get approvedMarkdown; DateTime? get updatedAt; List<ConversationPlanRevision> get revisions;
/// Create a copy of ConversationPlanArtifact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationPlanArtifactCopyWith<ConversationPlanArtifact> get copyWith => _$ConversationPlanArtifactCopyWithImpl<ConversationPlanArtifact>(this as ConversationPlanArtifact, _$identity);

  /// Serializes this ConversationPlanArtifact to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationPlanArtifact&&(identical(other.draftMarkdown, draftMarkdown) || other.draftMarkdown == draftMarkdown)&&(identical(other.approvedMarkdown, approvedMarkdown) || other.approvedMarkdown == approvedMarkdown)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.revisions, revisions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,draftMarkdown,approvedMarkdown,updatedAt,const DeepCollectionEquality().hash(revisions));

@override
String toString() {
  return 'ConversationPlanArtifact(draftMarkdown: $draftMarkdown, approvedMarkdown: $approvedMarkdown, updatedAt: $updatedAt, revisions: $revisions)';
}


}

/// @nodoc
abstract mixin class $ConversationPlanArtifactCopyWith<$Res>  {
  factory $ConversationPlanArtifactCopyWith(ConversationPlanArtifact value, $Res Function(ConversationPlanArtifact) _then) = _$ConversationPlanArtifactCopyWithImpl;
@useResult
$Res call({
 String draftMarkdown, String approvedMarkdown, DateTime? updatedAt, List<ConversationPlanRevision> revisions
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
@pragma('vm:prefer-inline') @override $Res call({Object? draftMarkdown = null,Object? approvedMarkdown = null,Object? updatedAt = freezed,Object? revisions = null,}) {
  return _then(_self.copyWith(
draftMarkdown: null == draftMarkdown ? _self.draftMarkdown : draftMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedMarkdown: null == approvedMarkdown ? _self.approvedMarkdown : approvedMarkdown // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,revisions: null == revisions ? _self.revisions : revisions // ignore: cast_nullable_to_non_nullable
as List<ConversationPlanRevision>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String draftMarkdown,  String approvedMarkdown,  DateTime? updatedAt,  List<ConversationPlanRevision> revisions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationPlanArtifact() when $default != null:
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.updatedAt,_that.revisions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String draftMarkdown,  String approvedMarkdown,  DateTime? updatedAt,  List<ConversationPlanRevision> revisions)  $default,) {final _that = this;
switch (_that) {
case _ConversationPlanArtifact():
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.updatedAt,_that.revisions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String draftMarkdown,  String approvedMarkdown,  DateTime? updatedAt,  List<ConversationPlanRevision> revisions)?  $default,) {final _that = this;
switch (_that) {
case _ConversationPlanArtifact() when $default != null:
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.updatedAt,_that.revisions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationPlanArtifact extends ConversationPlanArtifact {
  const _ConversationPlanArtifact({this.draftMarkdown = '', this.approvedMarkdown = '', this.updatedAt, final  List<ConversationPlanRevision> revisions = const <ConversationPlanRevision>[]}): _revisions = revisions,super._();
  factory _ConversationPlanArtifact.fromJson(Map<String, dynamic> json) => _$ConversationPlanArtifactFromJson(json);

@override@JsonKey() final  String draftMarkdown;
@override@JsonKey() final  String approvedMarkdown;
@override final  DateTime? updatedAt;
 final  List<ConversationPlanRevision> _revisions;
@override@JsonKey() List<ConversationPlanRevision> get revisions {
  if (_revisions is EqualUnmodifiableListView) return _revisions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_revisions);
}


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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationPlanArtifact&&(identical(other.draftMarkdown, draftMarkdown) || other.draftMarkdown == draftMarkdown)&&(identical(other.approvedMarkdown, approvedMarkdown) || other.approvedMarkdown == approvedMarkdown)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other._revisions, _revisions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,draftMarkdown,approvedMarkdown,updatedAt,const DeepCollectionEquality().hash(_revisions));

@override
String toString() {
  return 'ConversationPlanArtifact(draftMarkdown: $draftMarkdown, approvedMarkdown: $approvedMarkdown, updatedAt: $updatedAt, revisions: $revisions)';
}


}

/// @nodoc
abstract mixin class _$ConversationPlanArtifactCopyWith<$Res> implements $ConversationPlanArtifactCopyWith<$Res> {
  factory _$ConversationPlanArtifactCopyWith(_ConversationPlanArtifact value, $Res Function(_ConversationPlanArtifact) _then) = __$ConversationPlanArtifactCopyWithImpl;
@override @useResult
$Res call({
 String draftMarkdown, String approvedMarkdown, DateTime? updatedAt, List<ConversationPlanRevision> revisions
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
@override @pragma('vm:prefer-inline') $Res call({Object? draftMarkdown = null,Object? approvedMarkdown = null,Object? updatedAt = freezed,Object? revisions = null,}) {
  return _then(_ConversationPlanArtifact(
draftMarkdown: null == draftMarkdown ? _self.draftMarkdown : draftMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedMarkdown: null == approvedMarkdown ? _self.approvedMarkdown : approvedMarkdown // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,revisions: null == revisions ? _self._revisions : revisions // ignore: cast_nullable_to_non_nullable
as List<ConversationPlanRevision>,
  ));
}


}

// dart format on
