// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_goal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConversationGoal {

 String get id; String get objective; bool get enabled; bool get autoContinue;@JsonKey(unknownEnumValue: ConversationGoalStatus.active) ConversationGoalStatus get status; int get tokenBudget; int get tokenUsage; int get turnBudget; int get turnsUsed; String get completionSummary; String get blockedReason; String get blockerSignature; int get blockerRepeatCount; DateTime get createdAt; DateTime get updatedAt; DateTime? get completedAt; DateTime? get blockedAt; DateTime? get lastBlockerSeenAt;
/// Create a copy of ConversationGoal
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationGoalCopyWith<ConversationGoal> get copyWith => _$ConversationGoalCopyWithImpl<ConversationGoal>(this as ConversationGoal, _$identity);

  /// Serializes this ConversationGoal to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationGoal&&(identical(other.id, id) || other.id == id)&&(identical(other.objective, objective) || other.objective == objective)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.autoContinue, autoContinue) || other.autoContinue == autoContinue)&&(identical(other.status, status) || other.status == status)&&(identical(other.tokenBudget, tokenBudget) || other.tokenBudget == tokenBudget)&&(identical(other.tokenUsage, tokenUsage) || other.tokenUsage == tokenUsage)&&(identical(other.turnBudget, turnBudget) || other.turnBudget == turnBudget)&&(identical(other.turnsUsed, turnsUsed) || other.turnsUsed == turnsUsed)&&(identical(other.completionSummary, completionSummary) || other.completionSummary == completionSummary)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.blockerSignature, blockerSignature) || other.blockerSignature == blockerSignature)&&(identical(other.blockerRepeatCount, blockerRepeatCount) || other.blockerRepeatCount == blockerRepeatCount)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.blockedAt, blockedAt) || other.blockedAt == blockedAt)&&(identical(other.lastBlockerSeenAt, lastBlockerSeenAt) || other.lastBlockerSeenAt == lastBlockerSeenAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,objective,enabled,autoContinue,status,tokenBudget,tokenUsage,turnBudget,turnsUsed,completionSummary,blockedReason,blockerSignature,blockerRepeatCount,createdAt,updatedAt,completedAt,blockedAt,lastBlockerSeenAt);

@override
String toString() {
  return 'ConversationGoal(id: $id, objective: $objective, enabled: $enabled, autoContinue: $autoContinue, status: $status, tokenBudget: $tokenBudget, tokenUsage: $tokenUsage, turnBudget: $turnBudget, turnsUsed: $turnsUsed, completionSummary: $completionSummary, blockedReason: $blockedReason, blockerSignature: $blockerSignature, blockerRepeatCount: $blockerRepeatCount, createdAt: $createdAt, updatedAt: $updatedAt, completedAt: $completedAt, blockedAt: $blockedAt, lastBlockerSeenAt: $lastBlockerSeenAt)';
}


}

