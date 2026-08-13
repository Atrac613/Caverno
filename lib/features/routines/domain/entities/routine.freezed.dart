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
mixin _$RoutineObjectiveEvidenceContract {

 String get objective; List<String> get acceptanceCriteria; String get verificationCommand; String get plan;
/// Create a copy of RoutineObjectiveEvidenceContract
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineObjectiveEvidenceContractCopyWith<RoutineObjectiveEvidenceContract> get copyWith => _$RoutineObjectiveEvidenceContractCopyWithImpl<RoutineObjectiveEvidenceContract>(this as RoutineObjectiveEvidenceContract, _$identity);

  /// Serializes this RoutineObjectiveEvidenceContract to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineObjectiveEvidenceContract&&(identical(other.objective, objective) || other.objective == objective)&&const DeepCollectionEquality().equals(other.acceptanceCriteria, acceptanceCriteria)&&(identical(other.verificationCommand, verificationCommand) || other.verificationCommand == verificationCommand)&&(identical(other.plan, plan) || other.plan == plan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,objective,const DeepCollectionEquality().hash(acceptanceCriteria),verificationCommand,plan);

@override
String toString() {
  return 'RoutineObjectiveEvidenceContract(objective: $objective, acceptanceCriteria: $acceptanceCriteria, verificationCommand: $verificationCommand, plan: $plan)';
}


}

