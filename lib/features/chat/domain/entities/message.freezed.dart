// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MessageResponseMetrics {

 int get promptTokens; int get completionTokens; int get totalTokens; int get elapsedMilliseconds; String? get finishReason;
/// Create a copy of MessageResponseMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageResponseMetricsCopyWith<MessageResponseMetrics> get copyWith => _$MessageResponseMetricsCopyWithImpl<MessageResponseMetrics>(this as MessageResponseMetrics, _$identity);

  /// Serializes this MessageResponseMetrics to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageResponseMetrics&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.elapsedMilliseconds, elapsedMilliseconds) || other.elapsedMilliseconds == elapsedMilliseconds)&&(identical(other.finishReason, finishReason) || other.finishReason == finishReason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,promptTokens,completionTokens,totalTokens,elapsedMilliseconds,finishReason);

@override
String toString() {
  return 'MessageResponseMetrics(promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, elapsedMilliseconds: $elapsedMilliseconds, finishReason: $finishReason)';
}


}

/// @nodoc
abstract mixin class $MessageResponseMetricsCopyWith<$Res>  {
  factory $MessageResponseMetricsCopyWith(MessageResponseMetrics value, $Res Function(MessageResponseMetrics) _then) = _$MessageResponseMetricsCopyWithImpl;
@useResult
$Res call({
 int promptTokens, int completionTokens, int totalTokens, int elapsedMilliseconds, String? finishReason
});




}
/// @nodoc
class _$MessageResponseMetricsCopyWithImpl<$Res>
    implements $MessageResponseMetricsCopyWith<$Res> {
  _$MessageResponseMetricsCopyWithImpl(this._self, this._then);

  final MessageResponseMetrics _self;
  final $Res Function(MessageResponseMetrics) _then;

/// Create a copy of MessageResponseMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? elapsedMilliseconds = null,Object? finishReason = freezed,}) {
  return _then(_self.copyWith(
promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,elapsedMilliseconds: null == elapsedMilliseconds ? _self.elapsedMilliseconds : elapsedMilliseconds // ignore: cast_nullable_to_non_nullable
as int,finishReason: freezed == finishReason ? _self.finishReason : finishReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MessageResponseMetrics].
extension MessageResponseMetricsPatterns on MessageResponseMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MessageResponseMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MessageResponseMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MessageResponseMetrics value)  $default,){
final _that = this;
switch (_that) {
case _MessageResponseMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MessageResponseMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _MessageResponseMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int promptTokens,  int completionTokens,  int totalTokens,  int elapsedMilliseconds,  String? finishReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MessageResponseMetrics() when $default != null:
return $default(_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.elapsedMilliseconds,_that.finishReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int promptTokens,  int completionTokens,  int totalTokens,  int elapsedMilliseconds,  String? finishReason)  $default,) {final _that = this;
switch (_that) {
case _MessageResponseMetrics():
return $default(_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.elapsedMilliseconds,_that.finishReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int promptTokens,  int completionTokens,  int totalTokens,  int elapsedMilliseconds,  String? finishReason)?  $default,) {final _that = this;
switch (_that) {
case _MessageResponseMetrics() when $default != null:
return $default(_that.promptTokens,_that.completionTokens,_that.totalTokens,_that.elapsedMilliseconds,_that.finishReason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MessageResponseMetrics implements MessageResponseMetrics {
  const _MessageResponseMetrics({this.promptTokens = 0, this.completionTokens = 0, this.totalTokens = 0, this.elapsedMilliseconds = 0, this.finishReason});
  factory _MessageResponseMetrics.fromJson(Map<String, dynamic> json) => _$MessageResponseMetricsFromJson(json);

@override@JsonKey() final  int promptTokens;
@override@JsonKey() final  int completionTokens;
@override@JsonKey() final  int totalTokens;
@override@JsonKey() final  int elapsedMilliseconds;
@override final  String? finishReason;

/// Create a copy of MessageResponseMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessageResponseMetricsCopyWith<_MessageResponseMetrics> get copyWith => __$MessageResponseMetricsCopyWithImpl<_MessageResponseMetrics>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MessageResponseMetricsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MessageResponseMetrics&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.elapsedMilliseconds, elapsedMilliseconds) || other.elapsedMilliseconds == elapsedMilliseconds)&&(identical(other.finishReason, finishReason) || other.finishReason == finishReason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,promptTokens,completionTokens,totalTokens,elapsedMilliseconds,finishReason);

@override
String toString() {
  return 'MessageResponseMetrics(promptTokens: $promptTokens, completionTokens: $completionTokens, totalTokens: $totalTokens, elapsedMilliseconds: $elapsedMilliseconds, finishReason: $finishReason)';
}


}

/// @nodoc
abstract mixin class _$MessageResponseMetricsCopyWith<$Res> implements $MessageResponseMetricsCopyWith<$Res> {
  factory _$MessageResponseMetricsCopyWith(_MessageResponseMetrics value, $Res Function(_MessageResponseMetrics) _then) = __$MessageResponseMetricsCopyWithImpl;
@override @useResult
$Res call({
 int promptTokens, int completionTokens, int totalTokens, int elapsedMilliseconds, String? finishReason
});




}
/// @nodoc
class __$MessageResponseMetricsCopyWithImpl<$Res>
    implements _$MessageResponseMetricsCopyWith<$Res> {
  __$MessageResponseMetricsCopyWithImpl(this._self, this._then);

  final _MessageResponseMetrics _self;
  final $Res Function(_MessageResponseMetrics) _then;

/// Create a copy of MessageResponseMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? promptTokens = null,Object? completionTokens = null,Object? totalTokens = null,Object? elapsedMilliseconds = null,Object? finishReason = freezed,}) {
  return _then(_MessageResponseMetrics(
promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,elapsedMilliseconds: null == elapsedMilliseconds ? _self.elapsedMilliseconds : elapsedMilliseconds // ignore: cast_nullable_to_non_nullable
as int,finishReason: freezed == finishReason ? _self.finishReason : finishReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$Message {

 String get id; String get content; MessageRole get role; DateTime get timestamp; bool get isStreaming; String? get error; String? get imageBase64; String? get imageMimeType; String? get originalImagePath; String? get originalImageMimeType; String? get participantId; String? get participantDisplayName; String? get participantRoleLabel; int? get participantColorValue; List<String> get participantToolNames; String? get handoffTargetParticipantId; String? get handoffTargetDisplayName; String? get handoffTargetRoleLabel; MessageResponseMetrics? get responseMetrics;
/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageCopyWith<Message> get copyWith => _$MessageCopyWithImpl<Message>(this as Message, _$identity);

  /// Serializes this Message to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Message&&(identical(other.id, id) || other.id == id)&&(identical(other.content, content) || other.content == content)&&(identical(other.role, role) || other.role == role)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.isStreaming, isStreaming) || other.isStreaming == isStreaming)&&(identical(other.error, error) || other.error == error)&&(identical(other.imageBase64, imageBase64) || other.imageBase64 == imageBase64)&&(identical(other.imageMimeType, imageMimeType) || other.imageMimeType == imageMimeType)&&(identical(other.originalImagePath, originalImagePath) || other.originalImagePath == originalImagePath)&&(identical(other.originalImageMimeType, originalImageMimeType) || other.originalImageMimeType == originalImageMimeType)&&(identical(other.participantId, participantId) || other.participantId == participantId)&&(identical(other.participantDisplayName, participantDisplayName) || other.participantDisplayName == participantDisplayName)&&(identical(other.participantRoleLabel, participantRoleLabel) || other.participantRoleLabel == participantRoleLabel)&&(identical(other.participantColorValue, participantColorValue) || other.participantColorValue == participantColorValue)&&const DeepCollectionEquality().equals(other.participantToolNames, participantToolNames)&&(identical(other.handoffTargetParticipantId, handoffTargetParticipantId) || other.handoffTargetParticipantId == handoffTargetParticipantId)&&(identical(other.handoffTargetDisplayName, handoffTargetDisplayName) || other.handoffTargetDisplayName == handoffTargetDisplayName)&&(identical(other.handoffTargetRoleLabel, handoffTargetRoleLabel) || other.handoffTargetRoleLabel == handoffTargetRoleLabel)&&(identical(other.responseMetrics, responseMetrics) || other.responseMetrics == responseMetrics));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,content,role,timestamp,isStreaming,error,imageBase64,imageMimeType,originalImagePath,originalImageMimeType,participantId,participantDisplayName,participantRoleLabel,participantColorValue,const DeepCollectionEquality().hash(participantToolNames),handoffTargetParticipantId,handoffTargetDisplayName,handoffTargetRoleLabel,responseMetrics]);

@override
String toString() {
  return 'Message(id: $id, content: $content, role: $role, timestamp: $timestamp, isStreaming: $isStreaming, error: $error, imageBase64: $imageBase64, imageMimeType: $imageMimeType, originalImagePath: $originalImagePath, originalImageMimeType: $originalImageMimeType, participantId: $participantId, participantDisplayName: $participantDisplayName, participantRoleLabel: $participantRoleLabel, participantColorValue: $participantColorValue, participantToolNames: $participantToolNames, handoffTargetParticipantId: $handoffTargetParticipantId, handoffTargetDisplayName: $handoffTargetDisplayName, handoffTargetRoleLabel: $handoffTargetRoleLabel, responseMetrics: $responseMetrics)';
}


}

/// @nodoc
abstract mixin class $MessageCopyWith<$Res>  {
  factory $MessageCopyWith(Message value, $Res Function(Message) _then) = _$MessageCopyWithImpl;
@useResult
$Res call({
 String id, String content, MessageRole role, DateTime timestamp, bool isStreaming, String? error, String? imageBase64, String? imageMimeType, String? originalImagePath, String? originalImageMimeType, String? participantId, String? participantDisplayName, String? participantRoleLabel, int? participantColorValue, List<String> participantToolNames, String? handoffTargetParticipantId, String? handoffTargetDisplayName, String? handoffTargetRoleLabel, MessageResponseMetrics? responseMetrics
});


$MessageResponseMetricsCopyWith<$Res>? get responseMetrics;

}
/// @nodoc
class _$MessageCopyWithImpl<$Res>
    implements $MessageCopyWith<$Res> {
  _$MessageCopyWithImpl(this._self, this._then);

  final Message _self;
  final $Res Function(Message) _then;

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? content = null,Object? role = null,Object? timestamp = null,Object? isStreaming = null,Object? error = freezed,Object? imageBase64 = freezed,Object? imageMimeType = freezed,Object? originalImagePath = freezed,Object? originalImageMimeType = freezed,Object? participantId = freezed,Object? participantDisplayName = freezed,Object? participantRoleLabel = freezed,Object? participantColorValue = freezed,Object? participantToolNames = null,Object? handoffTargetParticipantId = freezed,Object? handoffTargetDisplayName = freezed,Object? handoffTargetRoleLabel = freezed,Object? responseMetrics = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as MessageRole,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,isStreaming: null == isStreaming ? _self.isStreaming : isStreaming // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,imageBase64: freezed == imageBase64 ? _self.imageBase64 : imageBase64 // ignore: cast_nullable_to_non_nullable
as String?,imageMimeType: freezed == imageMimeType ? _self.imageMimeType : imageMimeType // ignore: cast_nullable_to_non_nullable
as String?,originalImagePath: freezed == originalImagePath ? _self.originalImagePath : originalImagePath // ignore: cast_nullable_to_non_nullable
as String?,originalImageMimeType: freezed == originalImageMimeType ? _self.originalImageMimeType : originalImageMimeType // ignore: cast_nullable_to_non_nullable
as String?,participantId: freezed == participantId ? _self.participantId : participantId // ignore: cast_nullable_to_non_nullable
as String?,participantDisplayName: freezed == participantDisplayName ? _self.participantDisplayName : participantDisplayName // ignore: cast_nullable_to_non_nullable
as String?,participantRoleLabel: freezed == participantRoleLabel ? _self.participantRoleLabel : participantRoleLabel // ignore: cast_nullable_to_non_nullable
as String?,participantColorValue: freezed == participantColorValue ? _self.participantColorValue : participantColorValue // ignore: cast_nullable_to_non_nullable
as int?,participantToolNames: null == participantToolNames ? _self.participantToolNames : participantToolNames // ignore: cast_nullable_to_non_nullable
as List<String>,handoffTargetParticipantId: freezed == handoffTargetParticipantId ? _self.handoffTargetParticipantId : handoffTargetParticipantId // ignore: cast_nullable_to_non_nullable
as String?,handoffTargetDisplayName: freezed == handoffTargetDisplayName ? _self.handoffTargetDisplayName : handoffTargetDisplayName // ignore: cast_nullable_to_non_nullable
as String?,handoffTargetRoleLabel: freezed == handoffTargetRoleLabel ? _self.handoffTargetRoleLabel : handoffTargetRoleLabel // ignore: cast_nullable_to_non_nullable
as String?,responseMetrics: freezed == responseMetrics ? _self.responseMetrics : responseMetrics // ignore: cast_nullable_to_non_nullable
as MessageResponseMetrics?,
  ));
}
/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MessageResponseMetricsCopyWith<$Res>? get responseMetrics {
    if (_self.responseMetrics == null) {
    return null;
  }

  return $MessageResponseMetricsCopyWith<$Res>(_self.responseMetrics!, (value) {
    return _then(_self.copyWith(responseMetrics: value));
  });
}
}


/// Adds pattern-matching-related methods to [Message].
extension MessagePatterns on Message {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Message value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Message() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Message value)  $default,){
final _that = this;
switch (_that) {
case _Message():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Message value)?  $default,){
final _that = this;
switch (_that) {
case _Message() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String content,  MessageRole role,  DateTime timestamp,  bool isStreaming,  String? error,  String? imageBase64,  String? imageMimeType,  String? originalImagePath,  String? originalImageMimeType,  String? participantId,  String? participantDisplayName,  String? participantRoleLabel,  int? participantColorValue,  List<String> participantToolNames,  String? handoffTargetParticipantId,  String? handoffTargetDisplayName,  String? handoffTargetRoleLabel,  MessageResponseMetrics? responseMetrics)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Message() when $default != null:
return $default(_that.id,_that.content,_that.role,_that.timestamp,_that.isStreaming,_that.error,_that.imageBase64,_that.imageMimeType,_that.originalImagePath,_that.originalImageMimeType,_that.participantId,_that.participantDisplayName,_that.participantRoleLabel,_that.participantColorValue,_that.participantToolNames,_that.handoffTargetParticipantId,_that.handoffTargetDisplayName,_that.handoffTargetRoleLabel,_that.responseMetrics);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String content,  MessageRole role,  DateTime timestamp,  bool isStreaming,  String? error,  String? imageBase64,  String? imageMimeType,  String? originalImagePath,  String? originalImageMimeType,  String? participantId,  String? participantDisplayName,  String? participantRoleLabel,  int? participantColorValue,  List<String> participantToolNames,  String? handoffTargetParticipantId,  String? handoffTargetDisplayName,  String? handoffTargetRoleLabel,  MessageResponseMetrics? responseMetrics)  $default,) {final _that = this;
switch (_that) {
case _Message():
return $default(_that.id,_that.content,_that.role,_that.timestamp,_that.isStreaming,_that.error,_that.imageBase64,_that.imageMimeType,_that.originalImagePath,_that.originalImageMimeType,_that.participantId,_that.participantDisplayName,_that.participantRoleLabel,_that.participantColorValue,_that.participantToolNames,_that.handoffTargetParticipantId,_that.handoffTargetDisplayName,_that.handoffTargetRoleLabel,_that.responseMetrics);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String content,  MessageRole role,  DateTime timestamp,  bool isStreaming,  String? error,  String? imageBase64,  String? imageMimeType,  String? originalImagePath,  String? originalImageMimeType,  String? participantId,  String? participantDisplayName,  String? participantRoleLabel,  int? participantColorValue,  List<String> participantToolNames,  String? handoffTargetParticipantId,  String? handoffTargetDisplayName,  String? handoffTargetRoleLabel,  MessageResponseMetrics? responseMetrics)?  $default,) {final _that = this;
switch (_that) {
case _Message() when $default != null:
return $default(_that.id,_that.content,_that.role,_that.timestamp,_that.isStreaming,_that.error,_that.imageBase64,_that.imageMimeType,_that.originalImagePath,_that.originalImageMimeType,_that.participantId,_that.participantDisplayName,_that.participantRoleLabel,_that.participantColorValue,_that.participantToolNames,_that.handoffTargetParticipantId,_that.handoffTargetDisplayName,_that.handoffTargetRoleLabel,_that.responseMetrics);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Message implements Message {
  const _Message({required this.id, required this.content, required this.role, required this.timestamp, this.isStreaming = false, this.error, this.imageBase64, this.imageMimeType, this.originalImagePath, this.originalImageMimeType, this.participantId, this.participantDisplayName, this.participantRoleLabel, this.participantColorValue, final  List<String> participantToolNames = const <String>[], this.handoffTargetParticipantId, this.handoffTargetDisplayName, this.handoffTargetRoleLabel, this.responseMetrics}): _participantToolNames = participantToolNames;
  factory _Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);

@override final  String id;
@override final  String content;
@override final  MessageRole role;
@override final  DateTime timestamp;
@override@JsonKey() final  bool isStreaming;
@override final  String? error;
@override final  String? imageBase64;
@override final  String? imageMimeType;
@override final  String? originalImagePath;
@override final  String? originalImageMimeType;
@override final  String? participantId;
@override final  String? participantDisplayName;
@override final  String? participantRoleLabel;
@override final  int? participantColorValue;
 final  List<String> _participantToolNames;
@override@JsonKey() List<String> get participantToolNames {
  if (_participantToolNames is EqualUnmodifiableListView) return _participantToolNames;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_participantToolNames);
}

@override final  String? handoffTargetParticipantId;
@override final  String? handoffTargetDisplayName;
@override final  String? handoffTargetRoleLabel;
@override final  MessageResponseMetrics? responseMetrics;

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessageCopyWith<_Message> get copyWith => __$MessageCopyWithImpl<_Message>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Message&&(identical(other.id, id) || other.id == id)&&(identical(other.content, content) || other.content == content)&&(identical(other.role, role) || other.role == role)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.isStreaming, isStreaming) || other.isStreaming == isStreaming)&&(identical(other.error, error) || other.error == error)&&(identical(other.imageBase64, imageBase64) || other.imageBase64 == imageBase64)&&(identical(other.imageMimeType, imageMimeType) || other.imageMimeType == imageMimeType)&&(identical(other.originalImagePath, originalImagePath) || other.originalImagePath == originalImagePath)&&(identical(other.originalImageMimeType, originalImageMimeType) || other.originalImageMimeType == originalImageMimeType)&&(identical(other.participantId, participantId) || other.participantId == participantId)&&(identical(other.participantDisplayName, participantDisplayName) || other.participantDisplayName == participantDisplayName)&&(identical(other.participantRoleLabel, participantRoleLabel) || other.participantRoleLabel == participantRoleLabel)&&(identical(other.participantColorValue, participantColorValue) || other.participantColorValue == participantColorValue)&&const DeepCollectionEquality().equals(other._participantToolNames, _participantToolNames)&&(identical(other.handoffTargetParticipantId, handoffTargetParticipantId) || other.handoffTargetParticipantId == handoffTargetParticipantId)&&(identical(other.handoffTargetDisplayName, handoffTargetDisplayName) || other.handoffTargetDisplayName == handoffTargetDisplayName)&&(identical(other.handoffTargetRoleLabel, handoffTargetRoleLabel) || other.handoffTargetRoleLabel == handoffTargetRoleLabel)&&(identical(other.responseMetrics, responseMetrics) || other.responseMetrics == responseMetrics));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,content,role,timestamp,isStreaming,error,imageBase64,imageMimeType,originalImagePath,originalImageMimeType,participantId,participantDisplayName,participantRoleLabel,participantColorValue,const DeepCollectionEquality().hash(_participantToolNames),handoffTargetParticipantId,handoffTargetDisplayName,handoffTargetRoleLabel,responseMetrics]);

