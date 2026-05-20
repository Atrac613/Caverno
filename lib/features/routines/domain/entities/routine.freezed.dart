// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoutinePlanRevision {

 String get markdown; DateTime get createdAt;@JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft) RoutinePlanRevisionKind get kind; String get label;
/// Create a copy of RoutinePlanRevision
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutinePlanRevisionCopyWith<RoutinePlanRevision> get copyWith => _$RoutinePlanRevisionCopyWithImpl<RoutinePlanRevision>(this as RoutinePlanRevision, _$identity);

  /// Serializes this RoutinePlanRevision to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutinePlanRevision&&(identical(other.markdown, markdown) || other.markdown == markdown)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,markdown,createdAt,kind,label);

@override
String toString() {
  return 'RoutinePlanRevision(markdown: $markdown, createdAt: $createdAt, kind: $kind, label: $label)';
}


}

/// @nodoc
abstract mixin class $RoutinePlanRevisionCopyWith<$Res>  {
  factory $RoutinePlanRevisionCopyWith(RoutinePlanRevision value, $Res Function(RoutinePlanRevision) _then) = _$RoutinePlanRevisionCopyWithImpl;
@useResult
$Res call({
 String markdown, DateTime createdAt,@JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft) RoutinePlanRevisionKind kind, String label
});




}
/// @nodoc
class _$RoutinePlanRevisionCopyWithImpl<$Res>
    implements $RoutinePlanRevisionCopyWith<$Res> {
  _$RoutinePlanRevisionCopyWithImpl(this._self, this._then);

  final RoutinePlanRevision _self;
  final $Res Function(RoutinePlanRevision) _then;

/// Create a copy of RoutinePlanRevision
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? markdown = null,Object? createdAt = null,Object? kind = null,Object? label = null,}) {
  return _then(_self.copyWith(
markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as RoutinePlanRevisionKind,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutinePlanRevision].
extension RoutinePlanRevisionPatterns on RoutinePlanRevision {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutinePlanRevision value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutinePlanRevision() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutinePlanRevision value)  $default,){
final _that = this;
switch (_that) {
case _RoutinePlanRevision():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutinePlanRevision value)?  $default,){
final _that = this;
switch (_that) {
case _RoutinePlanRevision() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String markdown,  DateTime createdAt, @JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft)  RoutinePlanRevisionKind kind,  String label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutinePlanRevision() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String markdown,  DateTime createdAt, @JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft)  RoutinePlanRevisionKind kind,  String label)  $default,) {final _that = this;
switch (_that) {
case _RoutinePlanRevision():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String markdown,  DateTime createdAt, @JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft)  RoutinePlanRevisionKind kind,  String label)?  $default,) {final _that = this;
switch (_that) {
case _RoutinePlanRevision() when $default != null:
return $default(_that.markdown,_that.createdAt,_that.kind,_that.label);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutinePlanRevision extends RoutinePlanRevision {
  const _RoutinePlanRevision({required this.markdown, required this.createdAt, @JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft) this.kind = RoutinePlanRevisionKind.draft, this.label = ''}): super._();
  factory _RoutinePlanRevision.fromJson(Map<String, dynamic> json) => _$RoutinePlanRevisionFromJson(json);

@override final  String markdown;
@override final  DateTime createdAt;
@override@JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft) final  RoutinePlanRevisionKind kind;
@override@JsonKey() final  String label;

/// Create a copy of RoutinePlanRevision
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutinePlanRevisionCopyWith<_RoutinePlanRevision> get copyWith => __$RoutinePlanRevisionCopyWithImpl<_RoutinePlanRevision>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutinePlanRevisionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutinePlanRevision&&(identical(other.markdown, markdown) || other.markdown == markdown)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,markdown,createdAt,kind,label);

@override
String toString() {
  return 'RoutinePlanRevision(markdown: $markdown, createdAt: $createdAt, kind: $kind, label: $label)';
}


}

