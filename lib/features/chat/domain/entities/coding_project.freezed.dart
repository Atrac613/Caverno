// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coding_project.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CodingProject {

 String get id; String get name; String get rootPath; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of CodingProject
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CodingProjectCopyWith<CodingProject> get copyWith => _$CodingProjectCopyWithImpl<CodingProject>(this as CodingProject, _$identity);

  /// Serializes this CodingProject to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CodingProject&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.rootPath, rootPath) || other.rootPath == rootPath)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,rootPath,createdAt,updatedAt);

@override
String toString() {
  return 'CodingProject(id: $id, name: $name, rootPath: $rootPath, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $CodingProjectCopyWith<$Res>  {
  factory $CodingProjectCopyWith(CodingProject value, $Res Function(CodingProject) _then) = _$CodingProjectCopyWithImpl;
@useResult
$Res call({
 String id, String name, String rootPath, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$CodingProjectCopyWithImpl<$Res>
    implements $CodingProjectCopyWith<$Res> {
  _$CodingProjectCopyWithImpl(this._self, this._then);

  final CodingProject _self;
  final $Res Function(CodingProject) _then;

/// Create a copy of CodingProject
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? rootPath = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,rootPath: null == rootPath ? _self.rootPath : rootPath // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [CodingProject].
extension CodingProjectPatterns on CodingProject {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CodingProject value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CodingProject() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CodingProject value)  $default,){
final _that = this;
switch (_that) {
case _CodingProject():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CodingProject value)?  $default,){
final _that = this;
switch (_that) {
case _CodingProject() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String rootPath,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CodingProject() when $default != null:
return $default(_that.id,_that.name,_that.rootPath,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String rootPath,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _CodingProject():
return $default(_that.id,_that.name,_that.rootPath,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String rootPath,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _CodingProject() when $default != null:
return $default(_that.id,_that.name,_that.rootPath,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CodingProject extends CodingProject {
  const _CodingProject({required this.id, required this.name, required this.rootPath, required this.createdAt, required this.updatedAt}): super._();
  factory _CodingProject.fromJson(Map<String, dynamic> json) => _$CodingProjectFromJson(json);

@override final  String id;
@override final  String name;
@override final  String rootPath;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of CodingProject
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CodingProjectCopyWith<_CodingProject> get copyWith => __$CodingProjectCopyWithImpl<_CodingProject>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CodingProjectToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CodingProject&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.rootPath, rootPath) || other.rootPath == rootPath)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,rootPath,createdAt,updatedAt);

@override
String toString() {
  return 'CodingProject(id: $id, name: $name, rootPath: $rootPath, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$CodingProjectCopyWith<$Res> implements $CodingProjectCopyWith<$Res> {
  factory _$CodingProjectCopyWith(_CodingProject value, $Res Function(_CodingProject) _then) = __$CodingProjectCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String rootPath, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$CodingProjectCopyWithImpl<$Res>
    implements _$CodingProjectCopyWith<$Res> {
  __$CodingProjectCopyWithImpl(this._self, this._then);

  final _CodingProject _self;
  final $Res Function(_CodingProject) _then;

/// Create a copy of CodingProject
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? rootPath = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_CodingProject(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,rootPath: null == rootPath ? _self.rootPath : rootPath // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