@override
String toString() {
  return 'Message(id: $id, content: $content, role: $role, timestamp: $timestamp, isStreaming: $isStreaming, error: $error, imageBase64: $imageBase64, imageMimeType: $imageMimeType, originalImagePath: $originalImagePath, originalImageMimeType: $originalImageMimeType, participantId: $participantId, participantDisplayName: $participantDisplayName, participantRoleLabel: $participantRoleLabel, participantColorValue: $participantColorValue, participantToolNames: $participantToolNames, handoffTargetParticipantId: $handoffTargetParticipantId, handoffTargetDisplayName: $handoffTargetDisplayName, handoffTargetRoleLabel: $handoffTargetRoleLabel, responseMetrics: $responseMetrics)';
}


}

/// @nodoc
abstract mixin class _$MessageCopyWith<$Res> implements $MessageCopyWith<$Res> {
  factory _$MessageCopyWith(_Message value, $Res Function(_Message) _then) = __$MessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String content, MessageRole role, DateTime timestamp, bool isStreaming, String? error, String? imageBase64, String? imageMimeType, String? originalImagePath, String? originalImageMimeType, String? participantId, String? participantDisplayName, String? participantRoleLabel, int? participantColorValue, List<String> participantToolNames, String? handoffTargetParticipantId, String? handoffTargetDisplayName, String? handoffTargetRoleLabel, MessageResponseMetrics? responseMetrics
});