/// @nodoc
abstract mixin class $RoutineObjectiveEvidenceContractCopyWith<$Res>  {
  factory $RoutineObjectiveEvidenceContractCopyWith(RoutineObjectiveEvidenceContract value, $Res Function(RoutineObjectiveEvidenceContract) _then) = _$RoutineObjectiveEvidenceContractCopyWithImpl;
@useResult
$Res call({
 String objective, List<String> acceptanceCriteria, String verificationCommand, String plan
});




}
/// @nodoc
class _$RoutineObjectiveEvidenceContractCopyWithImpl<$Res>
    implements $RoutineObjectiveEvidenceContractCopyWith<$Res> {
  _$RoutineObjectiveEvidenceContractCopyWithImpl(this._self, this._then);

  final RoutineObjectiveEvidenceContract _self;
  final $Res Function(RoutineObjectiveEvidenceContract) _then;

/// Create a copy of RoutineObjectiveEvidenceContract
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? objective = null,Object? acceptanceCriteria = null,Object? verificationCommand = null,Object? plan = null,}) {
  return _then(_self.copyWith(
objective: null == objective ? _self.objective : objective // ignore: cast_nullable_to_non_nullable
as String,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,verificationCommand: null == verificationCommand ? _self.verificationCommand : verificationCommand // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineObjectiveEvidenceContract].
extension RoutineObjectiveEvidenceContractPatterns on RoutineObjectiveEvidenceContract {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineObjectiveEvidenceContract value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineObjectiveEvidenceContract() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineObjectiveEvidenceContract value)  $default,){
final _that = this;
switch (_that) {
case _RoutineObjectiveEvidenceContract():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineObjectiveEvidenceContract value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineObjectiveEvidenceContract() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String objective,  List<String> acceptanceCriteria,  String verificationCommand,  String plan)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineObjectiveEvidenceContract() when $default != null:
return $default(_that.objective,_that.acceptanceCriteria,_that.verificationCommand,_that.plan);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String objective,  List<String> acceptanceCriteria,  String verificationCommand,  String plan)  $default,) {final _that = this;
switch (_that) {
case _RoutineObjectiveEvidenceContract():
return $default(_that.objective,_that.acceptanceCriteria,_that.verificationCommand,_that.plan);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String objective,  List<String> acceptanceCriteria,  String verificationCommand,  String plan)?  $default,) {final _that = this;
switch (_that) {
case _RoutineObjectiveEvidenceContract() when $default != null:
return $default(_that.objective,_that.acceptanceCriteria,_that.verificationCommand,_that.plan);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineObjectiveEvidenceContract implements RoutineObjectiveEvidenceContract {
  const _RoutineObjectiveEvidenceContract({required this.objective, final  List<String> acceptanceCriteria = const <String>[], required this.verificationCommand, this.plan = ''}): _acceptanceCriteria = acceptanceCriteria;
  factory _RoutineObjectiveEvidenceContract.fromJson(Map<String, dynamic> json) => _$RoutineObjectiveEvidenceContractFromJson(json);

@override final  String objective;
 final  List<String> _acceptanceCriteria;
@override@JsonKey() List<String> get acceptanceCriteria {
  if (_acceptanceCriteria is EqualUnmodifiableListView) return _acceptanceCriteria;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_acceptanceCriteria);
}

@override final  String verificationCommand;
@override@JsonKey() final  String plan;

/// Create a copy of RoutineObjectiveEvidenceContract
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineObjectiveEvidenceContractCopyWith<_RoutineObjectiveEvidenceContract> get copyWith => __$RoutineObjectiveEvidenceContractCopyWithImpl<_RoutineObjectiveEvidenceContract>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineObjectiveEvidenceContractToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineObjectiveEvidenceContract&&(identical(other.objective, objective) || other.objective == objective)&&const DeepCollectionEquality().equals(other._acceptanceCriteria, _acceptanceCriteria)&&(identical(other.verificationCommand, verificationCommand) || other.verificationCommand == verificationCommand)&&(identical(other.plan, plan) || other.plan == plan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,objective,const DeepCollectionEquality().hash(_acceptanceCriteria),verificationCommand,plan);

@override
String toString() {
  return 'RoutineObjectiveEvidenceContract(objective: $objective, acceptanceCriteria: $acceptanceCriteria, verificationCommand: $verificationCommand, plan: $plan)';
}


}

/// @nodoc
abstract mixin class _$RoutineObjectiveEvidenceContractCopyWith<$Res> implements $RoutineObjectiveEvidenceContractCopyWith<$Res> {
  factory _$RoutineObjectiveEvidenceContractCopyWith(_RoutineObjectiveEvidenceContract value, $Res Function(_RoutineObjectiveEvidenceContract) _then) = __$RoutineObjectiveEvidenceContractCopyWithImpl;
@override @useResult
$Res call({
 String objective, List<String> acceptanceCriteria, String verificationCommand, String plan
});




}
/// @nodoc
class __$RoutineObjectiveEvidenceContractCopyWithImpl<$Res>
    implements _$RoutineObjectiveEvidenceContractCopyWith<$Res> {
  __$RoutineObjectiveEvidenceContractCopyWithImpl(this._self, this._then);

  final _RoutineObjectiveEvidenceContract _self;
  final $Res Function(_RoutineObjectiveEvidenceContract) _then;

/// Create a copy of RoutineObjectiveEvidenceContract
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? objective = null,Object? acceptanceCriteria = null,Object? verificationCommand = null,Object? plan = null,}) {
  return _then(_RoutineObjectiveEvidenceContract(
objective: null == objective ? _self.objective : objective // ignore: cast_nullable_to_non_nullable
as String,acceptanceCriteria: null == acceptanceCriteria ? _self._acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,verificationCommand: null == verificationCommand ? _self.verificationCommand : verificationCommand // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$RoutineRetryUntilGreenConfig {

 bool get enabled; int get maxRounds; int get candidatesPerRound;
/// Create a copy of RoutineRetryUntilGreenConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRetryUntilGreenConfigCopyWith<RoutineRetryUntilGreenConfig> get copyWith => _$RoutineRetryUntilGreenConfigCopyWithImpl<RoutineRetryUntilGreenConfig>(this as RoutineRetryUntilGreenConfig, _$identity);

  /// Serializes this RoutineRetryUntilGreenConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRetryUntilGreenConfig&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.maxRounds, maxRounds) || other.maxRounds == maxRounds)&&(identical(other.candidatesPerRound, candidatesPerRound) || other.candidatesPerRound == candidatesPerRound));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,enabled,maxRounds,candidatesPerRound);

@override
String toString() {
  return 'RoutineRetryUntilGreenConfig(enabled: $enabled, maxRounds: $maxRounds, candidatesPerRound: $candidatesPerRound)';
}


}

/// @nodoc
abstract mixin class $RoutineRetryUntilGreenConfigCopyWith<$Res>  {
  factory $RoutineRetryUntilGreenConfigCopyWith(RoutineRetryUntilGreenConfig value, $Res Function(RoutineRetryUntilGreenConfig) _then) = _$RoutineRetryUntilGreenConfigCopyWithImpl;
@useResult
$Res call({
 bool enabled, int maxRounds, int candidatesPerRound
});




}
/// @nodoc
class _$RoutineRetryUntilGreenConfigCopyWithImpl<$Res>
    implements $RoutineRetryUntilGreenConfigCopyWith<$Res> {
  _$RoutineRetryUntilGreenConfigCopyWithImpl(this._self, this._then);

  final RoutineRetryUntilGreenConfig _self;
  final $Res Function(RoutineRetryUntilGreenConfig) _then;

/// Create a copy of RoutineRetryUntilGreenConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? maxRounds = null,Object? candidatesPerRound = null,}) {
  return _then(_self.copyWith(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,maxRounds: null == maxRounds ? _self.maxRounds : maxRounds // ignore: cast_nullable_to_non_nullable
as int,candidatesPerRound: null == candidatesPerRound ? _self.candidatesPerRound : candidatesPerRound // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineRetryUntilGreenConfig].
extension RoutineRetryUntilGreenConfigPatterns on RoutineRetryUntilGreenConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineRetryUntilGreenConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineRetryUntilGreenConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineRetryUntilGreenConfig value)  $default,){
final _that = this;
switch (_that) {
case _RoutineRetryUntilGreenConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineRetryUntilGreenConfig value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineRetryUntilGreenConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enabled,  int maxRounds,  int candidatesPerRound)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRetryUntilGreenConfig() when $default != null:
return $default(_that.enabled,_that.maxRounds,_that.candidatesPerRound);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enabled,  int maxRounds,  int candidatesPerRound)  $default,) {final _that = this;
switch (_that) {
case _RoutineRetryUntilGreenConfig():
return $default(_that.enabled,_that.maxRounds,_that.candidatesPerRound);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enabled,  int maxRounds,  int candidatesPerRound)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRetryUntilGreenConfig() when $default != null:
return $default(_that.enabled,_that.maxRounds,_that.candidatesPerRound);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRetryUntilGreenConfig implements RoutineRetryUntilGreenConfig {
  const _RoutineRetryUntilGreenConfig({this.enabled = false, this.maxRounds = 3, this.candidatesPerRound = 2});
  factory _RoutineRetryUntilGreenConfig.fromJson(Map<String, dynamic> json) => _$RoutineRetryUntilGreenConfigFromJson(json);

@override@JsonKey() final  bool enabled;
@override@JsonKey() final  int maxRounds;
@override@JsonKey() final  int candidatesPerRound;

/// Create a copy of RoutineRetryUntilGreenConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineRetryUntilGreenConfigCopyWith<_RoutineRetryUntilGreenConfig> get copyWith => __$RoutineRetryUntilGreenConfigCopyWithImpl<_RoutineRetryUntilGreenConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineRetryUntilGreenConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRetryUntilGreenConfig&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.maxRounds, maxRounds) || other.maxRounds == maxRounds)&&(identical(other.candidatesPerRound, candidatesPerRound) || other.candidatesPerRound == candidatesPerRound));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,enabled,maxRounds,candidatesPerRound);

@override
String toString() {
  return 'RoutineRetryUntilGreenConfig(enabled: $enabled, maxRounds: $maxRounds, candidatesPerRound: $candidatesPerRound)';
}


}

/// @nodoc
abstract mixin class _$RoutineRetryUntilGreenConfigCopyWith<$Res> implements $RoutineRetryUntilGreenConfigCopyWith<$Res> {
  factory _$RoutineRetryUntilGreenConfigCopyWith(_RoutineRetryUntilGreenConfig value, $Res Function(_RoutineRetryUntilGreenConfig) _then) = __$RoutineRetryUntilGreenConfigCopyWithImpl;
@override @useResult
$Res call({
 bool enabled, int maxRounds, int candidatesPerRound
});




}
/// @nodoc
class __$RoutineRetryUntilGreenConfigCopyWithImpl<$Res>
    implements _$RoutineRetryUntilGreenConfigCopyWith<$Res> {
  __$RoutineRetryUntilGreenConfigCopyWithImpl(this._self, this._then);

  final _RoutineRetryUntilGreenConfig _self;
  final $Res Function(_RoutineRetryUntilGreenConfig) _then;

/// Create a copy of RoutineRetryUntilGreenConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? maxRounds = null,Object? candidatesPerRound = null,}) {
  return _then(_RoutineRetryUntilGreenConfig(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,maxRounds: null == maxRounds ? _self.maxRounds : maxRounds // ignore: cast_nullable_to_non_nullable
as int,candidatesPerRound: null == candidatesPerRound ? _self.candidatesPerRound : candidatesPerRound // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


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

 String get id; DateTime get startedAt; DateTime get finishedAt;@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus get status;@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger get trigger; bool get usedPlan; String get planSourceHash; int get durationMs; bool get usedTools; int get toolCallCount; List<String> get toolNames;@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> get toolCalls; Map<String, String> get toolSourceLabels;@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus get deliveryStatus; DateTime? get deliveredAt; String get deliveryMessage; String get preview; String get output; String get error; bool get failureAcknowledged; String get objective; List<String> get objectiveAcceptanceCriteria; String get objectivePlan; RoutineRunMechanicalVerification? get mechanicalVerification;@JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson) List<RoutineRunChangedFileEvidence> get changedFiles; bool get changedFileEvidenceTruncated; List<String> get implementationEvidence;
/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRunRecordCopyWith<RoutineRunRecord> get copyWith => _$RoutineRunRecordCopyWithImpl<RoutineRunRecord>(this as RoutineRunRecord, _$identity);

  /// Serializes this RoutineRunRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.usedPlan, usedPlan) || other.usedPlan == usedPlan)&&(identical(other.planSourceHash, planSourceHash) || other.planSourceHash == planSourceHash)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.usedTools, usedTools) || other.usedTools == usedTools)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&const DeepCollectionEquality().equals(other.toolNames, toolNames)&&const DeepCollectionEquality().equals(other.toolCalls, toolCalls)&&const DeepCollectionEquality().equals(other.toolSourceLabels, toolSourceLabels)&&(identical(other.deliveryStatus, deliveryStatus) || other.deliveryStatus == deliveryStatus)&&(identical(other.deliveredAt, deliveredAt) || other.deliveredAt == deliveredAt)&&(identical(other.deliveryMessage, deliveryMessage) || other.deliveryMessage == deliveryMessage)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.output, output) || other.output == output)&&(identical(other.error, error) || other.error == error)&&(identical(other.failureAcknowledged, failureAcknowledged) || other.failureAcknowledged == failureAcknowledged)&&(identical(other.objective, objective) || other.objective == objective)&&const DeepCollectionEquality().equals(other.objectiveAcceptanceCriteria, objectiveAcceptanceCriteria)&&(identical(other.objectivePlan, objectivePlan) || other.objectivePlan == objectivePlan)&&(identical(other.mechanicalVerification, mechanicalVerification) || other.mechanicalVerification == mechanicalVerification)&&const DeepCollectionEquality().equals(other.changedFiles, changedFiles)&&(identical(other.changedFileEvidenceTruncated, changedFileEvidenceTruncated) || other.changedFileEvidenceTruncated == changedFileEvidenceTruncated)&&const DeepCollectionEquality().equals(other.implementationEvidence, implementationEvidence));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,startedAt,finishedAt,status,trigger,usedPlan,planSourceHash,durationMs,usedTools,toolCallCount,const DeepCollectionEquality().hash(toolNames),const DeepCollectionEquality().hash(toolCalls),const DeepCollectionEquality().hash(toolSourceLabels),deliveryStatus,deliveredAt,deliveryMessage,preview,output,error,failureAcknowledged,objective,const DeepCollectionEquality().hash(objectiveAcceptanceCriteria),objectivePlan,mechanicalVerification,const DeepCollectionEquality().hash(changedFiles),changedFileEvidenceTruncated,const DeepCollectionEquality().hash(implementationEvidence)]);

@override
String toString() {
  return 'RoutineRunRecord(id: $id, startedAt: $startedAt, finishedAt: $finishedAt, status: $status, trigger: $trigger, usedPlan: $usedPlan, planSourceHash: $planSourceHash, durationMs: $durationMs, usedTools: $usedTools, toolCallCount: $toolCallCount, toolNames: $toolNames, toolCalls: $toolCalls, toolSourceLabels: $toolSourceLabels, deliveryStatus: $deliveryStatus, deliveredAt: $deliveredAt, deliveryMessage: $deliveryMessage, preview: $preview, output: $output, error: $error, failureAcknowledged: $failureAcknowledged, objective: $objective, objectiveAcceptanceCriteria: $objectiveAcceptanceCriteria, objectivePlan: $objectivePlan, mechanicalVerification: $mechanicalVerification, changedFiles: $changedFiles, changedFileEvidenceTruncated: $changedFileEvidenceTruncated, implementationEvidence: $implementationEvidence)';
}


}

/// @nodoc
abstract mixin class $RoutineRunRecordCopyWith<$Res>  {
  factory $RoutineRunRecordCopyWith(RoutineRunRecord value, $Res Function(RoutineRunRecord) _then) = _$RoutineRunRecordCopyWithImpl;
@useResult
$Res call({
 String id, DateTime startedAt, DateTime finishedAt,@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus status,@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger trigger, bool usedPlan, String planSourceHash, int durationMs, bool usedTools, int toolCallCount, List<String> toolNames,@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> toolCalls, Map<String, String> toolSourceLabels,@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus deliveryStatus, DateTime? deliveredAt, String deliveryMessage, String preview, String output, String error, bool failureAcknowledged, String objective, List<String> objectiveAcceptanceCriteria, String objectivePlan, RoutineRunMechanicalVerification? mechanicalVerification,@JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson) List<RoutineRunChangedFileEvidence> changedFiles, bool changedFileEvidenceTruncated, List<String> implementationEvidence
});


$RoutineRunMechanicalVerificationCopyWith<$Res>? get mechanicalVerification;

}
/// @nodoc
class _$RoutineRunRecordCopyWithImpl<$Res>
    implements $RoutineRunRecordCopyWith<$Res> {
  _$RoutineRunRecordCopyWithImpl(this._self, this._then);

  final RoutineRunRecord _self;
  final $Res Function(RoutineRunRecord) _then;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? startedAt = null,Object? finishedAt = null,Object? status = null,Object? trigger = null,Object? usedPlan = null,Object? planSourceHash = null,Object? durationMs = null,Object? usedTools = null,Object? toolCallCount = null,Object? toolNames = null,Object? toolCalls = null,Object? toolSourceLabels = null,Object? deliveryStatus = null,Object? deliveredAt = freezed,Object? deliveryMessage = null,Object? preview = null,Object? output = null,Object? error = null,Object? failureAcknowledged = null,Object? objective = null,Object? objectiveAcceptanceCriteria = null,Object? objectivePlan = null,Object? mechanicalVerification = freezed,Object? changedFiles = null,Object? changedFileEvidenceTruncated = null,Object? implementationEvidence = null,}) {
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
as bool,objective: null == objective ? _self.objective : objective // ignore: cast_nullable_to_non_nullable
as String,objectiveAcceptanceCriteria: null == objectiveAcceptanceCriteria ? _self.objectiveAcceptanceCriteria : objectiveAcceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,objectivePlan: null == objectivePlan ? _self.objectivePlan : objectivePlan // ignore: cast_nullable_to_non_nullable
as String,mechanicalVerification: freezed == mechanicalVerification ? _self.mechanicalVerification : mechanicalVerification // ignore: cast_nullable_to_non_nullable
as RoutineRunMechanicalVerification?,changedFiles: null == changedFiles ? _self.changedFiles : changedFiles // ignore: cast_nullable_to_non_nullable
as List<RoutineRunChangedFileEvidence>,changedFileEvidenceTruncated: null == changedFileEvidenceTruncated ? _self.changedFileEvidenceTruncated : changedFileEvidenceTruncated // ignore: cast_nullable_to_non_nullable
as bool,implementationEvidence: null == implementationEvidence ? _self.implementationEvidence : implementationEvidence // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}
/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoutineRunMechanicalVerificationCopyWith<$Res>? get mechanicalVerification {
    if (_self.mechanicalVerification == null) {
    return null;
  }

  return $RoutineRunMechanicalVerificationCopyWith<$Res>(_self.mechanicalVerification!, (value) {
    return _then(_self.copyWith(mechanicalVerification: value));
  });
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  bool usedPlan,  String planSourceHash,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson)  List<RoutineRunToolCall> toolCalls,  Map<String, String> toolSourceLabels, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error,  bool failureAcknowledged,  String objective,  List<String> objectiveAcceptanceCriteria,  String objectivePlan,  RoutineRunMechanicalVerification? mechanicalVerification, @JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson)  List<RoutineRunChangedFileEvidence> changedFiles,  bool changedFileEvidenceTruncated,  List<String> implementationEvidence)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.usedPlan,_that.planSourceHash,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.toolCalls,_that.toolSourceLabels,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error,_that.failureAcknowledged,_that.objective,_that.objectiveAcceptanceCriteria,_that.objectivePlan,_that.mechanicalVerification,_that.changedFiles,_that.changedFileEvidenceTruncated,_that.implementationEvidence);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  bool usedPlan,  String planSourceHash,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson)  List<RoutineRunToolCall> toolCalls,  Map<String, String> toolSourceLabels, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error,  bool failureAcknowledged,  String objective,  List<String> objectiveAcceptanceCriteria,  String objectivePlan,  RoutineRunMechanicalVerification? mechanicalVerification, @JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson)  List<RoutineRunChangedFileEvidence> changedFiles,  bool changedFileEvidenceTruncated,  List<String> implementationEvidence)  $default,) {final _that = this;
switch (_that) {
case _RoutineRunRecord():
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.usedPlan,_that.planSourceHash,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.toolCalls,_that.toolSourceLabels,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error,_that.failureAcknowledged,_that.objective,_that.objectiveAcceptanceCriteria,_that.objectivePlan,_that.mechanicalVerification,_that.changedFiles,_that.changedFileEvidenceTruncated,_that.implementationEvidence);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime startedAt,  DateTime finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed)  RoutineRunStatus status, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)  RoutineRunTrigger trigger,  bool usedPlan,  String planSourceHash,  int durationMs,  bool usedTools,  int toolCallCount,  List<String> toolNames, @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson)  List<RoutineRunToolCall> toolCalls,  Map<String, String> toolSourceLabels, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)  RoutineDeliveryStatus deliveryStatus,  DateTime? deliveredAt,  String deliveryMessage,  String preview,  String output,  String error,  bool failureAcknowledged,  String objective,  List<String> objectiveAcceptanceCriteria,  String objectivePlan,  RoutineRunMechanicalVerification? mechanicalVerification, @JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson)  List<RoutineRunChangedFileEvidence> changedFiles,  bool changedFileEvidenceTruncated,  List<String> implementationEvidence)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRunRecord() when $default != null:
return $default(_that.id,_that.startedAt,_that.finishedAt,_that.status,_that.trigger,_that.usedPlan,_that.planSourceHash,_that.durationMs,_that.usedTools,_that.toolCallCount,_that.toolNames,_that.toolCalls,_that.toolSourceLabels,_that.deliveryStatus,_that.deliveredAt,_that.deliveryMessage,_that.preview,_that.output,_that.error,_that.failureAcknowledged,_that.objective,_that.objectiveAcceptanceCriteria,_that.objectivePlan,_that.mechanicalVerification,_that.changedFiles,_that.changedFileEvidenceTruncated,_that.implementationEvidence);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRunRecord extends RoutineRunRecord {
  const _RoutineRunRecord({required this.id, required this.startedAt, required this.finishedAt, @JsonKey(unknownEnumValue: RoutineRunStatus.completed) this.status = RoutineRunStatus.completed, @JsonKey(unknownEnumValue: RoutineRunTrigger.manual) this.trigger = RoutineRunTrigger.manual, this.usedPlan = false, this.planSourceHash = '', this.durationMs = 0, this.usedTools = false, this.toolCallCount = 0, final  List<String> toolNames = const <String>[], @JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) final  List<RoutineRunToolCall> toolCalls = const <RoutineRunToolCall>[], final  Map<String, String> toolSourceLabels = const <String, String>{}, @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) this.deliveryStatus = RoutineDeliveryStatus.notRequested, this.deliveredAt, this.deliveryMessage = '', this.preview = '', this.output = '', this.error = '', this.failureAcknowledged = false, this.objective = '', final  List<String> objectiveAcceptanceCriteria = const <String>[], this.objectivePlan = '', this.mechanicalVerification, @JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson) final  List<RoutineRunChangedFileEvidence> changedFiles = const <RoutineRunChangedFileEvidence>[], this.changedFileEvidenceTruncated = false, final  List<String> implementationEvidence = const <String>[]}): _toolNames = toolNames,_toolCalls = toolCalls,_toolSourceLabels = toolSourceLabels,_objectiveAcceptanceCriteria = objectiveAcceptanceCriteria,_changedFiles = changedFiles,_implementationEvidence = implementationEvidence,super._();
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
@override@JsonKey() final  String objective;
 final  List<String> _objectiveAcceptanceCriteria;
