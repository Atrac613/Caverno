// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_participant.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ParticipantTurnConfig {

@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin) ParticipantTurnPolicy get turnPolicy;@JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound) ParticipantTurnDepth get depth; int get maxRounds;
/// Create a copy of ParticipantTurnConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParticipantTurnConfigCopyWith<ParticipantTurnConfig> get copyWith => _$ParticipantTurnConfigCopyWithImpl<ParticipantTurnConfig>(this as ParticipantTurnConfig, _$identity);

  /// Serializes this ParticipantTurnConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParticipantTurnConfig&&(identical(other.turnPolicy, turnPolicy) || other.turnPolicy == turnPolicy)&&(identical(other.depth, depth) || other.depth == depth)&&(identical(other.maxRounds, maxRounds) || other.maxRounds == maxRounds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,turnPolicy,depth,maxRounds);

@override
String toString() {
  return 'ParticipantTurnConfig(turnPolicy: $turnPolicy, depth: $depth, maxRounds: $maxRounds)';
}


}

/// @nodoc
abstract mixin class $ParticipantTurnConfigCopyWith<$Res>  {
  factory $ParticipantTurnConfigCopyWith(ParticipantTurnConfig value, $Res Function(ParticipantTurnConfig) _then) = _$ParticipantTurnConfigCopyWithImpl;
@useResult
$Res call({
@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin) ParticipantTurnPolicy turnPolicy,@JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound) ParticipantTurnDepth depth, int maxRounds
});




}
/// @nodoc
class _$ParticipantTurnConfigCopyWithImpl<$Res>
    implements $ParticipantTurnConfigCopyWith<$Res> {
  _$ParticipantTurnConfigCopyWithImpl(this._self, this._then);

  final ParticipantTurnConfig _self;
  final $Res Function(ParticipantTurnConfig) _then;

/// Create a copy of ParticipantTurnConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? turnPolicy = null,Object? depth = null,Object? maxRounds = null,}) {
  return _then(_self.copyWith(
turnPolicy: null == turnPolicy ? _self.turnPolicy : turnPolicy // ignore: cast_nullable_to_non_nullable
as ParticipantTurnPolicy,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as ParticipantTurnDepth,maxRounds: null == maxRounds ? _self.maxRounds : maxRounds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ParticipantTurnConfig].
extension ParticipantTurnConfigPatterns on ParticipantTurnConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParticipantTurnConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParticipantTurnConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParticipantTurnConfig value)  $default,){
final _that = this;
switch (_that) {
case _ParticipantTurnConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParticipantTurnConfig value)?  $default,){
final _that = this;
switch (_that) {
case _ParticipantTurnConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin)  ParticipantTurnPolicy turnPolicy, @JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound)  ParticipantTurnDepth depth,  int maxRounds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParticipantTurnConfig() when $default != null:
return $default(_that.turnPolicy,_that.depth,_that.maxRounds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin)  ParticipantTurnPolicy turnPolicy, @JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound)  ParticipantTurnDepth depth,  int maxRounds)  $default,) {final _that = this;
switch (_that) {
case _ParticipantTurnConfig():
return $default(_that.turnPolicy,_that.depth,_that.maxRounds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin)  ParticipantTurnPolicy turnPolicy, @JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound)  ParticipantTurnDepth depth,  int maxRounds)?  $default,) {final _that = this;
switch (_that) {
case _ParticipantTurnConfig() when $default != null:
return $default(_that.turnPolicy,_that.depth,_that.maxRounds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ParticipantTurnConfig implements ParticipantTurnConfig {
  const _ParticipantTurnConfig({@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin) this.turnPolicy = ParticipantTurnPolicy.roundRobin, @JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound) this.depth = ParticipantTurnDepth.singleRound, this.maxRounds = 2});
  factory _ParticipantTurnConfig.fromJson(Map<String, dynamic> json) => _$ParticipantTurnConfigFromJson(json);

@override@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin) final  ParticipantTurnPolicy turnPolicy;
@override@JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound) final  ParticipantTurnDepth depth;
@override@JsonKey() final  int maxRounds;

/// Create a copy of ParticipantTurnConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParticipantTurnConfigCopyWith<_ParticipantTurnConfig> get copyWith => __$ParticipantTurnConfigCopyWithImpl<_ParticipantTurnConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ParticipantTurnConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParticipantTurnConfig&&(identical(other.turnPolicy, turnPolicy) || other.turnPolicy == turnPolicy)&&(identical(other.depth, depth) || other.depth == depth)&&(identical(other.maxRounds, maxRounds) || other.maxRounds == maxRounds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,turnPolicy,depth,maxRounds);

@override
String toString() {
  return 'ParticipantTurnConfig(turnPolicy: $turnPolicy, depth: $depth, maxRounds: $maxRounds)';
}


}