/// @nodoc
abstract mixin class _$RoutinePlanRevisionCopyWith<$Res> implements $RoutinePlanRevisionCopyWith<$Res> {
  factory _$RoutinePlanRevisionCopyWith(_RoutinePlanRevision value, $Res Function(_RoutinePlanRevision) _then) = __$RoutinePlanRevisionCopyWithImpl;
@override @useResult
$Res call({
 String markdown, DateTime createdAt,@JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft) RoutinePlanRevisionKind kind, String label
});




}
/// @nodoc
class __$RoutinePlanRevisionCopyWithImpl<$Res>
    implements _$RoutinePlanRevisionCopyWith<$Res> {
  __$RoutinePlanRevisionCopyWithImpl(this._self, this._then);

  final _RoutinePlanRevision _self;
  final $Res Function(_RoutinePlanRevision) _then;

/// Create a copy of RoutinePlanRevision
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? markdown = null,Object? createdAt = null,Object? kind = null,Object? label = null,}) {
  return _then(_RoutinePlanRevision(
markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as RoutinePlanRevisionKind,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$RoutinePlanArtifact {

 String get draftMarkdown; String get approvedMarkdown; String get approvedSourceHash; DateTime? get approvedAt; DateTime? get updatedAt;@JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson) List<RoutinePlanRevision> get revisions;
/// Create a copy of RoutinePlanArtifact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutinePlanArtifactCopyWith<RoutinePlanArtifact> get copyWith => _$RoutinePlanArtifactCopyWithImpl<RoutinePlanArtifact>(this as RoutinePlanArtifact, _$identity);

  /// Serializes this RoutinePlanArtifact to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutinePlanArtifact&&(identical(other.draftMarkdown, draftMarkdown) || other.draftMarkdown == draftMarkdown)&&(identical(other.approvedMarkdown, approvedMarkdown) || other.approvedMarkdown == approvedMarkdown)&&(identical(other.approvedSourceHash, approvedSourceHash) || other.approvedSourceHash == approvedSourceHash)&&(identical(other.approvedAt, approvedAt) || other.approvedAt == approvedAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.revisions, revisions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,draftMarkdown,approvedMarkdown,approvedSourceHash,approvedAt,updatedAt,const DeepCollectionEquality().hash(revisions));

@override
String toString() {
  return 'RoutinePlanArtifact(draftMarkdown: $draftMarkdown, approvedMarkdown: $approvedMarkdown, approvedSourceHash: $approvedSourceHash, approvedAt: $approvedAt, updatedAt: $updatedAt, revisions: $revisions)';
}


}

/// @nodoc
abstract mixin class $RoutinePlanArtifactCopyWith<$Res>  {
  factory $RoutinePlanArtifactCopyWith(RoutinePlanArtifact value, $Res Function(RoutinePlanArtifact) _then) = _$RoutinePlanArtifactCopyWithImpl;
@useResult
$Res call({
 String draftMarkdown, String approvedMarkdown, String approvedSourceHash, DateTime? approvedAt, DateTime? updatedAt,@JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson) List<RoutinePlanRevision> revisions
});




}
/// @nodoc
class _$RoutinePlanArtifactCopyWithImpl<$Res>
    implements $RoutinePlanArtifactCopyWith<$Res> {
  _$RoutinePlanArtifactCopyWithImpl(this._self, this._then);

  final RoutinePlanArtifact _self;
  final $Res Function(RoutinePlanArtifact) _then;

/// Create a copy of RoutinePlanArtifact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? draftMarkdown = null,Object? approvedMarkdown = null,Object? approvedSourceHash = null,Object? approvedAt = freezed,Object? updatedAt = freezed,Object? revisions = null,}) {
  return _then(_self.copyWith(
draftMarkdown: null == draftMarkdown ? _self.draftMarkdown : draftMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedMarkdown: null == approvedMarkdown ? _self.approvedMarkdown : approvedMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedSourceHash: null == approvedSourceHash ? _self.approvedSourceHash : approvedSourceHash // ignore: cast_nullable_to_non_nullable
as String,approvedAt: freezed == approvedAt ? _self.approvedAt : approvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,revisions: null == revisions ? _self.revisions : revisions // ignore: cast_nullable_to_non_nullable
as List<RoutinePlanRevision>,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutinePlanArtifact].
extension RoutinePlanArtifactPatterns on RoutinePlanArtifact {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutinePlanArtifact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutinePlanArtifact() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutinePlanArtifact value)  $default,){
final _that = this;
switch (_that) {
case _RoutinePlanArtifact():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutinePlanArtifact value)?  $default,){
final _that = this;
switch (_that) {
case _RoutinePlanArtifact() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String draftMarkdown,  String approvedMarkdown,  String approvedSourceHash,  DateTime? approvedAt,  DateTime? updatedAt, @JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson)  List<RoutinePlanRevision> revisions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutinePlanArtifact() when $default != null:
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.approvedSourceHash,_that.approvedAt,_that.updatedAt,_that.revisions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String draftMarkdown,  String approvedMarkdown,  String approvedSourceHash,  DateTime? approvedAt,  DateTime? updatedAt, @JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson)  List<RoutinePlanRevision> revisions)  $default,) {final _that = this;
switch (_that) {
case _RoutinePlanArtifact():
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.approvedSourceHash,_that.approvedAt,_that.updatedAt,_that.revisions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String draftMarkdown,  String approvedMarkdown,  String approvedSourceHash,  DateTime? approvedAt,  DateTime? updatedAt, @JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson)  List<RoutinePlanRevision> revisions)?  $default,) {final _that = this;
switch (_that) {
case _RoutinePlanArtifact() when $default != null:
return $default(_that.draftMarkdown,_that.approvedMarkdown,_that.approvedSourceHash,_that.approvedAt,_that.updatedAt,_that.revisions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutinePlanArtifact extends RoutinePlanArtifact {
  const _RoutinePlanArtifact({this.draftMarkdown = '', this.approvedMarkdown = '', this.approvedSourceHash = '', this.approvedAt, this.updatedAt, @JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson) final  List<RoutinePlanRevision> revisions = const <RoutinePlanRevision>[]}): _revisions = revisions,super._();
  factory _RoutinePlanArtifact.fromJson(Map<String, dynamic> json) => _$RoutinePlanArtifactFromJson(json);

@override@JsonKey() final  String draftMarkdown;
@override@JsonKey() final  String approvedMarkdown;
@override@JsonKey() final  String approvedSourceHash;
@override final  DateTime? approvedAt;
@override final  DateTime? updatedAt;
 final  List<RoutinePlanRevision> _revisions;
@override@JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson) List<RoutinePlanRevision> get revisions {
  if (_revisions is EqualUnmodifiableListView) return _revisions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_revisions);
}


/// Create a copy of RoutinePlanArtifact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutinePlanArtifactCopyWith<_RoutinePlanArtifact> get copyWith => __$RoutinePlanArtifactCopyWithImpl<_RoutinePlanArtifact>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutinePlanArtifactToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutinePlanArtifact&&(identical(other.draftMarkdown, draftMarkdown) || other.draftMarkdown == draftMarkdown)&&(identical(other.approvedMarkdown, approvedMarkdown) || other.approvedMarkdown == approvedMarkdown)&&(identical(other.approvedSourceHash, approvedSourceHash) || other.approvedSourceHash == approvedSourceHash)&&(identical(other.approvedAt, approvedAt) || other.approvedAt == approvedAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other._revisions, _revisions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,draftMarkdown,approvedMarkdown,approvedSourceHash,approvedAt,updatedAt,const DeepCollectionEquality().hash(_revisions));

@override
String toString() {
  return 'RoutinePlanArtifact(draftMarkdown: $draftMarkdown, approvedMarkdown: $approvedMarkdown, approvedSourceHash: $approvedSourceHash, approvedAt: $approvedAt, updatedAt: $updatedAt, revisions: $revisions)';
}


}