@override@JsonKey() List<String> get objectiveAcceptanceCriteria {
  if (_objectiveAcceptanceCriteria is EqualUnmodifiableListView) return _objectiveAcceptanceCriteria;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_objectiveAcceptanceCriteria);
}

@override@JsonKey() final  String objectivePlan;
@override final  RoutineRunMechanicalVerification? mechanicalVerification;
 final  List<RoutineRunChangedFileEvidence> _changedFiles;
@override@JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson) List<RoutineRunChangedFileEvidence> get changedFiles {
  if (_changedFiles is EqualUnmodifiableListView) return _changedFiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changedFiles);
}

@override@JsonKey() final  bool changedFileEvidenceTruncated;
 final  List<String> _implementationEvidence;
@override@JsonKey() List<String> get implementationEvidence {
  if (_implementationEvidence is EqualUnmodifiableListView) return _implementationEvidence;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_implementationEvidence);
}


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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRunRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.usedPlan, usedPlan) || other.usedPlan == usedPlan)&&(identical(other.planSourceHash, planSourceHash) || other.planSourceHash == planSourceHash)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.usedTools, usedTools) || other.usedTools == usedTools)&&(identical(other.toolCallCount, toolCallCount) || other.toolCallCount == toolCallCount)&&const DeepCollectionEquality().equals(other._toolNames, _toolNames)&&const DeepCollectionEquality().equals(other._toolCalls, _toolCalls)&&const DeepCollectionEquality().equals(other._toolSourceLabels, _toolSourceLabels)&&(identical(other.deliveryStatus, deliveryStatus) || other.deliveryStatus == deliveryStatus)&&(identical(other.deliveredAt, deliveredAt) || other.deliveredAt == deliveredAt)&&(identical(other.deliveryMessage, deliveryMessage) || other.deliveryMessage == deliveryMessage)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.output, output) || other.output == output)&&(identical(other.error, error) || other.error == error)&&(identical(other.failureAcknowledged, failureAcknowledged) || other.failureAcknowledged == failureAcknowledged)&&(identical(other.objective, objective) || other.objective == objective)&&const DeepCollectionEquality().equals(other._objectiveAcceptanceCriteria, _objectiveAcceptanceCriteria)&&(identical(other.objectivePlan, objectivePlan) || other.objectivePlan == objectivePlan)&&(identical(other.mechanicalVerification, mechanicalVerification) || other.mechanicalVerification == mechanicalVerification)&&const DeepCollectionEquality().equals(other._changedFiles, _changedFiles)&&(identical(other.changedFileEvidenceTruncated, changedFileEvidenceTruncated) || other.changedFileEvidenceTruncated == changedFileEvidenceTruncated)&&const DeepCollectionEquality().equals(other._implementationEvidence, _implementationEvidence));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,startedAt,finishedAt,status,trigger,usedPlan,planSourceHash,durationMs,usedTools,toolCallCount,const DeepCollectionEquality().hash(_toolNames),const DeepCollectionEquality().hash(_toolCalls),const DeepCollectionEquality().hash(_toolSourceLabels),deliveryStatus,deliveredAt,deliveryMessage,preview,output,error,failureAcknowledged,objective,const DeepCollectionEquality().hash(_objectiveAcceptanceCriteria),objectivePlan,mechanicalVerification,const DeepCollectionEquality().hash(_changedFiles),changedFileEvidenceTruncated,const DeepCollectionEquality().hash(_implementationEvidence)]);