/// @nodoc
abstract mixin class _$ParticipantTurnConfigCopyWith<$Res> implements $ParticipantTurnConfigCopyWith<$Res> {
  factory _$ParticipantTurnConfigCopyWith(_ParticipantTurnConfig value, $Res Function(_ParticipantTurnConfig) _then) = __$ParticipantTurnConfigCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin) ParticipantTurnPolicy turnPolicy,@JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound) ParticipantTurnDepth depth, int maxRounds
});




}
/// @nodoc
class __$ParticipantTurnConfigCopyWithImpl<$Res>
    implements _$ParticipantTurnConfigCopyWith<$Res> {
  __$ParticipantTurnConfigCopyWithImpl(this._self, this._then);

  final _ParticipantTurnConfig _self;
  final $Res Function(_ParticipantTurnConfig) _then;

/// Create a copy of ParticipantTurnConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? turnPolicy = null,Object? depth = null,Object? maxRounds = null,}) {
  return _then(_ParticipantTurnConfig(
turnPolicy: null == turnPolicy ? _self.turnPolicy : turnPolicy // ignore: cast_nullable_to_non_nullable
as ParticipantTurnPolicy,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as ParticipantTurnDepth,maxRounds: null == maxRounds ? _self.maxRounds : maxRounds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ConversationParticipant {

 String get id; String get displayName; String get roleLabel; String get roleSystemPrompt; String get endpointId; String get model;@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode get toolApprovalMode; bool get toolsEnabled; int get colorValue; int get order; bool get enabled;
/// Create a copy of ConversationParticipant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationParticipantCopyWith<ConversationParticipant> get copyWith => _$ConversationParticipantCopyWithImpl<ConversationParticipant>(this as ConversationParticipant, _$identity);

  /// Serializes this ConversationParticipant to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationParticipant&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.roleLabel, roleLabel) || other.roleLabel == roleLabel)&&(identical(other.roleSystemPrompt, roleSystemPrompt) || other.roleSystemPrompt == roleSystemPrompt)&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId)&&(identical(other.model, model) || other.model == model)&&(identical(other.toolApprovalMode, toolApprovalMode) || other.toolApprovalMode == toolApprovalMode)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.colorValue, colorValue) || other.colorValue == colorValue)&&(identical(other.order, order) || other.order == order)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,roleLabel,roleSystemPrompt,endpointId,model,toolApprovalMode,toolsEnabled,colorValue,order,enabled);

@override
String toString() {
  return 'ConversationParticipant(id: $id, displayName: $displayName, roleLabel: $roleLabel, roleSystemPrompt: $roleSystemPrompt, endpointId: $endpointId, model: $model, toolApprovalMode: $toolApprovalMode, toolsEnabled: $toolsEnabled, colorValue: $colorValue, order: $order, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class $ConversationParticipantCopyWith<$Res>  {
  factory $ConversationParticipantCopyWith(ConversationParticipant value, $Res Function(ConversationParticipant) _then) = _$ConversationParticipantCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, String roleLabel, String roleSystemPrompt, String endpointId, String model,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode toolApprovalMode, bool toolsEnabled, int colorValue, int order, bool enabled
});




}
/// @nodoc
class _$ConversationParticipantCopyWithImpl<$Res>
    implements $ConversationParticipantCopyWith<$Res> {
  _$ConversationParticipantCopyWithImpl(this._self, this._then);

  final ConversationParticipant _self;
  final $Res Function(ConversationParticipant) _then;

/// Create a copy of ConversationParticipant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? roleLabel = null,Object? roleSystemPrompt = null,Object? endpointId = null,Object? model = null,Object? toolApprovalMode = null,Object? toolsEnabled = null,Object? colorValue = null,Object? order = null,Object? enabled = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,roleLabel: null == roleLabel ? _self.roleLabel : roleLabel // ignore: cast_nullable_to_non_nullable
as String,roleSystemPrompt: null == roleSystemPrompt ? _self.roleSystemPrompt : roleSystemPrompt // ignore: cast_nullable_to_non_nullable
as String,endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,toolApprovalMode: null == toolApprovalMode ? _self.toolApprovalMode : toolApprovalMode // ignore: cast_nullable_to_non_nullable
as ToolApprovalMode,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,colorValue: null == colorValue ? _self.colorValue : colorValue // ignore: cast_nullable_to_non_nullable
as int,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationParticipant].
extension ConversationParticipantPatterns on ConversationParticipant {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationParticipant value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationParticipant() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationParticipant value)  $default,){
final _that = this;
switch (_that) {
case _ConversationParticipant():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationParticipant value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationParticipant() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  String roleLabel,  String roleSystemPrompt,  String endpointId,  String model, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode toolApprovalMode,  bool toolsEnabled,  int colorValue,  int order,  bool enabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationParticipant() when $default != null:
return $default(_that.id,_that.displayName,_that.roleLabel,_that.roleSystemPrompt,_that.endpointId,_that.model,_that.toolApprovalMode,_that.toolsEnabled,_that.colorValue,_that.order,_that.enabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  String roleLabel,  String roleSystemPrompt,  String endpointId,  String model, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode toolApprovalMode,  bool toolsEnabled,  int colorValue,  int order,  bool enabled)  $default,) {final _that = this;
switch (_that) {
case _ConversationParticipant():
return $default(_that.id,_that.displayName,_that.roleLabel,_that.roleSystemPrompt,_that.endpointId,_that.model,_that.toolApprovalMode,_that.toolsEnabled,_that.colorValue,_that.order,_that.enabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  String roleLabel,  String roleSystemPrompt,  String endpointId,  String model, @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)  ToolApprovalMode toolApprovalMode,  bool toolsEnabled,  int colorValue,  int order,  bool enabled)?  $default,) {final _that = this;
switch (_that) {
case _ConversationParticipant() when $default != null:
return $default(_that.id,_that.displayName,_that.roleLabel,_that.roleSystemPrompt,_that.endpointId,_that.model,_that.toolApprovalMode,_that.toolsEnabled,_that.colorValue,_that.order,_that.enabled);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationParticipant extends ConversationParticipant {
  const _ConversationParticipant({required this.id, this.displayName = '', this.roleLabel = '', this.roleSystemPrompt = '', this.endpointId = '', this.model = '', @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) this.toolApprovalMode = ToolApprovalMode.defaultPermissions, this.toolsEnabled = false, this.colorValue = 0xFF6750A4, this.order = 0, this.enabled = true}): super._();
  factory _ConversationParticipant.fromJson(Map<String, dynamic> json) => _$ConversationParticipantFromJson(json);

@override final  String id;
@override@JsonKey() final  String displayName;
@override@JsonKey() final  String roleLabel;
@override@JsonKey() final  String roleSystemPrompt;
@override@JsonKey() final  String endpointId;
@override@JsonKey() final  String model;
@override@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) final  ToolApprovalMode toolApprovalMode;
@override@JsonKey() final  bool toolsEnabled;
@override@JsonKey() final  int colorValue;
@override@JsonKey() final  int order;
@override@JsonKey() final  bool enabled;

/// Create a copy of ConversationParticipant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationParticipantCopyWith<_ConversationParticipant> get copyWith => __$ConversationParticipantCopyWithImpl<_ConversationParticipant>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationParticipantToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationParticipant&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.roleLabel, roleLabel) || other.roleLabel == roleLabel)&&(identical(other.roleSystemPrompt, roleSystemPrompt) || other.roleSystemPrompt == roleSystemPrompt)&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId)&&(identical(other.model, model) || other.model == model)&&(identical(other.toolApprovalMode, toolApprovalMode) || other.toolApprovalMode == toolApprovalMode)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.colorValue, colorValue) || other.colorValue == colorValue)&&(identical(other.order, order) || other.order == order)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,roleLabel,roleSystemPrompt,endpointId,model,toolApprovalMode,toolsEnabled,colorValue,order,enabled);

@override
String toString() {
  return 'ConversationParticipant(id: $id, displayName: $displayName, roleLabel: $roleLabel, roleSystemPrompt: $roleSystemPrompt, endpointId: $endpointId, model: $model, toolApprovalMode: $toolApprovalMode, toolsEnabled: $toolsEnabled, colorValue: $colorValue, order: $order, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class _$ConversationParticipantCopyWith<$Res> implements $ConversationParticipantCopyWith<$Res> {
  factory _$ConversationParticipantCopyWith(_ConversationParticipant value, $Res Function(_ConversationParticipant) _then) = __$ConversationParticipantCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String roleLabel, String roleSystemPrompt, String endpointId, String model,@JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions) ToolApprovalMode toolApprovalMode, bool toolsEnabled, int colorValue, int order, bool enabled
});




}
/// @nodoc
class __$ConversationParticipantCopyWithImpl<$Res>
    implements _$ConversationParticipantCopyWith<$Res> {
  __$ConversationParticipantCopyWithImpl(this._self, this._then);

  final _ConversationParticipant _self;
  final $Res Function(_ConversationParticipant) _then;

/// Create a copy of ConversationParticipant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? roleLabel = null,Object? roleSystemPrompt = null,Object? endpointId = null,Object? model = null,Object? toolApprovalMode = null,Object? toolsEnabled = null,Object? colorValue = null,Object? order = null,Object? enabled = null,}) {
  return _then(_ConversationParticipant(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,roleLabel: null == roleLabel ? _self.roleLabel : roleLabel // ignore: cast_nullable_to_non_nullable
as String,roleSystemPrompt: null == roleSystemPrompt ? _self.roleSystemPrompt : roleSystemPrompt // ignore: cast_nullable_to_non_nullable
as String,endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,toolApprovalMode: null == toolApprovalMode ? _self.toolApprovalMode : toolApprovalMode // ignore: cast_nullable_to_non_nullable
as ToolApprovalMode,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,colorValue: null == colorValue ? _self.colorValue : colorValue // ignore: cast_nullable_to_non_nullable
as int,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