/// @nodoc
abstract mixin class _$RoutinePlanArtifactCopyWith<$Res> implements $RoutinePlanArtifactCopyWith<$Res> {
  factory _$RoutinePlanArtifactCopyWith(_RoutinePlanArtifact value, $Res Function(_RoutinePlanArtifact) _then) = __$RoutinePlanArtifactCopyWithImpl;
@override @useResult
$Res call({
 String draftMarkdown, String approvedMarkdown, String approvedSourceHash, DateTime? approvedAt, DateTime? updatedAt,@JsonKey(fromJson: _routinePlanRevisionsFromJson, toJson: _routinePlanRevisionsToJson) List<RoutinePlanRevision> revisions
});




}
/// @nodoc
class __$RoutinePlanArtifactCopyWithImpl<$Res>
    implements _$RoutinePlanArtifactCopyWith<$Res> {
  __$RoutinePlanArtifactCopyWithImpl(this._self, this._then);

  final _RoutinePlanArtifact _self;
  final $Res Function(_RoutinePlanArtifact) _then;

/// Create a copy of RoutinePlanArtifact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? draftMarkdown = null,Object? approvedMarkdown = null,Object? approvedSourceHash = null,Object? approvedAt = freezed,Object? updatedAt = freezed,Object? revisions = null,}) {
  return _then(_RoutinePlanArtifact(
draftMarkdown: null == draftMarkdown ? _self.draftMarkdown : draftMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedMarkdown: null == approvedMarkdown ? _self.approvedMarkdown : approvedMarkdown // ignore: cast_nullable_to_non_nullable
as String,approvedSourceHash: null == approvedSourceHash ? _self.approvedSourceHash : approvedSourceHash // ignore: cast_nullable_to_non_nullable
as String,approvedAt: freezed == approvedAt ? _self.approvedAt : approvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,revisions: null == revisions ? _self._revisions : revisions // ignore: cast_nullable_to_non_nullable
as List<RoutinePlanRevision>,
  ));
}


}


/// @nodoc
mixin _$RoutineRunRecord {

 String get id; DateTime get startedAt; DateTime get finishedAt;@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus get status;@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger get trigger; bool get usedPlan; String get planSourceHash; int get durationMs; bool get usedTools; int get toolCallCount; List<String> get toolNames;@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> get toolCalls; Map<String, String> get toolSourceLabels;@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus get deliveryStatus; DateTime? get deliveredAt; String get deliveryMessage; String get preview; String get output; String get error; bool get failureAcknowledged;
/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRunRecordCopyWith<RoutineRunRecord> get copyWith => _$RoutineRunRecordCopyWithImpl<RoutineRunRecord>(this as RoutineRunRecord, _$identity);

  /// Serializes this RoutineRunRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.usedPlan, usedPlan) || other.usedPlan == usedPlan)&&(identical(other.planSourceHash, planSourceHash) || other.planSourceHash == planSourceHash)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.usedTools, usedTools) || other.usedTools == usedTools)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&const DeepCollectionEquality().equals(other.toolNames, toolNames)&&const DeepCollectionEquality().equals(other.toolCalls, toolCalls)&&const DeepCollectionEquality().equals(other.toolSourceLabels, toolSourceLabels)&&(identical(other.deliveryStatus, deliveryStatus) || other.deliveryStatus == deliveryStatus)&&(identical(other.deliveredAt, deliveredAt) || other.deliveredAt == deliveredAt)&&(identical(other.deliveryMessage, deliveryMessage) || other.deliveryMessage == deliveryMessage)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.output, output) || other.output == output)&&(identical(other.error, error) || other.error == error)&&(identical(other.failureAcknowledged, failureAcknowledged) || other.failureAcknowledged == failureAcknowledged));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,startedAt,finishedAt,status,trigger,usedPlan,planSourceHash,durationMs,usedTools,toolCallCount,const DeepCollectionEquality().hash(toolNames),const DeepCollectionEquality().hash(toolCalls),const DeepCollectionEquality().hash(toolSourceLabels),deliveryStatus,deliveredAt,deliveryMessage,preview,output,error,failureAcknowledged]);

@override
String toString() {
  return 'RoutineRunRecord(id: $id, startedAt: $startedAt, finishedAt: $finishedAt, status: $status, trigger: $trigger, usedPlan: $usedPlan, planSourceHash: $planSourceHash, durationMs: $durationMs, usedTools: $usedTools, toolCallCount: $toolCallCount, toolNames: $toolNames, toolCalls: $toolCalls, toolSourceLabels: $toolSourceLabels, deliveryStatus: $deliveryStatus, deliveredAt: $deliveredAt, deliveryMessage: $deliveryMessage, preview: $preview, output: $output, error: $error, failureAcknowledged: $failureAcknowledged)';
}


}