@override $MessageResponseMetricsCopyWith<$Res>? get responseMetrics;

}
/// @nodoc
class __$MessageCopyWithImpl<$Res>
    implements _$MessageCopyWith<$Res> {
  __$MessageCopyWithImpl(this._self, this._then);

  final _Message _self;
  final $Res Function(_Message) _then;

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? content = null,Object? role = null,Object? timestamp = null,Object? isStreaming = null,Object? error = freezed,Object? imageBase64 = freezed,Object? imageMimeType = freezed,Object? originalImagePath = freezed,Object? originalImageMimeType = freezed,Object? participantId = freezed,Object? participantDisplayName = freezed,Object? participantRoleLabel = freezed,Object? participantColorValue = freezed,Object? participantToolNames = null,Object? handoffTargetParticipantId = freezed,Object? handoffTargetDisplayName = freezed,Object? handoffTargetRoleLabel = freezed,Object? responseMetrics = freezed,}) {
  return _then(_Message(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as MessageRole,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,isStreaming: null == isStreaming ? _self.isStreaming : isStreaming // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,imageBase64: freezed == imageBase64 ? _self.imageBase64 : imageBase64 // ignore: cast_nullable_to_non_nullable
as String?,imageMimeType: freezed == imageMimeType ? _self.imageMimeType : imageMimeType // ignore: cast_nullable_to_non_nullable
as String?,originalImagePath: freezed == originalImagePath ? _self.originalImagePath : originalImagePath // ignore: cast_nullable_to_non_nullable
as String?,originalImageMimeType: freezed == originalImageMimeType ? _self.originalImageMimeType : originalImageMimeType // ignore: cast_nullable_to_non_nullable
as String?,participantId: freezed == participantId ? _self.participantId : participantId // ignore: cast_nullable_to_non_nullable
as String?,participantDisplayName: freezed == participantDisplayName ? _self.participantDisplayName : participantDisplayName // ignore: cast_nullable_to_non_nullable
as String?,participantRoleLabel: freezed == participantRoleLabel ? _self.participantRoleLabel : participantRoleLabel // ignore: cast_nullable_to_non_nullable
as String?,participantColorValue: freezed == participantColorValue ? _self.participantColorValue : participantColorValue // ignore: cast_nullable_to_non_nullable
as int?,participantToolNames: null == participantToolNames ? _self._participantToolNames : participantToolNames // ignore: cast_nullable_to_non_nullable
as List<String>,handoffTargetParticipantId: freezed == handoffTargetParticipantId ? _self.handoffTargetParticipantId : handoffTargetParticipantId // ignore: cast_nullable_to_non_nullable
as String?,handoffTargetDisplayName: freezed == handoffTargetDisplayName ? _self.handoffTargetDisplayName : handoffTargetDisplayName // ignore: cast_nullable_to_non_nullable
as String?,handoffTargetRoleLabel: freezed == handoffTargetRoleLabel ? _self.handoffTargetRoleLabel : handoffTargetRoleLabel // ignore: cast_nullable_to_non_nullable
as String?,responseMetrics: freezed == responseMetrics ? _self.responseMetrics : responseMetrics // ignore: cast_nullable_to_non_nullable
as MessageResponseMetrics?,
  ));
}

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MessageResponseMetricsCopyWith<$Res>? get responseMetrics {
    if (_self.responseMetrics == null) {
    return null;
  }

  return $MessageResponseMetricsCopyWith<$Res>(_self.responseMetrics!, (value) {
    return _then(_self.copyWith(responseMetrics: value));
  });
}
}

// dart format on