@override
String toString() {
  return 'RoutineRunRecord(id: $id, startedAt: $startedAt, finishedAt: $finishedAt, status: $status, trigger: $trigger, usedPlan: $usedPlan, planSourceHash: $planSourceHash, durationMs: $durationMs, usedTools: $usedTools, toolCallCount: $toolCallCount, toolNames: $toolNames, toolCalls: $toolCalls, toolSourceLabels: $toolSourceLabels, deliveryStatus: $deliveryStatus, deliveredAt: $deliveredAt, deliveryMessage: $deliveryMessage, preview: $preview, output: $output, error: $error, failureAcknowledged: $failureAcknowledged, objective: $objective, objectiveAcceptanceCriteria: $objectiveAcceptanceCriteria, objectivePlan: $objectivePlan, mechanicalVerification: $mechanicalVerification, changedFiles: $changedFiles, changedFileEvidenceTruncated: $changedFileEvidenceTruncated, implementationEvidence: $implementationEvidence)';
}


}

/// @nodoc
abstract mixin class _$RoutineRunRecordCopyWith<$Res> implements $RoutineRunRecordCopyWith<$Res> {
  factory _$RoutineRunRecordCopyWith(_RoutineRunRecord value, $Res Function(_RoutineRunRecord) _then) = __$RoutineRunRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime startedAt, DateTime finishedAt,@JsonKey(unknownEnumValue: RoutineRunStatus.completed) RoutineRunStatus status,@JsonKey(unknownEnumValue: RoutineRunTrigger.manual) RoutineRunTrigger trigger, bool usedPlan, String planSourceHash, int durationMs, bool usedTools, int toolCallCount, List<String> toolNames,@JsonKey(fromJson: _routineRunToolCallsFromJson, toJson: _routineRunToolCallsToJson) List<RoutineRunToolCall> toolCalls, Map<String, String> toolSourceLabels,@JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested) RoutineDeliveryStatus deliveryStatus, DateTime? deliveredAt, String deliveryMessage, String preview, String output, String error, bool failureAcknowledged, String objective, List<String> objectiveAcceptanceCriteria, String objectivePlan, RoutineRunMechanicalVerification? mechanicalVerification,@JsonKey(fromJson: _routineRunChangedFilesFromJson, toJson: _routineRunChangedFilesToJson) List<RoutineRunChangedFileEvidence> changedFiles, bool changedFileEvidenceTruncated, List<String> implementationEvidence
});