/// @nodoc
abstract mixin class $RoutineRunRecordCopyWith<$Res>  {
  factory $RoutineRunRecordCopyWith(RoutineRunRecord value, $Res Function(RoutineRunRecord) _then) = _$RoutineRunRecordCopyWithImpl;
@useResult
$Res call({
 String id, DateTime startedAt, DateTime finishedAt,@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus status,@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger trigger, bool usedPlan, String planSourceHash, int durationMs, bool usedTools, int toolCallCount, List<String> toolNames,@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> toolCalls, Map<String, String> toolSourceLabels,@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus deliveryStatus, DateTime? deliveredAt, String deliveryMessage, String preview, String output, String error, bool failureAcknowledged
});




}
/// @nodoc
class _$RoutineRunRecordCopyWithImpl<$Res>
    implements $RoutineRunRecordCopyWith<$Res> {
  _$RoutineRunRecordCopyWithImpl(this._self, this._then);

  final RoutineRunRecord _self;
  final $Res Function(RoutineRunRecord) _then;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? startedAt = null,Object? finishedAt = null,Object? status = null,Object? trigger = null,Object? usedPlan = null,Object? planSourceHash = null,Object? durationMs = null,Object? usedTools = null,Object? toolCallCount = null,Object? toolNames = null,Object? toolCalls = null,Object? toolSourceLabels = null,Object? deliveryStatus = null,Object? deliveredAt = freezed,Object? deliveryMessage = null,Object? preview = null,Object? output = null,Object? error = null,Object? failureAcknowledged = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,finishedAt: null == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoutineRunStatus,trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as RoutineRunTrigger,usedPlan: null == usedPlan ? _self.usedPlan : usedPlan // ignore: cast_nullable_to_non_nullable
as bool,planSourceHash: null == planSourceHash ? _self.planSourceHash : planSourceHash // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,usedTools: null == usedTools ? _self.usedTools : usedTools // ignore: cast_nullable_to_non_nullable
as bool,toolCallCount: null == toolCallCount ? _self.toolCallCount : toolCallCount // ignore: cast_nullable_to_non_nullable
as int,toolNames: null == toolNames ? _self.toolNames : toolNames // ignore: cast_nullable_to_non_nullable
as List<String>,toolCalls: null == toolCalls ? _self.toolCalls : toolCalls // ignore: cast_nullable_to_non_nullable
as List<RoutineRunToolCall>,toolSourceLabels: null == toolSourceLabels ? _self.toolSourceLabels : toolSourceLabels // ignore: cast_nullable_to_non_nullable
as Map<String, String>,deliveryStatus: null == deliveryStatus ? _self.deliveryStatus : deliveryStatus // ignore: cast_nullable_to_non_nullable
as RoutineDeliveryStatus,deliveredAt: freezed == deliveredAt ? _self.deliveredAt : deliveredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deliveryMessage: null == deliveryMessage ? _self.deliveryMessage : deliveryMessage // ignore: cast_nullable_to_non_nullable
as String,preview: null == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as String,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,failureAcknowledged: null == failureAcknowledged ? _self.failureAcknowledged : failureAcknowledged // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineRunRecord].
extension RoutineRunRecordPatterns on RoutineRunRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineRunRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineRunRecord value)  $default,){
final _that = this;
switch (_that) {
case _RoutineRunRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineRunRecord value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  bool usedPlan,  String planSourceHash,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson)  List<RoutineRunToolCall> toolCalls,  Map<String, String> toolSourceLabels, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error,  bool failureAcknowledged)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.usedPlan,_that.planSourceHash,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.toolCalls,_that.toolSourceLabels,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error,_that.failureAcknowledged);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  bool usedPlan,  String planSourceHash,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson)  List<RoutineRunToolCall> toolCalls,  Map<String, String> toolSourceLabels, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error,  bool failureAcknowledged)  $default,) {final _that = this;
switch (_that) {
case _RoutineRunRecord():
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.usedPlan,_that.planSourceHash,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.toolCalls,_that.toolSourceLabels,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error,_that.failureAcknowledged);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  bool usedPlan,  String planSourceHash,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson)  List<RoutineRunToolCall> toolCalls,  Map<String, String> toolSourceLabels, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error,  bool failureAcknowledged)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.usedPlan,_that.planSourceHash,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.toolCalls,_that.toolSourceLabels,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error,_that.failureAcknowledged);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRunRecord extends RoutineRunRecord {
  const _RoutineRunRecord({required this.id, required this.startedAt, required this.finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed) this.status = RoutineRunStatus.completed, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual) this.trigger = RoutineRunTrigger.manual, this.usedPlan = false, this.planSourceHash = '', this.durationMs = 0, this.usedTools = false, this.toolCallCount = 0, final  List<String> toolNames = const <String>[], @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) final  List<RoutineRunToolCall> toolCalls = const <RoutineRunToolCall>[], final  Map<String, String> toolSourceLabels = const <String, String>{}, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) this.deliveryStatus = RoutineDeliveryStatus.notRequested, this.deliveredAt, this.deliveryMessage = '', this.preview = '', this.output = '', this.error = '', this.failureAcknowledged = false}): _toolNames = toolNames,_toolCalls = toolCalls,_toolSourceLabels = toolSourceLabels,super._();
  factory _RoutineRunRecord.fromJson(Map<String, dynamic> json) => _$RoutineRunRecordFromJson(json);

@override final  String id;
@override final  DateTime startedAt;
@override final  DateTime finishedAt;
@override@JsonKey(unknownEnumValue: RoutineRunStatus.completed) final  RoutineRunStatus status;
@override@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) final  RoutineRunTrigger trigger;
@override@JsonKey() final  bool usedPlan;
@override@JsonKey() final  String planSourceHash;
@override@JsonKey() final  int durationMs;
@override@JsonKey() final  bool usedTools;
@override@JsonKey() final  int toolCallCount;
 final  List<String> _toolNames;
@override@JsonKey() List<String> get toolNames {
  if (_toolNames is EqualUnmodifiableListView) return _toolNames;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_toolNames);
}

 final  List<RoutineRunToolCall> _toolCalls;
@override@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> get toolCalls {
  if (_toolCalls is EqualUnmodifiableListView) return _toolCalls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_toolCalls);
}

 final  Map<String, String> _toolSourceLabels;
@override@JsonKey() Map<String, String> get toolSourceLabels {
  if (_toolSourceLabels is EqualUnmodifiableMapView) return _toolSourceLabels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_toolSourceLabels);
}

@override@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) final  RoutineDeliveryStatus deliveryStatus;
@override final  DateTime? deliveredAt;
@override@JsonKey() final  String deliveryMessage;
@override@JsonKey() final  String preview;
@override@JsonKey() final  String output;
@override@JsonKey() final  String error;
@override@JsonKey() final  bool failureAcknowledged;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineRunRecordCopyWith<_RoutineRunRecord> get copyWith => __$RoutineRunRecordCopyWithImpl<_RoutineRunRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineRunRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.usedPlan, usedPlan) || other.usedPlan == usedPlan)&&(identical(other.planSourceHash, planSourceHash) || other.planSourceHash == planSourceHash)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.usedTools, usedTools) || other.usedTools == usedTools)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&const DeepCollectionEquality().equals(other._toolNames, _toolNames)&&const DeepCollectionEquality().equals(other._toolCalls, _toolCalls)&&const DeepCollectionEquality().equals(other._toolSourceLabels, _toolSourceLabels)&&(identical(other.deliveryStatus, deliveryStatus) || other.deliveryStatus == deliveryStatus)&&(identical(other.deliveredAt, deliveredAt) || other.deliveredAt == deliveredAt)&&(identical(other.deliveryMessage, deliveryMessage) || other.deliveryMessage == deliveryMessage)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.output, output) || other.output == output)&&(identical(other.error, error) || other.error == error)&&(identical(other.failureAcknowledged, failureAcknowledged) || other.failureAcknowledged == failureAcknowledged));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,startedAt,finishedAt,status,trigger,usedPlan,planSourceHash,durationMs,usedTools,toolCallCount,const DeepCollectionEquality().hash(_toolNames),const DeepCollectionEquality().hash(_toolCalls),const DeepCollectionEquality().hash(_toolSourceLabels),deliveryStatus,deliveredAt,deliveryMessage,preview,output,error,failureAcknowledged]);

