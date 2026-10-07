// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'roadmap_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoadmapItemSnapshot {

 String get id; String get title; String get quote; int? get line; bool get verified;
/// Create a copy of RoadmapItemSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoadmapItemSnapshotCopyWith<RoadmapItemSnapshot> get copyWith => _$RoadmapItemSnapshotCopyWithImpl<RoadmapItemSnapshot>(this as RoadmapItemSnapshot, _$identity);

  /// Serializes this RoadmapItemSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RoadmapItemSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoadmapItemSnapshot&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.quote, _this.quote) || other.quote == _this.quote)&&(identical(other.line, _this.line) || other.line == _this.line)&&(identical(other.verified, _this.verified) || other.verified == _this.verified));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RoadmapItemSnapshot;
  return Object.hash(runtimeType,_this.id,_this.title,_this.quote,_this.line,_this.verified);
}

@override
String toString() {
  final _this = this as RoadmapItemSnapshot;
  return 'RoadmapItemSnapshot(id: ${_this.id}, title: ${_this.title}, quote: ${_this.quote}, line: ${_this.line}, verified: ${_this.verified})';
}


}

/// @nodoc
abstract mixin class $RoadmapItemSnapshotCopyWith<$Res>  {
  factory $RoadmapItemSnapshotCopyWith(RoadmapItemSnapshot value, $Res Function(RoadmapItemSnapshot) _then) = _$RoadmapItemSnapshotCopyWithImpl;
@useResult
$Res call({
 String id, String title, String quote, int? line, bool verified
});




}
/// @nodoc
class _$RoadmapItemSnapshotCopyWithImpl<$Res>
    implements $RoadmapItemSnapshotCopyWith<$Res> {
  _$RoadmapItemSnapshotCopyWithImpl(this._self, this._then);

  final RoadmapItemSnapshot _self;
  final $Res Function(RoadmapItemSnapshot) _then;

/// Create a copy of RoadmapItemSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? quote = null,Object? line = freezed,Object? verified = null,}) {
  return _then(RoadmapItemSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,quote: null == quote ? _self.quote : quote // ignore: cast_nullable_to_non_nullable
as String,line: freezed == line ? _self.line : line // ignore: cast_nullable_to_non_nullable
as int?,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RoadmapItemSnapshot].
extension RoadmapItemSnapshotPatterns on RoadmapItemSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoadmapItemSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoadmapItemSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoadmapItemSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _RoadmapItemSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoadmapItemSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _RoadmapItemSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String quote,  int? line,  bool verified)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoadmapItemSnapshot() when $default != null:
return $default(_that.id,_that.title,_that.quote,_that.line,_that.verified);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String quote,  int? line,  bool verified)  $default,) {final _that = this;
switch (_that) {
case _RoadmapItemSnapshot():
return $default(_that.id,_that.title,_that.quote,_that.line,_that.verified);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String quote,  int? line,  bool verified)?  $default,) {final _that = this;
switch (_that) {
case _RoadmapItemSnapshot() when $default != null:
return $default(_that.id,_that.title,_that.quote,_that.line,_that.verified);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoadmapItemSnapshot implements RoadmapItemSnapshot {
  const _RoadmapItemSnapshot({required this.id, required this.title, required this.quote, this.line, this.verified = true});
  factory _RoadmapItemSnapshot.fromJson(Map<String, dynamic> json) => _$RoadmapItemSnapshotFromJson(json);

@override final  String id;
@override final  String title;
@override final  String quote;
@override final  int? line;
@override@JsonKey() final  bool verified;

/// Create a copy of RoadmapItemSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoadmapItemSnapshotCopyWith<_RoadmapItemSnapshot> get copyWith => __$RoadmapItemSnapshotCopyWithImpl<_RoadmapItemSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoadmapItemSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoadmapItemSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.quote, quote) || other.quote == quote)&&(identical(other.line, line) || other.line == line)&&(identical(other.verified, verified) || other.verified == verified));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,title,quote,line,verified);
}

@override
String toString() {
    return 'RoadmapItemSnapshot(id: $id, title: $title, quote: $quote, line: $line, verified: $verified)';
}


}

/// @nodoc
abstract mixin class _$RoadmapItemSnapshotCopyWith<$Res> implements $RoadmapItemSnapshotCopyWith<$Res> {
  factory _$RoadmapItemSnapshotCopyWith(_RoadmapItemSnapshot value, $Res Function(_RoadmapItemSnapshot) _then) = __$RoadmapItemSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String quote, int? line, bool verified
});




}
/// @nodoc
class __$RoadmapItemSnapshotCopyWithImpl<$Res>
    implements _$RoadmapItemSnapshotCopyWith<$Res> {
  __$RoadmapItemSnapshotCopyWithImpl(this._self, this._then);

  final _RoadmapItemSnapshot _self;
  final $Res Function(_RoadmapItemSnapshot) _then;

/// Create a copy of RoadmapItemSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? quote = null,Object? line = freezed,Object? verified = null,}) {
  return _then(_RoadmapItemSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,quote: null == quote ? _self.quote : quote // ignore: cast_nullable_to_non_nullable
as String,line: freezed == line ? _self.line : line // ignore: cast_nullable_to_non_nullable
as int?,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$RoadmapSnapshot {

 String get projectId; String get roadmapPath; String get contentSha256; int get extractorVersion; String get model; DateTime get extractedAt; RoadmapSnapshotStatus get status; RoadmapItemSnapshot? get recommended; RoadmapRecommendationSource get recommendationSource; List<RoadmapItemSnapshot> get current; List<RoadmapItemSnapshot> get blocked; List<RoadmapItemSnapshot> get upcoming; int get droppedCount; String? get error;/// The user pinned [recommended] over what the extractor chose. Applied
/// at read time by the service; the stored snapshot stays as extracted.
 bool get pinned;
/// Create a copy of RoadmapSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoadmapSnapshotCopyWith<RoadmapSnapshot> get copyWith => _$RoadmapSnapshotCopyWithImpl<RoadmapSnapshot>(this as RoadmapSnapshot, _$identity);

  /// Serializes this RoadmapSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RoadmapSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoadmapSnapshot&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.roadmapPath, _this.roadmapPath) || other.roadmapPath == _this.roadmapPath)&&(identical(other.contentSha256, _this.contentSha256) || other.contentSha256 == _this.contentSha256)&&(identical(other.extractorVersion, _this.extractorVersion) || other.extractorVersion == _this.extractorVersion)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.extractedAt, _this.extractedAt) || other.extractedAt == _this.extractedAt)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.recommended, _this.recommended) || other.recommended == _this.recommended)&&(identical(other.recommendationSource, _this.recommendationSource) || other.recommendationSource == _this.recommendationSource)&&const DeepCollectionEquality().equals(other.current, _this.current)&&const DeepCollectionEquality().equals(other.blocked, _this.blocked)&&const DeepCollectionEquality().equals(other.upcoming, _this.upcoming)&&(identical(other.droppedCount, _this.droppedCount) || other.droppedCount == _this.droppedCount)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.pinned, _this.pinned) || other.pinned == _this.pinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RoadmapSnapshot;
  return Object.hash(runtimeType,_this.projectId,_this.roadmapPath,_this.contentSha256,_this.extractorVersion,_this.model,_this.extractedAt,_this.status,_this.recommended,_this.recommendationSource,const DeepCollectionEquality().hash(_this.current),const DeepCollectionEquality().hash(_this.blocked),const DeepCollectionEquality().hash(_this.upcoming),_this.droppedCount,_this.error,_this.pinned);
}

@override
String toString() {
  final _this = this as RoadmapSnapshot;
  return 'RoadmapSnapshot(projectId: ${_this.projectId}, roadmapPath: ${_this.roadmapPath}, contentSha256: ${_this.contentSha256}, extractorVersion: ${_this.extractorVersion}, model: ${_this.model}, extractedAt: ${_this.extractedAt}, status: ${_this.status}, recommended: ${_this.recommended}, recommendationSource: ${_this.recommendationSource}, current: ${_this.current}, blocked: ${_this.blocked}, upcoming: ${_this.upcoming}, droppedCount: ${_this.droppedCount}, error: ${_this.error}, pinned: ${_this.pinned})';
}


}

/// @nodoc
abstract mixin class $RoadmapSnapshotCopyWith<$Res>  {
  factory $RoadmapSnapshotCopyWith(RoadmapSnapshot value, $Res Function(RoadmapSnapshot) _then) = _$RoadmapSnapshotCopyWithImpl;
@useResult
$Res call({
 String projectId, String roadmapPath, String contentSha256, int extractorVersion, String model, DateTime extractedAt, RoadmapSnapshotStatus status, RoadmapItemSnapshot? recommended, RoadmapRecommendationSource recommendationSource, List<RoadmapItemSnapshot> current, List<RoadmapItemSnapshot> blocked, List<RoadmapItemSnapshot> upcoming, int droppedCount, String? error, bool pinned
});


$RoadmapItemSnapshotCopyWith<$Res>? get recommended;

}
/// @nodoc
class _$RoadmapSnapshotCopyWithImpl<$Res>
    implements $RoadmapSnapshotCopyWith<$Res> {
  _$RoadmapSnapshotCopyWithImpl(this._self, this._then);

  final RoadmapSnapshot _self;
  final $Res Function(RoadmapSnapshot) _then;

/// Create a copy of RoadmapSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? roadmapPath = null,Object? contentSha256 = null,Object? extractorVersion = null,Object? model = null,Object? extractedAt = null,Object? status = null,Object? recommended = freezed,Object? recommendationSource = null,Object? current = null,Object? blocked = null,Object? upcoming = null,Object? droppedCount = null,Object? error = freezed,Object? pinned = null,}) {
  return _then(RoadmapSnapshot(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,roadmapPath: null == roadmapPath ? _self.roadmapPath : roadmapPath // ignore: cast_nullable_to_non_nullable
as String,contentSha256: null == contentSha256 ? _self.contentSha256 : contentSha256 // ignore: cast_nullable_to_non_nullable
as String,extractorVersion: null == extractorVersion ? _self.extractorVersion : extractorVersion // ignore: cast_nullable_to_non_nullable
as int,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,extractedAt: null == extractedAt ? _self.extractedAt : extractedAt // ignore: cast_nullable_to_non_nullable
as DateTime,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoadmapSnapshotStatus,recommended: freezed == recommended ? _self.recommended : recommended // ignore: cast_nullable_to_non_nullable
as RoadmapItemSnapshot?,recommendationSource: null == recommendationSource ? _self.recommendationSource : recommendationSource // ignore: cast_nullable_to_non_nullable
as RoadmapRecommendationSource,current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as List<RoadmapItemSnapshot>,blocked: null == blocked ? _self.blocked : blocked // ignore: cast_nullable_to_non_nullable
as List<RoadmapItemSnapshot>,upcoming: null == upcoming ? _self.upcoming : upcoming // ignore: cast_nullable_to_non_nullable
as List<RoadmapItemSnapshot>,droppedCount: null == droppedCount ? _self.droppedCount : droppedCount // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of RoadmapSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoadmapItemSnapshotCopyWith<$Res>? get recommended {
    if (_self.recommended == null) {
    return null;
  }

  return $RoadmapItemSnapshotCopyWith<$Res>(_self.recommended!, (value) {
    return _then(_self.copyWith(recommended: value));
  });
}
}


/// Adds pattern-matching-related methods to [RoadmapSnapshot].
extension RoadmapSnapshotPatterns on RoadmapSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoadmapSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoadmapSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoadmapSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _RoadmapSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoadmapSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _RoadmapSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  String roadmapPath,  String contentSha256,  int extractorVersion,  String model,  DateTime extractedAt,  RoadmapSnapshotStatus status,  RoadmapItemSnapshot? recommended,  RoadmapRecommendationSource recommendationSource,  List<RoadmapItemSnapshot> current,  List<RoadmapItemSnapshot> blocked,  List<RoadmapItemSnapshot> upcoming,  int droppedCount,  String? error,  bool pinned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoadmapSnapshot() when $default != null:
return $default(_that.projectId,_that.roadmapPath,_that.contentSha256,_that.extractorVersion,_that.model,_that.extractedAt,_that.status,_that.recommended,_that.recommendationSource,_that.current,_that.blocked,_that.upcoming,_that.droppedCount,_that.error,_that.pinned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  String roadmapPath,  String contentSha256,  int extractorVersion,  String model,  DateTime extractedAt,  RoadmapSnapshotStatus status,  RoadmapItemSnapshot? recommended,  RoadmapRecommendationSource recommendationSource,  List<RoadmapItemSnapshot> current,  List<RoadmapItemSnapshot> blocked,  List<RoadmapItemSnapshot> upcoming,  int droppedCount,  String? error,  bool pinned)  $default,) {final _that = this;
switch (_that) {
case _RoadmapSnapshot():
return $default(_that.projectId,_that.roadmapPath,_that.contentSha256,_that.extractorVersion,_that.model,_that.extractedAt,_that.status,_that.recommended,_that.recommendationSource,_that.current,_that.blocked,_that.upcoming,_that.droppedCount,_that.error,_that.pinned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  String roadmapPath,  String contentSha256,  int extractorVersion,  String model,  DateTime extractedAt,  RoadmapSnapshotStatus status,  RoadmapItemSnapshot? recommended,  RoadmapRecommendationSource recommendationSource,  List<RoadmapItemSnapshot> current,  List<RoadmapItemSnapshot> blocked,  List<RoadmapItemSnapshot> upcoming,  int droppedCount,  String? error,  bool pinned)?  $default,) {final _that = this;
switch (_that) {
case _RoadmapSnapshot() when $default != null:
return $default(_that.projectId,_that.roadmapPath,_that.contentSha256,_that.extractorVersion,_that.model,_that.extractedAt,_that.status,_that.recommended,_that.recommendationSource,_that.current,_that.blocked,_that.upcoming,_that.droppedCount,_that.error,_that.pinned);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoadmapSnapshot extends RoadmapSnapshot {
  const _RoadmapSnapshot({required this.projectId, required this.roadmapPath, required this.contentSha256, required this.extractorVersion, required this.model, required this.extractedAt, required this.status, this.recommended, this.recommendationSource = RoadmapRecommendationSource.explicit,  List<RoadmapItemSnapshot> current = const <RoadmapItemSnapshot>[],  List<RoadmapItemSnapshot> blocked = const <RoadmapItemSnapshot>[],  List<RoadmapItemSnapshot> upcoming = const <RoadmapItemSnapshot>[], this.droppedCount = 0, this.error, this.pinned = false}): _current = current,_blocked = blocked,_upcoming = upcoming,super._();
  factory _RoadmapSnapshot.fromJson(Map<String, dynamic> json) => _$RoadmapSnapshotFromJson(json);

@override final  String projectId;
@override final  String roadmapPath;
@override final  String contentSha256;
@override final  int extractorVersion;
@override final  String model;
@override final  DateTime extractedAt;
@override final  RoadmapSnapshotStatus status;
@override final  RoadmapItemSnapshot? recommended;
@override@JsonKey() final  RoadmapRecommendationSource recommendationSource;
 final  List<RoadmapItemSnapshot> _current;
@override@JsonKey() List<RoadmapItemSnapshot> get current {
  if (_current is EqualUnmodifiableListView) return _current;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_current);
}

 final  List<RoadmapItemSnapshot> _blocked;
@override@JsonKey() List<RoadmapItemSnapshot> get blocked {
  if (_blocked is EqualUnmodifiableListView) return _blocked;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocked);
}

 final  List<RoadmapItemSnapshot> _upcoming;
@override@JsonKey() List<RoadmapItemSnapshot> get upcoming {
  if (_upcoming is EqualUnmodifiableListView) return _upcoming;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_upcoming);
}

@override@JsonKey() final  int droppedCount;
@override final  String? error;
/// The user pinned [recommended] over what the extractor chose. Applied
/// at read time by the service; the stored snapshot stays as extracted.
@override@JsonKey() final  bool pinned;

/// Create a copy of RoadmapSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoadmapSnapshotCopyWith<_RoadmapSnapshot> get copyWith => __$RoadmapSnapshotCopyWithImpl<_RoadmapSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoadmapSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoadmapSnapshot&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.roadmapPath, roadmapPath) || other.roadmapPath == roadmapPath)&&(identical(other.contentSha256, contentSha256) || other.contentSha256 == contentSha256)&&(identical(other.extractorVersion, extractorVersion) || other.extractorVersion == extractorVersion)&&(identical(other.model, model) || other.model == model)&&(identical(other.extractedAt, extractedAt) || other.extractedAt == extractedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.recommended, recommended) || other.recommended == recommended)&&(identical(other.recommendationSource, recommendationSource) || other.recommendationSource == recommendationSource)&&const DeepCollectionEquality().equals(other.current, _current)&&const DeepCollectionEquality().equals(other.blocked, _blocked)&&const DeepCollectionEquality().equals(other.upcoming, _upcoming)&&(identical(other.droppedCount, droppedCount) || other.droppedCount == droppedCount)&&(identical(other.error, error) || other.error == error)&&(identical(other.pinned, pinned) || other.pinned == pinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,projectId,roadmapPath,contentSha256,extractorVersion,model,extractedAt,status,recommended,recommendationSource,const DeepCollectionEquality().hash(_current),const DeepCollectionEquality().hash(_blocked),const DeepCollectionEquality().hash(_upcoming),droppedCount,error,pinned);
}

@override
String toString() {
    return 'RoadmapSnapshot(projectId: $projectId, roadmapPath: $roadmapPath, contentSha256: $contentSha256, extractorVersion: $extractorVersion, model: $model, extractedAt: $extractedAt, status: $status, recommended: $recommended, recommendationSource: $recommendationSource, current: $current, blocked: $blocked, upcoming: $upcoming, droppedCount: $droppedCount, error: $error, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class _$RoadmapSnapshotCopyWith<$Res> implements $RoadmapSnapshotCopyWith<$Res> {
  factory _$RoadmapSnapshotCopyWith(_RoadmapSnapshot value, $Res Function(_RoadmapSnapshot) _then) = __$RoadmapSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String projectId, String roadmapPath, String contentSha256, int extractorVersion, String model, DateTime extractedAt, RoadmapSnapshotStatus status, RoadmapItemSnapshot? recommended, RoadmapRecommendationSource recommendationSource, List<RoadmapItemSnapshot> current, List<RoadmapItemSnapshot> blocked, List<RoadmapItemSnapshot> upcoming, int droppedCount, String? error, bool pinned
});