@override $RoutineRunMechanicalVerificationCopyWith<$Res>? get mechanicalVerification;

}
/// @nodoc
class __$RoutineRunRecordCopyWithImpl<$Res>
    implements _$RoutineRunRecordCopyWith<$Res> {
  __$RoutineRunRecordCopyWithImpl(this._self, this._then);

  final _RoutineRunRecord _self;
  final $Res Function(_RoutineRunRecord) _then;

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? startedAt = null,Object? finishedAt = null,Object? status = null,Object? trigger = null,Object? usedPlan = null,Object? planSourceHash = null,Object? durationMs = null,Object? usedTools = null,Object? toolCallCount = null,Object? toolNames = null,Object? toolCalls = null,Object? toolSourceLabels = null,Object? deliveryStatus = null,Object? deliveredAt = freezed,Object? deliveryMessage = null,Object? preview = null,Object? output = null,Object? error = null,Object? failureAcknowledged = null,Object? objective = null,Object? objectiveAcceptanceCriteria = null,Object? objectivePlan = null,Object? mechanicalVerification = freezed,Object? changedFiles = null,Object? changedFileEvidenceTruncated = null,Object? implementationEvidence = null,}) {
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
as bool,objective: null == objective ? _self.objective : objective // ignore: cast_nullable_to_non_nullable
as String,objectiveAcceptanceCriteria: null == objectiveAcceptanceCriteria ? _self._objectiveAcceptanceCriteria : objectiveAcceptanceCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,objectivePlan: null == objectivePlan ? _self.objectivePlan : objectivePlan // ignore: cast_nullable_to_non_nullable
as String,mechanicalVerification: freezed == mechanicalVerification ? _self.mechanicalVerification : mechanicalVerification // ignore: cast_nullable_to_non_nullable
as RoutineRunMechanicalVerification?,changedFiles: null == changedFiles ? _self._changedFiles : changedFiles // ignore: cast_nullable_to_non_nullable
as List<RoutineRunChangedFileEvidence>,changedFileEvidenceTruncated: null == changedFileEvidenceTruncated ? _self.changedFileEvidenceTruncated : changedFileEvidenceTruncated // ignore: cast_nullable_to_non_nullable
as bool,implementationEvidence: null == implementationEvidence ? _self._implementationEvidence : implementationEvidence // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

/// Create a copy of RoutineRunRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoutineRunMechanicalVerificationCopyWith<$Res>? get mechanicalVerification {
    if (_self.mechanicalVerification == null) {
    return null;
  }

  return $RoutineRunMechanicalVerificationCopyWith<$Res>(_self.mechanicalVerification!, (value) {
    return _then(_self.copyWith(mechanicalVerification: value));
  });
}
}


/// @nodoc
mixin _$RoutineRunMechanicalVerification {

 String get command; int get exitCode; String get output;
/// Create a copy of RoutineRunMechanicalVerification
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRunMechanicalVerificationCopyWith<RoutineRunMechanicalVerification> get copyWith => _$RoutineRunMechanicalVerificationCopyWithImpl<RoutineRunMechanicalVerification>(this as RoutineRunMechanicalVerification, _$identity);

  /// Serializes this RoutineRunMechanicalVerification to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRunMechanicalVerification&&(identical(other.command, command) || other.command == command)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.output, output) || other.output == output));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,command,exitCode,output);

@override
String toString() {
  return 'RoutineRunMechanicalVerification(command: $command, exitCode: $exitCode, output: $output)';
}


}

/// @nodoc
abstract mixin class $RoutineRunMechanicalVerificationCopyWith<$Res>  {
  factory $RoutineRunMechanicalVerificationCopyWith(RoutineRunMechanicalVerification value, $Res Function(RoutineRunMechanicalVerification) _then) = _$RoutineRunMechanicalVerificationCopyWithImpl;
@useResult
$Res call({
 String command, int exitCode, String output
});




}
/// @nodoc
class _$RoutineRunMechanicalVerificationCopyWithImpl<$Res>
    implements $RoutineRunMechanicalVerificationCopyWith<$Res> {
  _$RoutineRunMechanicalVerificationCopyWithImpl(this._self, this._then);

  final RoutineRunMechanicalVerification _self;
  final $Res Function(RoutineRunMechanicalVerification) _then;

/// Create a copy of RoutineRunMechanicalVerification
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? command = null,Object? exitCode = null,Object? output = null,}) {
  return _then(_self.copyWith(
command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,exitCode: null == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineRunMechanicalVerification].
extension RoutineRunMechanicalVerificationPatterns on RoutineRunMechanicalVerification {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineRunMechanicalVerification value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineRunMechanicalVerification() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineRunMechanicalVerification value)  $default,){
final _that = this;
switch (_that) {
case _RoutineRunMechanicalVerification():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineRunMechanicalVerification value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineRunMechanicalVerification() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String command,  int exitCode,  String output)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRunMechanicalVerification() when $default != null:
return $default(_that.command,_that.exitCode,_that.output);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String command,  int exitCode,  String output)  $default,) {final _that = this;
switch (_that) {
case _RoutineRunMechanicalVerification():
return $default(_that.command,_that.exitCode,_that.output);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String command,  int exitCode,  String output)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRunMechanicalVerification() when $default != null:
return $default(_that.command,_that.exitCode,_that.output);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRunMechanicalVerification extends RoutineRunMechanicalVerification {
  const _RoutineRunMechanicalVerification({required this.command, required this.exitCode, this.output = ''}): super._();
  factory _RoutineRunMechanicalVerification.fromJson(Map<String, dynamic> json) => _$RoutineRunMechanicalVerificationFromJson(json);

@override final  String command;
@override final  int exitCode;
@override@JsonKey() final  String output;

/// Create a copy of RoutineRunMechanicalVerification
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineRunMechanicalVerificationCopyWith<_RoutineRunMechanicalVerification> get copyWith => __$RoutineRunMechanicalVerificationCopyWithImpl<_RoutineRunMechanicalVerification>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineRunMechanicalVerificationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRunMechanicalVerification&&(identical(other.command, command) || other.command == command)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.output, output) || other.output == output));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,command,exitCode,output);

@override
String toString() {
  return 'RoutineRunMechanicalVerification(command: $command, exitCode: $exitCode, output: $output)';
}


}