@override
String toString() {
  return 'RoutineRunRecord(id: $id, startedAt: $startedAt, finishedAt: $finishedAt, status: $status, trigger: $trigger, usedPlan: $usedPlan, planSourceHash: $planSourceHash, durationMs: $durationMs, usedTools: $usedTools, toolCallCount: $toolCallCount, toolNames: $toolNames, toolCalls: $toolCalls, toolSourceLabels: $toolSourceLabels, deliveryStatus: $deliveryStatus, deliveredAt: $deliveredAt, deliveryMessage: $deliveryMessage, preview: $preview, output: $output, error: $error, failureAcknowledged: $failureAcknowledged)';
}


}

/// @nodoc
abstract mixin class _$RoutineRunRecordCopyWith<$Res> implements $RoutineRunRecordCopyWith<$Res> {
  factory _$RoutineRunRecordCopyWith(_RoutineRunRecord value, $Res Function(_RoutineRunRecord) _then) = __$RoutineRunRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime startedAt, DateTime finishedAt,@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus status,@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger trigger, bool usedPlan, String planSourceHash, int durationMs, bool usedTools, int toolCallCount, List<String> toolNames,@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> toolCalls, Map<String, String> toolSourceLabels,@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus deliveryStatus, DateTime? deliveredAt, String deliveryMessage, String preview, String output, String error, bool failureAcknowledged
});




}
/// @nodoc
class __$RoutineRunRecordCopyWithImpl<$Res>
    implements _$RoutineRunRecordCopyWith<$Res> {
  __$RoutineRunRecordCopyWithImpl(this._self, this._then);

  final _RoutineRunRecord _self;
  final $Res Function(_RoutineRunRecord) _then;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? startedAt = null,Object? finishedAt = null,Object? status = null,Object? trigger = null,Object? usedPlan = null,Object? planSourceHash = null,Object? durationMs = null,Object? usedTools = null,Object? toolCallCount = null,Object? toolNames = null,Object? toolCalls = null,Object? toolSourceLabels = null,Object? deliveryStatus = null,Object? deliveredAt = freezed,Object? deliveryMessage = null,Object? preview = null,Object? output = null,Object? error = null,Object? failureAcknowledged = null,}) {
  return _then(_RoutineRunRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,finishedAt: null == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoutineRunStatus,trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as RoutineRunTrigger,usedPlan: null == usedPlan ? _self.usedPlan : usedPlan // ignore: cast_nullable_to_non_nullable
as bool,planSourceHash: null == planSourceHash ? _self.planSourceHash : planSourceHash // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,usedTools: null == usedTools ? _self.usedTools : usedTools // ignore: cast_nullable_to_non_nullable
as bool,toolCallCount: null == toolCallCount ? _self.toolCallCount : toolCallCount // ignore: cast_nullable_to_non_nullable
as int,toolNames: null == toolNames ? _self._toolNames : toolNames // ignore: cast_nullable_to_non_nullable
as List<String>,toolCalls: null == toolCalls ? _self._toolCalls : toolCalls // ignore: cast_nullable_to_non_nullable
as List<RoutineRunToolCall>,toolSourceLabels: null == toolSourceLabels ? _self._toolSourceLabels : toolSourceLabels // ignore: cast_nullable_to_non_nullable
as Map<String, String>,deliveryStatus: null == deliveryStatus ? _self.deliveryStatus : deliveryStatus // ignore: cast_nullable_to_non_nullable
as RoutineDeliveryStatus,deliveredAt: freezed == deliveredAt ? _self.deliveredAt : deliveredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deliveryMessage: null == deliveryMessage ? _self.deliveryMessage : deliveryMessage // ignore: cast_nullable_to_non_nullable
as String,preview: null == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as String,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,failureAcknowledged: null == failureAcknowledged ? _self.failureAcknowledged : failureAcknowledged // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$RoutineRunToolCall {

 String get id; String get name; String get arguments; String get result;
/// Create a copy of RoutineRunToolCall
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRunToolCallCopyWith<RoutineRunToolCall> get copyWith => _$RoutineRunToolCallCopyWithImpl<RoutineRunToolCall>(this as RoutineRunToolCall, _$identity);

  /// Serializes this RoutineRunToolCall to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRunToolCall&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.result, result) || other.result == result));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,arguments,result);

@override
String toString() {
  return 'RoutineRunToolCall(id: $id, name: $name, arguments: $arguments, result: $result)';
}


}

/// @nodoc
abstract mixin class $RoutineRunToolCallCopyWith<$Res>  {
  factory $RoutineRunToolCallCopyWith(RoutineRunToolCall value, $Res Function(RoutineRunToolCall) _then) = _$RoutineRunToolCallCopyWithImpl;
@useResult
$Res call({
 String id, String name, String arguments, String result
});




}
/// @nodoc
class _$RoutineRunToolCallCopyWithImpl<$Res>
    implements $RoutineRunToolCallCopyWith<$Res> {
  _$RoutineRunToolCallCopyWithImpl(this._self, this._then);

  final RoutineRunToolCall _self;
  final $Res Function(RoutineRunToolCall) _then;

/// Create a copy of RoutineRunToolCall
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? arguments = null,Object? result = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineRunToolCall].
extension RoutineRunToolCallPatterns on RoutineRunToolCall {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineRunToolCall value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineRunToolCall() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineRunToolCall value)  $default,){
final _that = this;
switch (_that) {
case _RoutineRunToolCall():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineRunToolCall value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineRunToolCall() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String arguments,  String result)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRunToolCall() when $default != null:
return $default(_that.id,_that.name,_that.arguments,_that.result);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String arguments,  String result)  $default,) {final _that = this;
switch (_that) {
case _RoutineRunToolCall():
return $default(_that.id,_that.name,_that.arguments,_that.result);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String arguments,  String result)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRunToolCall() when $default != null:
return $default(_that.id,_that.name,_that.arguments,_that.result);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRunToolCall extends RoutineRunToolCall {
  const _RoutineRunToolCall({required this.id, required this.name, this.arguments = '', this.result = ''}): super._();
  factory _RoutineRunToolCall.fromJson(Map<String, dynamic> json) => _$RoutineRunToolCallFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  String arguments;
@override@JsonKey() final  String result;

/// Create a copy of RoutineRunToolCall
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineRunToolCallCopyWith<_RoutineRunToolCall> get copyWith => __$RoutineRunToolCallCopyWithImpl<_RoutineRunToolCall>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineRunToolCallToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRunToolCall&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.result, result) || other.result == result));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,arguments,result);