@override $RoadmapItemSnapshotCopyWith<$Res>? get recommended;

}
/// @nodoc
class __$RoadmapSnapshotCopyWithImpl<$Res>
    implements _$RoadmapSnapshotCopyWith<$Res> {
  __$RoadmapSnapshotCopyWithImpl(this._self, this._then);

  final _RoadmapSnapshot _self;
  final $Res Function(_RoadmapSnapshot) _then;

/// Create a copy of RoadmapSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? roadmapPath = null,Object? contentSha256 = null,Object? extractorVersion = null,Object? model = null,Object? extractedAt = null,Object? status = null,Object? recommended = freezed,Object? recommendationSource = null,Object? current = null,Object? blocked = null,Object? upcoming = null,Object? droppedCount = null,Object? error = freezed,Object? pinned = null,}) {
  return _then(_RoadmapSnapshot(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,roadmapPath: null == roadmapPath ? _self.roadmapPath : roadmapPath // ignore: cast_nullable_to_non_nullable
as String,contentSha256: null == contentSha256 ? _self.contentSha256 : contentSha256 // ignore: cast_nullable_to_non_nullable
as String,extractorVersion: null == extractorVersion ? _self.extractorVersion : extractorVersion // ignore: cast_nullable_to_non_nullable
as int,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,extractedAt: null == extractedAt ? _self.extractedAt : extractedAt // ignore: cast_nullable_to_non_nullable
as DateTime,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoadmapSnapshotStatus,recommended: freezed == recommended ? _self.recommended : recommended // ignore: cast_nullable_to_non_nullable
as RoadmapItemSnapshot?,recommendationSource: null == recommendationSource ? _self.recommendationSource : recommendationSource // ignore: cast_nullable_to_non_nullable
as RoadmapRecommendationSource,current: null == current ? _self._current : current // ignore: cast_nullable_to_non_nullable
as List<RoadmapItemSnapshot>,blocked: null == blocked ? _self._blocked : blocked // ignore: cast_nullable_to_non_nullable
as List<RoadmapItemSnapshot>,upcoming: null == upcoming ? _self._upcoming : upcoming // ignore: cast_nullable_to_non_nullable
as List<RoadmapItemSnapshot>,droppedCount: null == droppedCount ? _self.droppedCount : droppedCount // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of RoadmapSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoadmapItemSnapshotCopyWith<$Res>? get recommended {
    if (_self.recommended == null) {
    return null;
  }

  return $RoadmapItemSnapshotCopyWith<$Res>(_self.recommended!, (value) {
    return _then(_self.copyWith(recommended: value));
  });
}
}

// dart format on