/// @nodoc
abstract mixin class _$RoutineRunMechanicalVerificationCopyWith<$Res> implements $RoutineRunMechanicalVerificationCopyWith<$Res> {
  factory _$RoutineRunMechanicalVerificationCopyWith(_RoutineRunMechanicalVerification value, $Res Function(_RoutineRunMechanicalVerification) _then) = __$RoutineRunMechanicalVerificationCopyWithImpl;
@override @useResult
$Res call({
 String command, int exitCode, String output
});




}
/// @nodoc
class __$RoutineRunMechanicalVerificationCopyWithImpl<$Res>
    implements _$RoutineRunMechanicalVerificationCopyWith<$Res> {
  __$RoutineRunMechanicalVerificationCopyWithImpl(this._self, this._then);

  final _RoutineRunMechanicalVerification _self;
  final $Res Function(_RoutineRunMechanicalVerification) _then;

/// Create a copy of RoutineRunMechanicalVerification
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? command = null,Object? exitCode = null,Object? output = null,}) {
  return _then(_RoutineRunMechanicalVerification(
command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,exitCode: null == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$RoutineRunChangedFileEvidence {

 String get path; String get content; int get byteSize; String get contentHash; bool get truncated;
/// Create a copy of RoutineRunChangedFileEvidence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineRunChangedFileEvidenceCopyWith<RoutineRunChangedFileEvidence> get copyWith => _$RoutineRunChangedFileEvidenceCopyWithImpl<RoutineRunChangedFileEvidence>(this as RoutineRunChangedFileEvidence, _$identity);

  /// Serializes this RoutineRunChangedFileEvidence to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutineRunChangedFileEvidence&&(identical(other.path, path) || other.path == path)&&(identical(other.content, content) || other.content == content)&&(identical(other.byteSize, byteSize) || other.byteSize == byteSize)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.truncated, truncated) || other.truncated == truncated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,content,byteSize,contentHash,truncated);

@override
String toString() {
  return 'RoutineRunChangedFileEvidence(path: $path, content: $content, byteSize: $byteSize, contentHash: $contentHash, truncated: $truncated)';
}


}

/// @nodoc
abstract mixin class $RoutineRunChangedFileEvidenceCopyWith<$Res>  {
  factory $RoutineRunChangedFileEvidenceCopyWith(RoutineRunChangedFileEvidence value, $Res Function(RoutineRunChangedFileEvidence) _then) = _$RoutineRunChangedFileEvidenceCopyWithImpl;
@useResult
$Res call({
 String path, String content, int byteSize, String contentHash, bool truncated
});




}
/// @nodoc
class _$RoutineRunChangedFileEvidenceCopyWithImpl<$Res>
    implements $RoutineRunChangedFileEvidenceCopyWith<$Res> {
  _$RoutineRunChangedFileEvidenceCopyWithImpl(this._self, this._then);

  final RoutineRunChangedFileEvidence _self;
  final $Res Function(RoutineRunChangedFileEvidence) _then;

/// Create a copy of RoutineRunChangedFileEvidence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? content = null,Object? byteSize = null,Object? contentHash = null,Object? truncated = null,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,byteSize: null == byteSize ? _self.byteSize : byteSize // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutineRunChangedFileEvidence].
extension RoutineRunChangedFileEvidencePatterns on RoutineRunChangedFileEvidence {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutineRunChangedFileEvidence value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutineRunChangedFileEvidence() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutineRunChangedFileEvidence value)  $default,){
final _that = this;
switch (_that) {
case _RoutineRunChangedFileEvidence():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutineRunChangedFileEvidence value)?  $default,){
final _that = this;
switch (_that) {
case _RoutineRunChangedFileEvidence() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String content,  int byteSize,  String contentHash,  bool truncated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutineRunChangedFileEvidence() when $default != null:
return $default(_that.path,_that.content,_that.byteSize,_that.contentHash,_that.truncated);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String content,  int byteSize,  String contentHash,  bool truncated)  $default,) {final _that = this;
switch (_that) {
case _RoutineRunChangedFileEvidence():
return $default(_that.path,_that.content,_that.byteSize,_that.contentHash,_that.truncated);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String content,  int byteSize,  String contentHash,  bool truncated)?  $default,) {final _that = this;
switch (_that) {
case _RoutineRunChangedFileEvidence() when $default != null:
return $default(_that.path,_that.content,_that.byteSize,_that.contentHash,_that.truncated);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutineRunChangedFileEvidence implements RoutineRunChangedFileEvidence {
  const _RoutineRunChangedFileEvidence({required this.path, required this.content, required this.byteSize, required this.contentHash, this.truncated = false});
  factory _RoutineRunChangedFileEvidence.fromJson(Map<String, dynamic> json) => _$RoutineRunChangedFileEvidenceFromJson(json);

@override final  String path;
@override final  String content;
@override final  int byteSize;
@override final  String contentHash;
@override@JsonKey() final  bool truncated;

/// Create a copy of RoutineRunChangedFileEvidence
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutineRunChangedFileEvidenceCopyWith<_RoutineRunChangedFileEvidence> get copyWith => __$RoutineRunChangedFileEvidenceCopyWithImpl<_RoutineRunChangedFileEvidence>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutineRunChangedFileEvidenceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutineRunChangedFileEvidence&&(identical(other.path, path) || other.path == path)&&(identical(other.content, content) || other.content == content)&&(identical(other.byteSize, byteSize) || other.byteSize == byteSize)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.truncated, truncated) || other.truncated == truncated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,content,byteSize,contentHash,truncated);

@override
String toString() {
  return 'RoutineRunChangedFileEvidence(path: $path, content: $content, byteSize: $byteSize, contentHash: $contentHash, truncated: $truncated)';
}


}

/// @nodoc
abstract mixin class _$RoutineRunChangedFileEvidenceCopyWith<$Res> implements $RoutineRunChangedFileEvidenceCopyWith<$Res> {
  factory _$RoutineRunChangedFileEvidenceCopyWith(_RoutineRunChangedFileEvidence value, $Res Function(_RoutineRunChangedFileEvidence) _then) = __$RoutineRunChangedFileEvidenceCopyWithImpl;
@override @useResult
$Res call({
 String path, String content, int byteSize, String contentHash, bool truncated
});




}
/// @nodoc
class __$RoutineRunChangedFileEvidenceCopyWithImpl<$Res>
    implements _$RoutineRunChangedFileEvidenceCopyWith<$Res> {
  __$RoutineRunChangedFileEvidenceCopyWithImpl(this._self, this._then);

  final _RoutineRunChangedFileEvidence _self;
  final $Res Function(_RoutineRunChangedFileEvidence) _then;

/// Create a copy of RoutineRunChangedFileEvidence
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? content = null,Object? byteSize = null,Object? contentHash = null,Object? truncated = null,}) {
  return _then(_RoutineRunChangedFileEvidence(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,byteSize: null == byteSize ? _self.byteSize : byteSize // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
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

 String get id; String get name; String get prompt; DateTime get createdAt; DateTime get updatedAt; bool get enabled; bool get notifyOnCompletion; bool get toolsEnabled;@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction get completionAction;@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule get googleChatRule; String get workspaceDirectory; bool get allowWorkspaceWrites; RoutineObjectiveEvidenceContract? get objectiveEvidenceContract; RoutineRetryUntilGreenConfig? get retryUntilGreenConfig;@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) RoutinePlanArtifact? get planArtifact; int get intervalValue;@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit get intervalUnit;@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) RoutineScheduleMode get scheduleMode; int get timeOfDayMinutes; DateTime? get nextRunAt; DateTime? get lastRunAt; List<RoutineRunRecord> get runs;
/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutineCopyWith<Routine> get copyWith => _$RoutineCopyWithImpl<Routine>(this as Routine, _$identity);

  /// Serializes this Routine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Routine&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.notifyOnCompletion, notifyOnCompletion) || other.notifyOnCompletion == notifyOnCompletion)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.completionAction, completionAction) || other.completionAction == completionAction)&&(identical(other.googleChatRule, googleChatRule) || other.googleChatRule == googleChatRule)&&(identical(other.workspaceDirectory, workspaceDirectory) || other.workspaceDirectory == workspaceDirectory)&&(identical(other.allowWorkspaceWrites, allowWorkspaceWrites) || other.allowWorkspaceWrites == allowWorkspaceWrites)&&(identical(other.objectiveEvidenceContract, objectiveEvidenceContract) || other.objectiveEvidenceContract == objectiveEvidenceContract)&&(identical(other.retryUntilGreenConfig, retryUntilGreenConfig) || other.retryUntilGreenConfig == retryUntilGreenConfig)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.intervalValue, intervalValue) || other.intervalValue == intervalValue)&&(identical(other.intervalUnit, intervalUnit) || other.intervalUnit == intervalUnit)&&(identical(other.scheduleMode, scheduleMode) || other.scheduleMode == scheduleMode)&&(identical(other.timeOfDayMinutes, timeOfDayMinutes) || other.timeOfDayMinutes == timeOfDayMinutes)&&(identical(other.nextRunAt, nextRunAt) || other.nextRunAt == nextRunAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&const DeepCollectionEquality().equals(other.runs, runs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,prompt,createdAt,updatedAt,enabled,notifyOnCompletion,toolsEnabled,completionAction,googleChatRule,workspaceDirectory,allowWorkspaceWrites,objectiveEvidenceContract,retryUntilGreenConfig,planArtifact,intervalValue,intervalUnit,scheduleMode,timeOfDayMinutes,nextRunAt,lastRunAt,const DeepCollectionEquality().hash(runs)]);

@override
String toString() {
  return 'Routine(id: $id, name: $name, prompt: $prompt, createdAt: $createdAt, updatedAt: $updatedAt, enabled: $enabled, notifyOnCompletion: $notifyOnCompletion, toolsEnabled: $toolsEnabled, completionAction: $completionAction, googleChatRule: $googleChatRule, workspaceDirectory: $workspaceDirectory, allowWorkspaceWrites: $allowWorkspaceWrites, objectiveEvidenceContract: $objectiveEvidenceContract, retryUntilGreenConfig: $retryUntilGreenConfig, planArtifact: $planArtifact, intervalValue: $intervalValue, intervalUnit: $intervalUnit, scheduleMode: $scheduleMode, timeOfDayMinutes: $timeOfDayMinutes, nextRunAt: $nextRunAt, lastRunAt: $lastRunAt, runs: $runs)';
}


}

/// @nodoc
abstract mixin class $RoutineCopyWith<$Res>  {
  factory $RoutineCopyWith(Routine value, $Res Function(Routine) _then) = _$RoutineCopyWithImpl;
@useResult
$Res call({
 String id, String name, String prompt, DateTime createdAt, DateTime updatedAt, bool enabled, bool notifyOnCompletion, bool toolsEnabled,@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction completionAction,@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule googleChatRule, String workspaceDirectory, bool allowWorkspaceWrites, RoutineObjectiveEvidenceContract? objectiveEvidenceContract, RoutineRetryUntilGreenConfig? retryUntilGreenConfig,@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) RoutinePlanArtifact? planArtifact, int intervalValue,@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit intervalUnit,@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) RoutineScheduleMode scheduleMode, int timeOfDayMinutes, DateTime? nextRunAt, DateTime? lastRunAt, List<RoutineRunRecord> runs
});


$RoutineObjectiveEvidenceContractCopyWith<$Res>? get objectiveEvidenceContract;$RoutineRetryUntilGreenConfigCopyWith<$Res>? get retryUntilGreenConfig;$RoutinePlanArtifactCopyWith<$Res>? get planArtifact;

}
/// @nodoc
class _$RoutineCopyWithImpl<$Res>
    implements $RoutineCopyWith<$Res> {
  _$RoutineCopyWithImpl(this._self, this._then);

  final Routine _self;
  final $Res Function(Routine) _then;

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? createdAt = null,Object? updatedAt = null,Object? enabled = null,Object? notifyOnCompletion = null,Object? toolsEnabled = null,Object? completionAction = null,Object? googleChatRule = null,Object? workspaceDirectory = null,Object? allowWorkspaceWrites = null,Object? objectiveEvidenceContract = freezed,Object? retryUntilGreenConfig = freezed,Object? planArtifact = freezed,Object? intervalValue = null,Object? intervalUnit = null,Object? scheduleMode = null,Object? timeOfDayMinutes = null,Object? nextRunAt = freezed,Object? lastRunAt = freezed,Object? runs = null,}) {
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
as bool,objectiveEvidenceContract: freezed == objectiveEvidenceContract ? _self.objectiveEvidenceContract : objectiveEvidenceContract // ignore: cast_nullable_to_non_nullable
as RoutineObjectiveEvidenceContract?,retryUntilGreenConfig: freezed == retryUntilGreenConfig ? _self.retryUntilGreenConfig : retryUntilGreenConfig // ignore: cast_nullable_to_non_nullable
as RoutineRetryUntilGreenConfig?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
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
$RoutineObjectiveEvidenceContractCopyWith<$Res>? get objectiveEvidenceContract {
    if (_self.objectiveEvidenceContract == null) {
    return null;
  }

  return $RoutineObjectiveEvidenceContractCopyWith<$Res>(_self.objectiveEvidenceContract!, (value) {
    return _then(_self.copyWith(objectiveEvidenceContract: value));
  });
}/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoutineRetryUntilGreenConfigCopyWith<$Res>? get retryUntilGreenConfig {
    if (_self.retryUntilGreenConfig == null) {
    return null;
  }

  return $RoutineRetryUntilGreenConfigCopyWith<$Res>(_self.retryUntilGreenConfig!, (value) {
    return _then(_self.copyWith(retryUntilGreenConfig: value));
  });
}/// Create a copy of Routine
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  String workspaceDirectory,  bool allowWorkspaceWrites,  RoutineObjectiveEvidenceContract? objectiveEvidenceContract,  RoutineRetryUntilGreenConfig? retryUntilGreenConfig, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson)  RoutinePlanArtifact? planArtifact,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)  RoutineScheduleMode scheduleMode,  int timeOfDayMinutes,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Routine() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.workspaceDirectory,_that.allowWorkspaceWrites,_that.objectiveEvidenceContract,_that.retryUntilGreenConfig,_that.planArtifact,_that.intervalValue,_that.intervalUnit,_that.scheduleMode,_that.timeOfDayMinutes,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  String workspaceDirectory,  bool allowWorkspaceWrites,  RoutineObjectiveEvidenceContract? objectiveEvidenceContract,  RoutineRetryUntilGreenConfig? retryUntilGreenConfig, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson)  RoutinePlanArtifact? planArtifact,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)  RoutineScheduleMode scheduleMode,  int timeOfDayMinutes,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)  $default,) {final _that = this;
switch (_that) {
case _Routine():
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.workspaceDirectory,_that.allowWorkspaceWrites,_that.objectiveEvidenceContract,_that.retryUntilGreenConfig,_that.planArtifact,_that.intervalValue,_that.intervalUnit,_that.scheduleMode,_that.timeOfDayMinutes,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String prompt,  DateTime createdAt,  DateTime updatedAt,  bool enabled,  bool notifyOnCompletion,  bool toolsEnabled, @JsonKey(unknownEnumValue: RoutineCompletionAction.none)  RoutineCompletionAction completionAction, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)  RoutineGoogleChatRule googleChatRule,  String workspaceDirectory,  bool allowWorkspaceWrites,  RoutineObjectiveEvidenceContract? objectiveEvidenceContract,  RoutineRetryUntilGreenConfig? retryUntilGreenConfig, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson)  RoutinePlanArtifact? planArtifact,  int intervalValue, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)  RoutineIntervalUnit intervalUnit, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)  RoutineScheduleMode scheduleMode,  int timeOfDayMinutes,  DateTime? nextRunAt,  DateTime? lastRunAt,  List<RoutineRunRecord> runs)?  $default,) {final _that = this;
switch (_that) {
case _Routine() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.createdAt,_that.updatedAt,_that.enabled,_that.notifyOnCompletion,_that.toolsEnabled,_that.completionAction,_that.googleChatRule,_that.workspaceDirectory,_that.allowWorkspaceWrites,_that.objectiveEvidenceContract,_that.retryUntilGreenConfig,_that.planArtifact,_that.intervalValue,_that.intervalUnit,_that.scheduleMode,_that.timeOfDayMinutes,_that.nextRunAt,_that.lastRunAt,_that.runs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Routine extends Routine {
  const _Routine({required this.id, required this.name, required this.prompt, required this.createdAt, required this.updatedAt, this.enabled = true, this.notifyOnCompletion = true, this.toolsEnabled = false, @JsonKey(unknownEnumValue: RoutineCompletionAction.none) this.completionAction = RoutineCompletionAction.none, @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) this.googleChatRule = RoutineGoogleChatRule.onFailure, this.workspaceDirectory = '', this.allowWorkspaceWrites = false, this.objectiveEvidenceContract, this.retryUntilGreenConfig, @JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) this.planArtifact, this.intervalValue = 1, @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) this.intervalUnit = RoutineIntervalUnit.hours, @JsonKey(unknownEnumValue: RoutineScheduleMode.interval) this.scheduleMode = RoutineScheduleMode.interval, this.timeOfDayMinutes = 480, this.nextRunAt, this.lastRunAt, final  List<RoutineRunRecord> runs = const <RoutineRunRecord>[]}): _runs = runs,super._();
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
@override final  RoutineObjectiveEvidenceContract? objectiveEvidenceContract;
@override final  RoutineRetryUntilGreenConfig? retryUntilGreenConfig;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Routine&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.notifyOnCompletion, notifyOnCompletion) || other.notifyOnCompletion == notifyOnCompletion)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.completionAction, completionAction) || other.completionAction == completionAction)&&(identical(other.googleChatRule, googleChatRule) || other.googleChatRule == googleChatRule)&&(identical(other.workspaceDirectory, workspaceDirectory) || other.workspaceDirectory == workspaceDirectory)&&(identical(other.allowWorkspaceWrites, allowWorkspaceWrites) || other.allowWorkspaceWrites == allowWorkspaceWrites)&&(identical(other.objectiveEvidenceContract, objectiveEvidenceContract) || other.objectiveEvidenceContract == objectiveEvidenceContract)&&(identical(other.retryUntilGreenConfig, retryUntilGreenConfig) || other.retryUntilGreenConfig == retryUntilGreenConfig)&&(identical(other.planArtifact, planArtifact) || other.planArtifact == planArtifact)&&(identical(other.intervalValue, intervalValue) || other.intervalValue == intervalValue)&&(identical(other.intervalUnit, intervalUnit) || other.intervalUnit == intervalUnit)&&(identical(other.scheduleMode, scheduleMode) || other.scheduleMode == scheduleMode)&&(identical(other.timeOfDayMinutes, timeOfDayMinutes) || other.timeOfDayMinutes == timeOfDayMinutes)&&(identical(other.nextRunAt, nextRunAt) || other.nextRunAt == nextRunAt)&&(identical(other.lastRunAt, lastRunAt) || other.lastRunAt == lastRunAt)&&const DeepCollectionEquality().equals(other._runs, _runs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,name,prompt,createdAt,updatedAt,enabled,notifyOnCompletion,toolsEnabled,completionAction,googleChatRule,workspaceDirectory,allowWorkspaceWrites,objectiveEvidenceContract,retryUntilGreenConfig,planArtifact,intervalValue,intervalUnit,scheduleMode,timeOfDayMinutes,nextRunAt,lastRunAt,const DeepCollectionEquality().hash(_runs)]);