@override
String toString() {
  return 'RoutineRunToolCall(id: $id, name: $name, arguments: $arguments, result: $result)';
}


}

/// @nodoc
abstract mixin class _$RoutineRunToolCallCopyWith<$Res> implements $RoutineRunToolCallCopyWith<$Res> {
  factory _$RoutineRunToolCallCopyWith(_RoutineRunToolCall value, $Res Function(_RoutineRunToolCall) _then) = __$RoutineRunToolCallCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String arguments, String result
});




}
/// @nodoc
class __$RoutineRunToolCallCopyWithImpl<$Res>
    implements _$RoutineRunToolCallCopyWith<$Res> {
  __$RoutineRunToolCallCopyWithImpl(this._self, this._then);

  final _RoutineRunToolCall _self;
  final $Res Function(_RoutineRunToolCall) _then;

/// Create a copy of RoutineRunToolCall
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? arguments = null,Object? result = null,}) {
  return _then(_RoutineRunToolCall(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$Routine {

 String get id; String get name; String get prompt; DateTime get createdAt; DateTime get updatedAt; bool get enabled; bool get notifyOnCompletion; bool get toolsEnabled;@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction get completionAction;@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule get googleChatRule; String get workspaceDirectory; bool get allowWorkspaceWrites;@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) RoutinePlanArtifact? get planArtifact; int get intervalValue;@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit get intervalUnit;@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) RoutineScheduleMode get scheduleMode; int get timeOfDayMinutes; DateTime? get nextRunAt; DateTime? get lastRunAt; List<RoutineRunRecord> get runs;
/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineCopyWith<Routine> get copyWith => _$RoutineCopyWithImpl<Routine>(this as Routine, _$identity);

  /// Serializes this Routine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Routine&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.notifyOnCompletion, notifyOnCompletion) || other.notifyOnCompletion == notifyOnCompletion)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.completionAction, completionAction) || other.completionAction == completionAction)&&(identical(other.googleChatRule, googleChatRule) || other.googleChatRule == googleChatRule)&&(identical(other.workspaceDirectory, workspaceDirectory) || other.workspaceDirectory == workspaceDirectory)&&(identical(other.allowWorkspaceWrites, allowWorkspaceWrites) || other.allowWorkspaceWrites == allowWorkspaceWrites)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.intervalValue, intervalValue) || other.intervalValue == intervalValue)&&(identical(other.intervalUnit, intervalUnit) || other.intervalUnit == intervalUnit)&&(identical(other.scheduleMode, scheduleMode) || other.scheduleMode == scheduleMode)&&(identical(other.timeOfDayMinutes, timeOfDayMinutes) || other.timeOfDayMinutes == timeOfDayMinutes)&&(identical(other.nextRunAt, nextRunAt) || other.nextRunAt == nextRunAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&const DeepCollectionEquality().equals(other.runs, runs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,prompt,createdAt,updatedAt,enabled,notifyOnCompletion,toolsEnabled,completionAction,googleChatRule,workspaceDirectory,allowWorkspaceWrites,planArtifact,intervalValue,intervalUnit,scheduleMode,timeOfDayMinutes,nextRunAt,lastRunAt,const DeepCollectionEquality().hash(runs)]);

@override
String toString() {
  return 'Routine(id: $id, name: $name, prompt: $prompt, createdAt: $createdAt, updatedAt: $updatedAt, enabled: $enabled, notifyOnCompletion: $notifyOnCompletion, toolsEnabled: $toolsEnabled, completionAction: $completionAction, googleChatRule: $googleChatRule, workspaceDirectory: $workspaceDirectory, allowWorkspaceWrites: $allowWorkspaceWrites, planArtifact: $planArtifact, intervalValue: $intervalValue, intervalUnit: $intervalUnit, scheduleMode: $scheduleMode, timeOfDayMinutes: $timeOfDayMinutes, nextRunAt: $nextRunAt, lastRunAt: $lastRunAt, runs: $runs)';
}


}

/// @nodoc
abstract mixin class $RoutineCopyWith<$Res>  {
  factory $RoutineCopyWith(Routine value, $Res Function(Routine) _then) = _$RoutineCopyWithImpl;
@useResult
$Res call({
 String id, String name, String prompt, DateTime createdAt, DateTime updatedAt, bool enabled, bool notifyOnCompletion, bool toolsEnabled,@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction completionAction,@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule googleChatRule, String workspaceDirectory, bool allowWorkspaceWrites,@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) RoutinePlanArtifact? planArtifact, int intervalValue,@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit intervalUnit,@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) RoutineScheduleMode scheduleMode, int timeOfDayMinutes, DateTime? nextRunAt, DateTime? lastRunAt, List<RoutineRunRecord> runs
});