/// @nodoc
abstract mixin class $ConversationGoalCopyWith<$Res>  {
  factory $ConversationGoalCopyWith(ConversationGoal value, $Res Function(ConversationGoal) _then) = _$ConversationGoalCopyWithImpl;
@useResult
$Res call({
 String id, String objective, bool enabled, bool autoContinue,@JsonKey(unknownEnumValue: ConversationGoalStatus.active) ConversationGoalStatus status, int tokenBudget, int tokenUsage, int turnBudget, int turnsUsed, String completionSummary, String blockedReason, String blockerSignature, int blockerRepeatCount, DateTime createdAt, DateTime updatedAt, DateTime? completedAt, DateTime? blockedAt, DateTime? lastBlockerSeenAt
});




}
/// @nodoc
class _$ConversationGoalCopyWithImpl<$Res>
    implements $ConversationGoalCopyWith<$Res> {
  _$ConversationGoalCopyWithImpl(this._self, this._then);

  final ConversationGoal _self;
  final $Res Function(ConversationGoal) _then;

/// Create a copy of ConversationGoal
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? objective = null,Object? enabled = null,Object? autoContinue = null,Object? status = null,Object? tokenBudget = null,Object? tokenUsage = null,Object? turnBudget = null,Object? turnsUsed = null,Object? completionSummary = null,Object? blockedReason = null,Object? blockerSignature = null,Object? blockerRepeatCount = null,Object? createdAt = null,Object? updatedAt = null,Object? completedAt = freezed,Object? blockedAt = freezed,Object? lastBlockerSeenAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,objective: null == objective ? _self.objective : objective // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,autoContinue: null == autoContinue ? _self.autoContinue : autoContinue // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationGoalStatus,tokenBudget: null == tokenBudget ? _self.tokenBudget : tokenBudget // ignore: cast_nullable_to_non_nullable
as int,tokenUsage: null == tokenUsage ? _self.tokenUsage : tokenUsage // ignore: cast_nullable_to_non_nullable
as int,turnBudget: null == turnBudget ? _self.turnBudget : turnBudget // ignore: cast_nullable_to_non_nullable
as int,turnsUsed: null == turnsUsed ? _self.turnsUsed : turnsUsed // ignore: cast_nullable_to_non_nullable
as int,completionSummary: null == completionSummary ? _self.completionSummary : completionSummary // ignore: cast_nullable_to_non_nullable
as String,blockedReason: null == blockedReason ? _self.blockedReason : blockedReason // ignore: cast_nullable_to_non_nullable
as String,blockerSignature: null == blockerSignature ? _self.blockerSignature : blockerSignature // ignore: cast_nullable_to_non_nullable
as String,blockerRepeatCount: null == blockerRepeatCount ? _self.blockerRepeatCount : blockerRepeatCount // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,blockedAt: freezed == blockedAt ? _self.blockedAt : blockedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastBlockerSeenAt: freezed == lastBlockerSeenAt ? _self.lastBlockerSeenAt : lastBlockerSeenAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationGoal].
extension ConversationGoalPatterns on ConversationGoal {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationGoal value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationGoal() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationGoal value)  $default,){
final _that = this;
switch (_that) {
case _ConversationGoal():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationGoal value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationGoal() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String objective,  bool enabled,  bool autoContinue, @JsonKey(unknownEnumValue: ConversationGoalStatus.active)  ConversationGoalStatus status,  int tokenBudget,  int tokenUsage,  int turnBudget,  int turnsUsed,  String completionSummary,  String blockedReason,  String blockerSignature,  int blockerRepeatCount,  DateTime createdAt,  DateTime updatedAt,  DateTime? completedAt,  DateTime? blockedAt,  DateTime? lastBlockerSeenAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationGoal() when $default != null:
return $default(_that.id,_that.objective,_that.enabled,_that.autoContinue,_that.status,_that.tokenBudget,_that.tokenUsage,_that.turnBudget,_that.turnsUsed,_that.completionSummary,_that.blockedReason,_that.blockerSignature,_that.blockerRepeatCount,_that.createdAt,_that.updatedAt,_that.completedAt,_that.blockedAt,_that.lastBlockerSeenAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String objective,  bool enabled,  bool autoContinue, @JsonKey(unknownEnumValue: ConversationGoalStatus.active)  ConversationGoalStatus status,  int tokenBudget,  int tokenUsage,  int turnBudget,  int turnsUsed,  String completionSummary,  String blockedReason,  String blockerSignature,  int blockerRepeatCount,  DateTime createdAt,  DateTime updatedAt,  DateTime? completedAt,  DateTime? blockedAt,  DateTime? lastBlockerSeenAt)  $default,) {final _that = this;
switch (_that) {
case _ConversationGoal():
return $default(_that.id,_that.objective,_that.enabled,_that.autoContinue,_that.status,_that.tokenBudget,_that.tokenUsage,_that.turnBudget,_that.turnsUsed,_that.completionSummary,_that.blockedReason,_that.blockerSignature,_that.blockerRepeatCount,_that.createdAt,_that.updatedAt,_that.completedAt,_that.blockedAt,_that.lastBlockerSeenAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String objective,  bool enabled,  bool autoContinue, @JsonKey(unknownEnumValue: ConversationGoalStatus.active)  ConversationGoalStatus status,  int tokenBudget,  int tokenUsage,  int turnBudget,  int turnsUsed,  String completionSummary,  String blockedReason,  String blockerSignature,  int blockerRepeatCount,  DateTime createdAt,  DateTime updatedAt,  DateTime? completedAt,  DateTime? blockedAt,  DateTime? lastBlockerSeenAt)?  $default,) {final _that = this;
switch (_that) {
case _ConversationGoal() when $default != null:
return $default(_that.id,_that.objective,_that.enabled,_that.autoContinue,_that.status,_that.tokenBudget,_that.tokenUsage,_that.turnBudget,_that.turnsUsed,_that.completionSummary,_that.blockedReason,_that.blockerSignature,_that.blockerRepeatCount,_that.createdAt,_that.updatedAt,_that.completedAt,_that.blockedAt,_that.lastBlockerSeenAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationGoal extends ConversationGoal {
  const _ConversationGoal({required this.id, this.objective = '', this.enabled = true, this.autoContinue = false, @JsonKey(unknownEnumValue: ConversationGoalStatus.active) this.status = ConversationGoalStatus.active, this.tokenBudget = 0, this.tokenUsage = 0, this.turnBudget = 0, this.turnsUsed = 0, this.completionSummary = '', this.blockedReason = '', this.blockerSignature = '', this.blockerRepeatCount = 0, required this.createdAt, required this.updatedAt, this.completedAt, this.blockedAt, this.lastBlockerSeenAt}): super._();
  factory _ConversationGoal.fromJson(Map<String, dynamic> json) => _$ConversationGoalFromJson(json);

@override final  String id;
@override@JsonKey() final  String objective;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool autoContinue;
@override@JsonKey(unknownEnumValue: ConversationGoalStatus.active) final  ConversationGoalStatus status;
@override@JsonKey() final  int tokenBudget;
@override@JsonKey() final  int tokenUsage;
@override@JsonKey() final  int turnBudget;
@override@JsonKey() final  int turnsUsed;
@override@JsonKey() final  String completionSummary;
@override@JsonKey() final  String blockedReason;
@override@JsonKey() final  String blockerSignature;
@override@JsonKey() final  int blockerRepeatCount;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? completedAt;
@override final  DateTime? blockedAt;
@override final  DateTime? lastBlockerSeenAt;

/// Create a copy of ConversationGoal
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationGoalCopyWith<_ConversationGoal> get copyWith => __$ConversationGoalCopyWithImpl<_ConversationGoal>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationGoalToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationGoal&&(identical(other.id, id) || other.id == id)&&(identical(other.objective, objective) || other.objective == objective)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.autoContinue, autoContinue) || other.autoContinue == autoContinue)&&(identical(other.status, status) || other.status == status)&&(identical(other.tokenBudget, tokenBudget) || other.tokenBudget == tokenBudget)&&(identical(other.tokenUsage, tokenUsage) || other.tokenUsage == tokenUsage)&&(identical(other.turnBudget, turnBudget) || other.turnBudget == turnBudget)&&(identical(other.turnsUsed, turnsUsed) || other.turnsUsed == turnsUsed)&&(identical(other.completionSummary, completionSummary) || other.completionSummary == completionSummary)&&(identical(other.blockedReason, blockedReason) || other.blockedReason == blockedReason)&&(identical(other.blockerSignature, blockerSignature) || other.blockerSignature == blockerSignature)&&(identical(other.blockerRepeatCount, blockerRepeatCount) || other.blockerRepeatCount == blockerRepeatCount)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.blockedAt, blockedAt) || other.blockedAt == blockedAt)&&(identical(other.lastBlockerSeenAt, lastBlockerSeenAt) || other.lastBlockerSeenAt == lastBlockerSeenAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,objective,enabled,autoContinue,status,tokenBudget,tokenUsage,turnBudget,turnsUsed,completionSummary,blockedReason,blockerSignature,blockerRepeatCount,createdAt,updatedAt,completedAt,blockedAt,lastBlockerSeenAt);

@override
String toString() {
  return 'ConversationGoal(id: $id, objective: $objective, enabled: $enabled, autoContinue: $autoContinue, status: $status, tokenBudget: $tokenBudget, tokenUsage: $tokenUsage, turnBudget: $turnBudget, turnsUsed: $turnsUsed, completionSummary: $completionSummary, blockedReason: $blockedReason, blockerSignature: $blockerSignature, blockerRepeatCount: $blockerRepeatCount, createdAt: $createdAt, updatedAt: $updatedAt, completedAt: $completedAt, blockedAt: $blockedAt, lastBlockerSeenAt: $lastBlockerSeenAt)';
}


}

/// @nodoc
abstract mixin class _$ConversationGoalCopyWith<$Res> implements $ConversationGoalCopyWith<$Res> {
  factory _$ConversationGoalCopyWith(_ConversationGoal value, $Res Function(_ConversationGoal) _then) = __$ConversationGoalCopyWithImpl;
@override @useResult
$Res call({
 String id, String objective, bool enabled, bool autoContinue,@JsonKey(unknownEnumValue: ConversationGoalStatus.active) ConversationGoalStatus status, int tokenBudget, int tokenUsage, int turnBudget, int turnsUsed, String completionSummary, String blockedReason, String blockerSignature, int blockerRepeatCount, DateTime createdAt, DateTime updatedAt, DateTime? completedAt, DateTime? blockedAt, DateTime? lastBlockerSeenAt
});




}
/// @nodoc
class __$ConversationGoalCopyWithImpl<$Res>
    implements _$ConversationGoalCopyWith<$Res> {
  __$ConversationGoalCopyWithImpl(this._self, this._then);

  final _ConversationGoal _self;
  final $Res Function(_ConversationGoal) _then;

/// Create a copy of ConversationGoal
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? objective = null,Object? enabled = null,Object? autoContinue = null,Object? status = null,Object? tokenBudget = null,Object? tokenUsage = null,Object? turnBudget = null,Object? turnsUsed = null,Object? completionSummary = null,Object? blockedReason = null,Object? blockerSignature = null,Object? blockerRepeatCount = null,Object? createdAt = null,Object? updatedAt = null,Object? completedAt = freezed,Object? blockedAt = freezed,Object? lastBlockerSeenAt = freezed,}) {
  return _then(_ConversationGoal(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,objective: null == objective ? _self.objective : objective // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,autoContinue: null == autoContinue ? _self.autoContinue : autoContinue // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConversationGoalStatus,tokenBudget: null == tokenBudget ? _self.tokenBudget : tokenBudget // ignore: cast_nullable_to_non_nullable
as int,tokenUsage: null == tokenUsage ? _self.tokenUsage : tokenUsage // ignore: cast_nullable_to_non_nullable
as int,turnBudget: null == turnBudget ? _self.turnBudget : turnBudget // ignore: cast_nullable_to_non_nullable
as int,turnsUsed: null == turnsUsed ? _self.turnsUsed : turnsUsed // ignore: cast_nullable_to_non_nullable
as int,completionSummary: null == completionSummary ? _self.completionSummary : completionSummary // ignore: cast_nullable_to_non_nullable
as String,blockedReason: null == blockedReason ? _self.blockedReason : blockedReason // ignore: cast_nullable_to_non_nullable
as String,blockerSignature: null == blockerSignature ? _self.blockerSignature : blockerSignature // ignore: cast_nullable_to_non_nullable
as String,blockerRepeatCount: null == blockerRepeatCount ? _self.blockerRepeatCount : blockerRepeatCount // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,blockedAt: freezed == blockedAt ? _self.blockedAt : blockedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastBlockerSeenAt: freezed == lastBlockerSeenAt ? _self.lastBlockerSeenAt : lastBlockerSeenAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