@override
String toString() {
  return 'Routine(id: $id, name: $name, prompt: $prompt, createdAt: $createdAt, updatedAt: $updatedAt, enabled: $enabled, notifyOnCompletion: $notifyOnCompletion, toolsEnabled: $toolsEnabled, completionAction: $completionAction, googleChatRule: $googleChatRule, workspaceDirectory: $workspaceDirectory, allowWorkspaceWrites: $allowWorkspaceWrites, objectiveEvidenceContract: $objectiveEvidenceContract, retryUntilGreenConfig: $retryUntilGreenConfig, planArtifact: $planArtifact, intervalValue: $intervalValue, intervalUnit: $intervalUnit, scheduleMode: $scheduleMode, timeOfDayMinutes: $timeOfDayMinutes, nextRunAt: $nextRunAt, lastRunAt: $lastRunAt, runs: $runs)';
}


}

/// @nodoc
abstract mixin class _$RoutineCopyWith<$Res> implements $RoutineCopyWith<$Res> {
  factory _$RoutineCopyWith(_Routine value, $Res Function(_Routine) _then) = __$RoutineCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String prompt, DateTime createdAt, DateTime updatedAt, bool enabled, bool notifyOnCompletion, bool toolsEnabled,@JsonKey(unknownEnumValue: RoutineCompletionAction.none) RoutineCompletionAction completionAction,@JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure) RoutineGoogleChatRule googleChatRule, String workspaceDirectory, bool allowWorkspaceWrites, RoutineObjectiveEvidenceContract? objectiveEvidenceContract, RoutineRetryUntilGreenConfig? retryUntilGreenConfig,@JsonKey(fromJson: _routinePlanArtifactFromJson, toJson: _routinePlanArtifactToJson) RoutinePlanArtifact? planArtifact, int intervalValue,@JsonKey(unknownEnumValue: RoutineIntervalUnit.hours) RoutineIntervalUnit intervalUnit,@JsonKey(unknownEnumValue: RoutineScheduleMode.interval) RoutineScheduleMode scheduleMode, int timeOfDayMinutes, DateTime? nextRunAt, DateTime? lastRunAt, List<RoutineRunRecord> runs
});