$RoutinePlanArtifactCopyWith<$Res>? get planArtifact;

}
/// @nodoc
class _$RoutineCopyWithImpl<$Res>
    implements $RoutineCopyWith<$Res> {
  _$RoutineCopyWithImpl(this._self, this._then);

  final Routine _self;
  final $Res Function(Routine) _then;

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? createdAt = null,Object? updatedAt = null,Object? enabled = null,Object? notifyOnCompletion = null,Object? toolsEnabled = null,Object? completionAction = null,Object? googleChatRule = null,Object? workspaceDirectory = null,Object? allowWorkspaceWrites = null,Object? planArtifact = freezed,Object? intervalValue = null,Object? intervalUnit = null,Object? scheduleMode = null,Object? timeOfDayMinutes = null,Object? nextRunAt = freezed,Object? lastRunAt = freezed,Object? runs = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,notifyOnCompletion: null == notifyOnCompletion ? _self.notifyOnCompletion : notifyOnCompletion // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,completionAction: null == completionAction ? _self.completionAction : completionAction // ignore: cast_nullable_to_non_nullable
as RoutineCompletionAction,googleChatRule: null == googleChatRule ? _self.googleChatRule : googleChatRule // ignore: cast_nullable_to_non_nullable
as RoutineGoogleChatRule,workspaceDirectory: null == workspaceDirectory ? _self.workspaceDirectory : workspaceDirectory // ignore: cast_nullable_to_non_nullable
as String,allowWorkspaceWrites: null == allowWorkspaceWrites ? _self.allowWorkspaceWrites : allowWorkspaceWrites // ignore: cast_nullable_to_non_nullable
as bool,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as RoutinePlanArtifact?,intervalValue: null == intervalValue ? _self.intervalValue : intervalValue // ignore: cast_nullable_to_non_nullable
as int,intervalUnit: null == intervalUnit ? _self.intervalUnit : intervalUnit // ignore: cast_nullable_to_non_nullable
as RoutineIntervalUnit,scheduleMode: null == scheduleMode ? _self.scheduleMode : scheduleMode // ignore: cast_nullable_to_non_nullable
as RoutineScheduleMode,timeOfDayMinutes: null == timeOfDayMinutes ? _self.timeOfDayMinutes : timeOfDayMinutes // ignore: cast_nullable_to_non_nullable
as int,nextRunAt: freezed == nextRunAt ? _self.nextRunAt : nextRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,runs: null == runs ? _self.runs : runs // ignore: cast_nullable_to_non_nullable
as List<RoutineRunRecord>,
  ));
}
/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoutinePlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $RoutinePlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}
}


/// Adds pattern-matching-related methods to [Routine].
extension RoutinePatterns on Routine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Routine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Routine() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Routine value)  $default,){
final _that = this;
switch (_that) {
case _Routine():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Routine value)?  $default,){
final _that = this;
switch (_that) {
case _Routine() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  String workspaceDirectory,  bool allowWorkspaceWrites, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson)  RoutinePlanArtifact? planArtifact,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)  RoutineScheduleMode scheduleMode,  int timeOfDayMinutes,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Routine() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.workspaceDirectory,_that.allowWorkspaceWrites,_that.planArtifact,_that.intervalValue,_that.intervalUnit,_that.scheduleMode,_that.timeOfDayMinutes,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  String workspaceDirectory,  bool allowWorkspaceWrites, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson)  RoutinePlanArtifact? planArtifact,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)  RoutineScheduleMode scheduleMode,  int timeOfDayMinutes,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)  $default,) {final _that = this;
switch (_that) {
case _Routine():
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.workspaceDirectory,_that.allowWorkspaceWrites,_that.planArtifact,_that.intervalValue,_that.intervalUnit,_that.scheduleMode,_that.timeOfDayMinutes,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  String workspaceDirectory,  bool allowWorkspaceWrites, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson)  RoutinePlanArtifact? planArtifact,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)  RoutineScheduleMode scheduleMode,  int timeOfDayMinutes,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)?  $default,) {final _that = this;
switch (_that) {
case _Routine() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.workspaceDirectory,_that.allowWorkspaceWrites,_that.planArtifact,_that.intervalValue,_that.intervalUnit,_that.scheduleMode,_that.timeOfDayMinutes,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Routine extends Routine {
  const _Routine({required this.id, required this.name, required this.prompt, required this.createdAt, required this.updatedAt, this.enabled = true, this.notifyOnCompletion = true, this.toolsEnabled = false, @JsonKey(unknownEnumValue: RoutineCompletionAction.none) this.completionAction = RoutineCompletionAction.none, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) this.googleChatRule = RoutineGoogleChatRule.onFailure, this.workspaceDirectory = '', this.allowWorkspaceWrites = false, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) this.planArtifact, this.intervalValue = 1, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) this.intervalUnit = RoutineIntervalUnit.hours, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval) this.scheduleMode = RoutineScheduleMode.interval, this.timeOfDayMinutes = 480, this.nextRunAt, this.lastRunAt, final  List<RoutineRunRecord> runs = const <RoutineRunRecord>[]}): _runs = runs,super._();
  factory _Routine.fromJson(Map<String, dynamic> json) => _$RoutineFromJson(json);

@override final  String id;
@override final  String name;
@override final  String prompt;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool notifyOnCompletion;
@override@JsonKey() final  bool toolsEnabled;
@override@JsonKey(unknownEnumValue: RoutineCompletionAction.none) final  RoutineCompletionAction completionAction;
@override@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) final  RoutineGoogleChatRule googleChatRule;
@override@JsonKey() final  String workspaceDirectory;
@override@JsonKey() final  bool allowWorkspaceWrites;
@override@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) final  RoutinePlanArtifact? planArtifact;
@override@JsonKey() final  int intervalValue;
@override@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) final  RoutineIntervalUnit intervalUnit;
@override@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) final  RoutineScheduleMode scheduleMode;
@override@JsonKey() final  int timeOfDayMinutes;
@override final  DateTime? nextRunAt;
@override final  DateTime? lastRunAt;
 final  List<RoutineRunRecord> _runs;
@override@JsonKey() List<RoutineRunRecord> get runs {
  if (_runs is EqualUnmodifiableListView) return _runs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_runs);
}


