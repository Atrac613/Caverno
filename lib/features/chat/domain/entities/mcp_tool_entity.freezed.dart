// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp_tool_entity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$McpToolEntity {

 String get name; String get description; Map<String, dynamic> get inputSchema; String? get originalName; String? get sourceUrl;
/// Create a copy of McpToolEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpToolEntityCopyWith<McpToolEntity> get copyWith => _$McpToolEntityCopyWithImpl<McpToolEntity>(this as McpToolEntity, _$identity);

  /// Serializes this McpToolEntity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as McpToolEntity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpToolEntity&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.inputSchema, _this.inputSchema)&&(identical(other.originalName, _this.originalName) || other.originalName == _this.originalName)&&(identical(other.sourceUrl, _this.sourceUrl) || other.sourceUrl == _this.sourceUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as McpToolEntity;
  return Object.hash(runtimeType,_this.name,_this.description,const DeepCollectionEquality().hash(_this.inputSchema),_this.originalName,_this.sourceUrl);
}

@override
String toString() {
  final _this = this as McpToolEntity;
  return 'McpToolEntity(name: ${_this.name}, description: ${_this.description}, inputSchema: ${_this.inputSchema}, originalName: ${_this.originalName}, sourceUrl: ${_this.sourceUrl})';
}


}

/// @nodoc
abstract mixin class $McpToolEntityCopyWith<$Res>  {
  factory $McpToolEntityCopyWith(McpToolEntity value, $Res Function(McpToolEntity) _then) = _$McpToolEntityCopyWithImpl;
@useResult
$Res call({
 String name, String description, Map<String, dynamic> inputSchema, String? originalName, String? sourceUrl
});




}
/// @nodoc
class _$McpToolEntityCopyWithImpl<$Res>
    implements $McpToolEntityCopyWith<$Res> {
  _$McpToolEntityCopyWithImpl(this._self, this._then);

  final McpToolEntity _self;
  final $Res Function(McpToolEntity) _then;

/// Create a copy of McpToolEntity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? description = null,Object? inputSchema = null,Object? originalName = freezed,Object? sourceUrl = freezed,}) {
  return _then(McpToolEntity(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,inputSchema: null == inputSchema ? _self.inputSchema : inputSchema // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,originalName: freezed == originalName ? _self.originalName : originalName // ignore: cast_nullable_to_non_nullable
as String?,sourceUrl: freezed == sourceUrl ? _self.sourceUrl : sourceUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [McpToolEntity].
extension McpToolEntityPatterns on McpToolEntity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpToolEntity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpToolEntity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpToolEntity value)  $default,){
final _that = this;
switch (_that) {
case _McpToolEntity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpToolEntity value)?  $default,){
final _that = this;
switch (_that) {
case _McpToolEntity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String description,  Map<String, dynamic> inputSchema,  String? originalName,  String? sourceUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpToolEntity() when $default != null:
return $default(_that.name,_that.description,_that.inputSchema,_that.originalName,_that.sourceUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String description,  Map<String, dynamic> inputSchema,  String? originalName,  String? sourceUrl)  $default,) {final _that = this;
switch (_that) {
case _McpToolEntity():
return $default(_that.name,_that.description,_that.inputSchema,_that.originalName,_that.sourceUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String description,  Map<String, dynamic> inputSchema,  String? originalName,  String? sourceUrl)?  $default,) {final _that = this;
switch (_that) {
case _McpToolEntity() when $default != null:
return $default(_that.name,_that.description,_that.inputSchema,_that.originalName,_that.sourceUrl);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _McpToolEntity extends McpToolEntity {
  const _McpToolEntity({required this.name, required this.description, required  Map<String, dynamic> inputSchema, this.originalName, this.sourceUrl}): _inputSchema = inputSchema,super._();
  factory _McpToolEntity.fromJson(Map<String, dynamic> json) => _$McpToolEntityFromJson(json);

@override final  String name;
@override final  String description;
 final  Map<String, dynamic> _inputSchema;
@override Map<String, dynamic> get inputSchema {
  if (_inputSchema is EqualUnmodifiableMapView) return _inputSchema;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_inputSchema);
}

@override final  String? originalName;
@override final  String? sourceUrl;

/// Create a copy of McpToolEntity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpToolEntityCopyWith<_McpToolEntity> get copyWith => __$McpToolEntityCopyWithImpl<_McpToolEntity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$McpToolEntityToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpToolEntity&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.inputSchema, _inputSchema)&&(identical(other.originalName, originalName) || other.originalName == originalName)&&(identical(other.sourceUrl, sourceUrl) || other.sourceUrl == sourceUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,description,const DeepCollectionEquality().hash(_inputSchema),originalName,sourceUrl);
}

@override
String toString() {
    return 'McpToolEntity(name: $name, description: $description, inputSchema: $inputSchema, originalName: $originalName, sourceUrl: $sourceUrl)';
}


}

/// @nodoc
abstract mixin class _$McpToolEntityCopyWith<$Res> implements $McpToolEntityCopyWith<$Res> {
  factory _$McpToolEntityCopyWith(_McpToolEntity value, $Res Function(_McpToolEntity) _then) = __$McpToolEntityCopyWithImpl;
@override @useResult
$Res call({
 String name, String description, Map<String, dynamic> inputSchema, String? originalName, String? sourceUrl
});




}
/// @nodoc
class __$McpToolEntityCopyWithImpl<$Res>
    implements _$McpToolEntityCopyWith<$Res> {
  __$McpToolEntityCopyWithImpl(this._self, this._then);

  final _McpToolEntity _self;
  final $Res Function(_McpToolEntity) _then;

/// Create a copy of McpToolEntity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? description = null,Object? inputSchema = null,Object? originalName = freezed,Object? sourceUrl = freezed,}) {
  return _then(_McpToolEntity(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,inputSchema: null == inputSchema ? _self._inputSchema : inputSchema // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,originalName: freezed == originalName ? _self.originalName : originalName // ignore: cast_nullable_to_non_nullable
as String?,sourceUrl: freezed == sourceUrl ? _self.sourceUrl : sourceUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$McpToolResult {

 String get toolName; String get result; bool get isSuccess;@JsonKey(includeFromJson: false, includeToJson: false) bool get isExternalMcpResult; String? get errorMessage;/// Structured facts a first-party tool reported about its own execution.
///
/// Null for third-party MCP results, which stay opaque text: only tools
/// Caverno implements can be trusted to describe their own outcome. It is
/// runtime-only for the same reason `isExternalMcpResult` is — consumers
/// read it while a turn runs, and a persisted copy could outlive the facts
/// it describes. See LL34 in `docs/local_llm_agent_roadmap.md`.
@JsonKey(includeFromJson: false, includeToJson: false) ToolOutcome? get outcome;
/// Create a copy of McpToolResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpToolResultCopyWith<McpToolResult> get copyWith => _$McpToolResultCopyWithImpl<McpToolResult>(this as McpToolResult, _$identity);

  /// Serializes this McpToolResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as McpToolResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpToolResult&&(identical(other.toolName, _this.toolName) || other.toolName == _this.toolName)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.isSuccess, _this.isSuccess) || other.isSuccess == _this.isSuccess)&&(identical(other.isExternalMcpResult, _this.isExternalMcpResult) || other.isExternalMcpResult == _this.isExternalMcpResult)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as McpToolResult;
  return Object.hash(runtimeType,_this.toolName,_this.result,_this.isSuccess,_this.isExternalMcpResult,_this.errorMessage,_this.outcome);
}

@override
String toString() {
  final _this = this as McpToolResult;
  return 'McpToolResult(toolName: ${_this.toolName}, result: ${_this.result}, isSuccess: ${_this.isSuccess}, isExternalMcpResult: ${_this.isExternalMcpResult}, errorMessage: ${_this.errorMessage}, outcome: ${_this.outcome})';
}


}

/// @nodoc
abstract mixin class $McpToolResultCopyWith<$Res>  {
  factory $McpToolResultCopyWith(McpToolResult value, $Res Function(McpToolResult) _then) = _$McpToolResultCopyWithImpl;
@useResult
$Res call({
 String toolName, String result, bool isSuccess,@JsonKey(includeFromJson: false, includeToJson: false) bool isExternalMcpResult, String? errorMessage,@JsonKey(includeFromJson: false, includeToJson: false) ToolOutcome? outcome
});




}
/// @nodoc
class _$McpToolResultCopyWithImpl<$Res>
    implements $McpToolResultCopyWith<$Res> {
  _$McpToolResultCopyWithImpl(this._self, this._then);

  final McpToolResult _self;
  final $Res Function(McpToolResult) _then;

/// Create a copy of McpToolResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? toolName = null,Object? result = null,Object? isSuccess = null,Object? isExternalMcpResult = null,Object? errorMessage = freezed,Object? outcome = freezed,}) {
  return _then(McpToolResult(
toolName: null == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,isSuccess: null == isSuccess ? _self.isSuccess : isSuccess // ignore: cast_nullable_to_non_nullable
as bool,isExternalMcpResult: null == isExternalMcpResult ? _self.isExternalMcpResult : isExternalMcpResult // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ToolOutcome?,
  ));
}

}


/// Adds pattern-matching-related methods to [McpToolResult].
extension McpToolResultPatterns on McpToolResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpToolResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpToolResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpToolResult value)  $default,){
final _that = this;
switch (_that) {
case _McpToolResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpToolResult value)?  $default,){
final _that = this;
switch (_that) {
case _McpToolResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String toolName,  String result,  bool isSuccess, @JsonKey(includeFromJson: false, includeToJson: false)  bool isExternalMcpResult,  String? errorMessage, @JsonKey(includeFromJson: false, includeToJson: false)  ToolOutcome? outcome)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpToolResult() when $default != null:
return $default(_that.toolName,_that.result,_that.isSuccess,_that.isExternalMcpResult,_that.errorMessage,_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String toolName,  String result,  bool isSuccess, @JsonKey(includeFromJson: false, includeToJson: false)  bool isExternalMcpResult,  String? errorMessage, @JsonKey(includeFromJson: false, includeToJson: false)  ToolOutcome? outcome)  $default,) {final _that = this;
switch (_that) {
case _McpToolResult():
return $default(_that.toolName,_that.result,_that.isSuccess,_that.isExternalMcpResult,_that.errorMessage,_that.outcome);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String toolName,  String result,  bool isSuccess, @JsonKey(includeFromJson: false, includeToJson: false)  bool isExternalMcpResult,  String? errorMessage, @JsonKey(includeFromJson: false, includeToJson: false)  ToolOutcome? outcome)?  $default,) {final _that = this;
switch (_that) {
case _McpToolResult() when $default != null:
return $default(_that.toolName,_that.result,_that.isSuccess,_that.isExternalMcpResult,_that.errorMessage,_that.outcome);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _McpToolResult implements McpToolResult {
  const _McpToolResult({required this.toolName, required this.result, required this.isSuccess, @JsonKey(includeFromJson: false, includeToJson: false) this.isExternalMcpResult = false, this.errorMessage, @JsonKey(includeFromJson: false, includeToJson: false) this.outcome});
  factory _McpToolResult.fromJson(Map<String, dynamic> json) => _$McpToolResultFromJson(json);

@override final  String toolName;
@override final  String result;
@override final  bool isSuccess;
@override@JsonKey(includeFromJson: false, includeToJson: false) final  bool isExternalMcpResult;
@override final  String? errorMessage;
/// Structured facts a first-party tool reported about its own execution.
///
/// Null for third-party MCP results, which stay opaque text: only tools
/// Caverno implements can be trusted to describe their own outcome. It is
/// runtime-only for the same reason `isExternalMcpResult` is — consumers
/// read it while a turn runs, and a persisted copy could outlive the facts
/// it describes. See LL34 in `docs/local_llm_agent_roadmap.md`.
@override@JsonKey(includeFromJson: false, includeToJson: false) final  ToolOutcome? outcome;

/// Create a copy of McpToolResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpToolResultCopyWith<_McpToolResult> get copyWith => __$McpToolResultCopyWithImpl<_McpToolResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$McpToolResultToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpToolResult&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.result, result) || other.result == result)&&(identical(other.isSuccess, isSuccess) || other.isSuccess == isSuccess)&&(identical(other.isExternalMcpResult, isExternalMcpResult) || other.isExternalMcpResult == isExternalMcpResult)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.outcome, outcome) || other.outcome == outcome));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,toolName,result,isSuccess,isExternalMcpResult,errorMessage,outcome);
}

@override
String toString() {
    return 'McpToolResult(toolName: $toolName, result: $result, isSuccess: $isSuccess, isExternalMcpResult: $isExternalMcpResult, errorMessage: $errorMessage, outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class _$McpToolResultCopyWith<$Res> implements $McpToolResultCopyWith<$Res> {
  factory _$McpToolResultCopyWith(_McpToolResult value, $Res Function(_McpToolResult) _then) = __$McpToolResultCopyWithImpl;
@override @useResult
$Res call({
 String toolName, String result, bool isSuccess,@JsonKey(includeFromJson: false, includeToJson: false) bool isExternalMcpResult, String? errorMessage,@JsonKey(includeFromJson: false, includeToJson: false) ToolOutcome? outcome
});




}
/// @nodoc
class __$McpToolResultCopyWithImpl<$Res>
    implements _$McpToolResultCopyWith<$Res> {
  __$McpToolResultCopyWithImpl(this._self, this._then);

  final _McpToolResult _self;
  final $Res Function(_McpToolResult) _then;

/// Create a copy of McpToolResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? toolName = null,Object? result = null,Object? isSuccess = null,Object? isExternalMcpResult = null,Object? errorMessage = freezed,Object? outcome = freezed,}) {
  return _then(_McpToolResult(
toolName: null == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,isSuccess: null == isSuccess ? _self.isSuccess : isSuccess // ignore: cast_nullable_to_non_nullable
as bool,isExternalMcpResult: null == isExternalMcpResult ? _self.isExternalMcpResult : isExternalMcpResult // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ToolOutcome?,
  ));
}


}

// dart format on