@override $RoutineObjectiveEvidenceContractCopyWith<$Res>? get objectiveEvidenceContract;@override $RoutineRetryUntilGreenConfigCopyWith<$Res>? get retryUntilGreenConfig;@override $RoutinePlanArtifactCopyWith<$Res>? get planArtifact;

}
/// @nodoc
class __$RoutineCopyWithImpl<$Res>
    implements _$RoutineCopyWith<$Res> {
  __$RoutineCopyWithImpl(this._self, this._then);

  final _Routine _self;
  final $Res Function(_Routine) _then;

/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? createdAt = null,Object? updatedAt = null,Object? enabled = null,Object? notifyOnCompletion = null,Object? toolsEnabled = null,Object? completionAction = null,Object? googleChatRule = null,Object? workspaceDirectory = null,Object? allowWorkspaceWrites = null,Object? objectiveEvidenceContract = freezed,Object? retryUntilGreenConfig = freezed,Object? planArtifact = freezed,Object? intervalValue = null,Object? intervalUnit = null,Object? scheduleMode = null,Object? timeOfDayMinutes = null,Object? nextRunAt = freezed,Object? lastRunAt = freezed,Object? runs = null,}) {
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
as bool,objectiveEvidenceContract: freezed == objectiveEvidenceContract ? _self.objectiveEvidenceContract : objectiveEvidenceContract // ignore: cast_nullable_to_non_nullable
as RoutineObjectiveEvidenceContract?,retryUntilGreenConfig: freezed == retryUntilGreenConfig ? _self.retryUntilGreenConfig : retryUntilGreenConfig // ignore: cast_nullable_to_non_nullable
as RoutineRetryUntilGreenConfig?,planArtifact: freezed == planArtifact ? _self.planArtifact : planArtifact // ignore: cast_nullable_to_non_nullable
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
$RoutineObjectiveEvidenceContractCopyWith<$Res>? get objectiveEvidenceContract {
    if (_self.objectiveEvidenceContract == null) {
    return null;
  }

  return $RoutineObjectiveEvidenceContractCopyWith<$Res>(_self.objectiveEvidenceContract!, (value) {
    return _then(_self.copyWith(objectiveEvidenceContract: value));
  });
}/// Create a copy of Routine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoutineRetryUntilGreenConfigCopyWith<$Res>? get retryUntilGreenConfig {
    if (_self.retryUntilGreenConfig == null) {
    return null;
  }

  return $RoutineRetryUntilGreenConfigCopyWith<$Res>(_self.retryUntilGreenConfig!, (value) {
    return _then(_self.copyWith(retryUntilGreenConfig: value));
  });
}/// Create a copy of Routine
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