/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineCopyWith<_Routine> get copyWith => __$RoutineCopyWithImpl<_Routine>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Routine&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.notifyOnCompletion, notifyOnCompletion) || other.notifyOnCompletion == notifyOnCompletion)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.completionAction, completionAction) || other.completionAction == completionAction)&&(identical(other.googleChatRule, googleChatRule) || other.googleChatRule == googleChatRule)&&(identical(other.workspaceDirectory, workspaceDirectory) || other.workspaceDirectory == workspaceDirectory)&&(identical(other.allowWorkspaceWrites, allowWorkspaceWrites) || other.allowWorkspaceWrites == allowWorkspaceWrites)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.intervalValue, intervalValue) || other.intervalValue == intervalValue)&&(identical(other.intervalUnit, intervalUnit) || other.intervalUnit == intervalUnit)&&(identical(other.scheduleMode, scheduleMode) || other.scheduleMode == scheduleMode)&&(identical(other.timeOfDayMinutes, timeOfDayMinutes) || other.timeOfDayMinutes == timeOfDayMinutes)&&(identical(other.nextRunAt, nextRunAt) || other.nextRunAt == nextRunAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&const DeepCollectionEquality().equals(other._runs, _runs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,prompt,createdAt,updatedAt,enabled,notifyOnCompletion,toolsEnabled,completionAction,googleChatRule,workspaceDirectory,allowWorkspaceWrites,planArtifact,intervalValue,intervalUnit,scheduleMode,timeOfDayMinutes,nextRunAt,lastRunAt,const DeepCollectionEquality().hash(_runs)]);

@override
String toString() {
  return 'Routine(id: $id, name: $name, prompt: $prompt, createdAt: $createdAt, updatedAt: $updatedAt, enabled: $enabled, notifyOnCompletion: $notifyOnCompletion, toolsEnabled: $toolsEnabled, completionAction: $completionAction, googleChatRule: $googleChatRule, workspaceDirectory: $workspaceDirectory, allowWorkspaceWrites: $allowWorkspaceWrites, planArtifact: $planArtifact, intervalValue: $intervalValue, intervalUnit: $intervalUnit, scheduleMode: $scheduleMode, timeOfDayMinutes: $timeOfDayMinutes, nextRunAt: $nextRunAt, lastRunAt: $lastRunAt, runs: $runs)';
}


}

/// @nodoc
abstract mixin class _$RoutineCopyWith<$Res> implements $RoutineCopyWith<$Res> {
  factory _$RoutineCopyWith(_Routine value, $Res Function(_Routine) _then) = __$RoutineCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String prompt, DateTime createdAt, DateTime updatedAt, bool enabled, bool notifyOnCompletion, bool toolsEnabled,@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction completionAction,@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule googleChatRule, String workspaceDirectory, bool allowWorkspaceWrites,@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) RoutinePlanArtifact? planArtifact, int intervalValue,@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit intervalUnit,@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) RoutineScheduleMode scheduleMode, int timeOfDayMinutes, DateTime? nextRunAt, DateTime? lastRunAt, List<RoutineRunRecord> runs
});


@override $RoutinePlanArtifactCopyWith<$Res>? get planArtifact;

}
/// @nodoc
class __$RoutineCopyWithImpl<$Res>
    implements _$RoutineCopyWith<$Res> {
  __$RoutineCopyWithImpl(this._self, this._then);

  final _Routine _self;
  final $Res Function(_Routine) _then;

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? createdAt = null,Object? updatedAt = null,Object? enabled = null,Object? notifyOnCompletion = null,Object? toolsEnabled = null,Object? completionAction = null,Object? googleChatRule = null,Object? workspaceDirectory = null,Object? allowWorkspaceWrites = null,Object? planArtifact = freezed,Object? intervalValue = null,Object? intervalUnit = null,Object? scheduleMode = null,Object? timeOfDayMinutes = null,Object? nextRunAt = freezed,Object? lastRunAt = freezed,Object? runs = null,}) {
  return _then(_Routine(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,notifyOnCompletion: null == notifyOnCompletion ? _self.notifyOnCompletion : notifyOnCompletion // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,completionAction: null == completionAction ? _self.completionAction : completionAction // ignore: cast_nullable_to_non_nullable
as RoutineCompletionAction,googleChatRule: null == googleChatRule ? _self.googleChatRule : googleChatRule // ignore: cast_nullable_to_non_nullable
as RoutineGoogleChatRule,workspaceDirectory: null == workspaceDirectory ? _self.workspaceDirectory : workspaceDirectory // ignore: cast_nullable_to_non_nullable
as String,allowWorkspaceWrites: null == allowWorkspaceWrites ? _self.allowWorkspaceWrites : allowWorkspaceWrites // ignore: cast_nullable_to_non_nullable
as bool,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
as RoutinePlanArtifact?,intervalValue: null == intervalValue ? _self.intervalValue : intervalValue // ignore: cast_nullable_to_non_nullable
as int,intervalUnit: null == intervalUnit ? _self.intervalUnit : intervalUnit // ignore: cast_nullable_to_non_nullable
as RoutineIntervalUnit,scheduleMode: null == scheduleMode ? _self.scheduleMode : scheduleMode // ignore: cast_nullable_to_non_nullable
as RoutineScheduleMode,timeOfDayMinutes: null == timeOfDayMinutes ? _self.timeOfDayMinutes : timeOfDayMinutes // ignore: cast_nullable_to_non_nullable
as int,nextRunAt: freezed == nextRunAt ? _self.nextRunAt : nextRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,runs: null == runs ? _self._runs : runs // ignore: cast_nullable_to_non_nullable
as List<RoutineRunRecord>,
  ));
}

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoutinePlanArtifactCopyWith<$Res>? get planArtifact {
    if (_self.planArtifact == null) {
    return null;
  }

  return $RoutinePlanArtifactCopyWith<$Res>(_self.planArtifact!, (value) {
    return _then(_self.copyWith(planArtifact: value));
  });
}
}

// dart format on
