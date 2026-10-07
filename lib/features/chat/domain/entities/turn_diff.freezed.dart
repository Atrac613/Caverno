// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'turn_diff.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TurnDiffFile {

 String get filePath; bool get isNewFile; bool get isDeletedFile; bool get isBinary; bool get isLargeFile; bool get isTruncated; bool get isUntracked; int get linesAdded; int get linesRemoved; String get unifiedPatch; String get note;
/// Create a copy of TurnDiffFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnDiffFileCopyWith<TurnDiffFile> get copyWith => _$TurnDiffFileCopyWithImpl<TurnDiffFile>(this as TurnDiffFile, _$identity);

  /// Serializes this TurnDiffFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TurnDiffFile;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnDiffFile&&(identical(other.filePath, _this.filePath) || other.filePath == _this.filePath)&&(identical(other.isNewFile, _this.isNewFile) || other.isNewFile == _this.isNewFile)&&(identical(other.isDeletedFile, _this.isDeletedFile) || other.isDeletedFile == _this.isDeletedFile)&&(identical(other.isBinary, _this.isBinary) || other.isBinary == _this.isBinary)&&(identical(other.isLargeFile, _this.isLargeFile) || other.isLargeFile == _this.isLargeFile)&&(identical(other.isTruncated, _this.isTruncated) || other.isTruncated == _this.isTruncated)&&(identical(other.isUntracked, _this.isUntracked) || other.isUntracked == _this.isUntracked)&&(identical(other.linesAdded, _this.linesAdded) || other.linesAdded == _this.linesAdded)&&(identical(other.linesRemoved, _this.linesRemoved) || other.linesRemoved == _this.linesRemoved)&&(identical(other.unifiedPatch, _this.unifiedPatch) || other.unifiedPatch == _this.unifiedPatch)&&(identical(other.note, _this.note) || other.note == _this.note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TurnDiffFile;
  return Object.hash(runtimeType,_this.filePath,_this.isNewFile,_this.isDeletedFile,_this.isBinary,_this.isLargeFile,_this.isTruncated,_this.isUntracked,_this.linesAdded,_this.linesRemoved,_this.unifiedPatch,_this.note);
}

@override
String toString() {
  final _this = this as TurnDiffFile;
  return 'TurnDiffFile(filePath: ${_this.filePath}, isNewFile: ${_this.isNewFile}, isDeletedFile: ${_this.isDeletedFile}, isBinary: ${_this.isBinary}, isLargeFile: ${_this.isLargeFile}, isTruncated: ${_this.isTruncated}, isUntracked: ${_this.isUntracked}, linesAdded: ${_this.linesAdded}, linesRemoved: ${_this.linesRemoved}, unifiedPatch: ${_this.unifiedPatch}, note: ${_this.note})';
}


}

/// @nodoc
abstract mixin class $TurnDiffFileCopyWith<$Res>  {
  factory $TurnDiffFileCopyWith(TurnDiffFile value, $Res Function(TurnDiffFile) _then) = _$TurnDiffFileCopyWithImpl;
@useResult
$Res call({
 String filePath, bool isNewFile, bool isDeletedFile, bool isBinary, bool isLargeFile, bool isTruncated, bool isUntracked, int linesAdded, int linesRemoved, String unifiedPatch, String note
});




}
/// @nodoc
class _$TurnDiffFileCopyWithImpl<$Res>
    implements $TurnDiffFileCopyWith<$Res> {
  _$TurnDiffFileCopyWithImpl(this._self, this._then);

  final TurnDiffFile _self;
  final $Res Function(TurnDiffFile) _then;

/// Create a copy of TurnDiffFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? filePath = null,Object? isNewFile = null,Object? isDeletedFile = null,Object? isBinary = null,Object? isLargeFile = null,Object? isTruncated = null,Object? isUntracked = null,Object? linesAdded = null,Object? linesRemoved = null,Object? unifiedPatch = null,Object? note = null,}) {
  return _then(TurnDiffFile(
filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,isNewFile: null == isNewFile ? _self.isNewFile : isNewFile // ignore: cast_nullable_to_non_nullable
as bool,isDeletedFile: null == isDeletedFile ? _self.isDeletedFile : isDeletedFile // ignore: cast_nullable_to_non_nullable
as bool,isBinary: null == isBinary ? _self.isBinary : isBinary // ignore: cast_nullable_to_non_nullable
as bool,isLargeFile: null == isLargeFile ? _self.isLargeFile : isLargeFile // ignore: cast_nullable_to_non_nullable
as bool,isTruncated: null == isTruncated ? _self.isTruncated : isTruncated // ignore: cast_nullable_to_non_nullable
as bool,isUntracked: null == isUntracked ? _self.isUntracked : isUntracked // ignore: cast_nullable_to_non_nullable
as bool,linesAdded: null == linesAdded ? _self.linesAdded : linesAdded // ignore: cast_nullable_to_non_nullable
as int,linesRemoved: null == linesRemoved ? _self.linesRemoved : linesRemoved // ignore: cast_nullable_to_non_nullable
as int,unifiedPatch: null == unifiedPatch ? _self.unifiedPatch : unifiedPatch // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TurnDiffFile].
extension TurnDiffFilePatterns on TurnDiffFile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnDiffFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnDiffFile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnDiffFile value)  $default,){
final _that = this;
switch (_that) {
case _TurnDiffFile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnDiffFile value)?  $default,){
final _that = this;
switch (_that) {
case _TurnDiffFile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String filePath,  bool isNewFile,  bool isDeletedFile,  bool isBinary,  bool isLargeFile,  bool isTruncated,  bool isUntracked,  int linesAdded,  int linesRemoved,  String unifiedPatch,  String note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnDiffFile() when $default != null:
return $default(_that.filePath,_that.isNewFile,_that.isDeletedFile,_that.isBinary,_that.isLargeFile,_that.isTruncated,_that.isUntracked,_that.linesAdded,_that.linesRemoved,_that.unifiedPatch,_that.note);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String filePath,  bool isNewFile,  bool isDeletedFile,  bool isBinary,  bool isLargeFile,  bool isTruncated,  bool isUntracked,  int linesAdded,  int linesRemoved,  String unifiedPatch,  String note)  $default,) {final _that = this;
switch (_that) {
case _TurnDiffFile():
return $default(_that.filePath,_that.isNewFile,_that.isDeletedFile,_that.isBinary,_that.isLargeFile,_that.isTruncated,_that.isUntracked,_that.linesAdded,_that.linesRemoved,_that.unifiedPatch,_that.note);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String filePath,  bool isNewFile,  bool isDeletedFile,  bool isBinary,  bool isLargeFile,  bool isTruncated,  bool isUntracked,  int linesAdded,  int linesRemoved,  String unifiedPatch,  String note)?  $default,) {final _that = this;
switch (_that) {
case _TurnDiffFile() when $default != null:
return $default(_that.filePath,_that.isNewFile,_that.isDeletedFile,_that.isBinary,_that.isLargeFile,_that.isTruncated,_that.isUntracked,_that.linesAdded,_that.linesRemoved,_that.unifiedPatch,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TurnDiffFile extends TurnDiffFile {
  const _TurnDiffFile({required this.filePath, this.isNewFile = false, this.isDeletedFile = false, this.isBinary = false, this.isLargeFile = false, this.isTruncated = false, this.isUntracked = false, this.linesAdded = 0, this.linesRemoved = 0, this.unifiedPatch = '', this.note = ''}): super._();
  factory _TurnDiffFile.fromJson(Map<String, dynamic> json) => _$TurnDiffFileFromJson(json);

@override final  String filePath;
@override@JsonKey() final  bool isNewFile;
@override@JsonKey() final  bool isDeletedFile;
@override@JsonKey() final  bool isBinary;
@override@JsonKey() final  bool isLargeFile;
@override@JsonKey() final  bool isTruncated;
@override@JsonKey() final  bool isUntracked;
@override@JsonKey() final  int linesAdded;
@override@JsonKey() final  int linesRemoved;
@override@JsonKey() final  String unifiedPatch;
@override@JsonKey() final  String note;

/// Create a copy of TurnDiffFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnDiffFileCopyWith<_TurnDiffFile> get copyWith => __$TurnDiffFileCopyWithImpl<_TurnDiffFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TurnDiffFileToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnDiffFile&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.isNewFile, isNewFile) || other.isNewFile == isNewFile)&&(identical(other.isDeletedFile, isDeletedFile) || other.isDeletedFile == isDeletedFile)&&(identical(other.isBinary, isBinary) || other.isBinary == isBinary)&&(identical(other.isLargeFile, isLargeFile) || other.isLargeFile == isLargeFile)&&(identical(other.isTruncated, isTruncated) || other.isTruncated == isTruncated)&&(identical(other.isUntracked, isUntracked) || other.isUntracked == isUntracked)&&(identical(other.linesAdded, linesAdded) || other.linesAdded == linesAdded)&&(identical(other.linesRemoved, linesRemoved) || other.linesRemoved == linesRemoved)&&(identical(other.unifiedPatch, unifiedPatch) || other.unifiedPatch == unifiedPatch)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,filePath,isNewFile,isDeletedFile,isBinary,isLargeFile,isTruncated,isUntracked,linesAdded,linesRemoved,unifiedPatch,note);
}

@override
String toString() {
    return 'TurnDiffFile(filePath: $filePath, isNewFile: $isNewFile, isDeletedFile: $isDeletedFile, isBinary: $isBinary, isLargeFile: $isLargeFile, isTruncated: $isTruncated, isUntracked: $isUntracked, linesAdded: $linesAdded, linesRemoved: $linesRemoved, unifiedPatch: $unifiedPatch, note: $note)';
}


}

/// @nodoc
abstract mixin class _$TurnDiffFileCopyWith<$Res> implements $TurnDiffFileCopyWith<$Res> {
  factory _$TurnDiffFileCopyWith(_TurnDiffFile value, $Res Function(_TurnDiffFile) _then) = __$TurnDiffFileCopyWithImpl;
@override @useResult
$Res call({
 String filePath, bool isNewFile, bool isDeletedFile, bool isBinary, bool isLargeFile, bool isTruncated, bool isUntracked, int linesAdded, int linesRemoved, String unifiedPatch, String note
});




}
/// @nodoc
class __$TurnDiffFileCopyWithImpl<$Res>
    implements _$TurnDiffFileCopyWith<$Res> {
  __$TurnDiffFileCopyWithImpl(this._self, this._then);

  final _TurnDiffFile _self;
  final $Res Function(_TurnDiffFile) _then;

/// Create a copy of TurnDiffFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? filePath = null,Object? isNewFile = null,Object? isDeletedFile = null,Object? isBinary = null,Object? isLargeFile = null,Object? isTruncated = null,Object? isUntracked = null,Object? linesAdded = null,Object? linesRemoved = null,Object? unifiedPatch = null,Object? note = null,}) {
  return _then(_TurnDiffFile(
filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,isNewFile: null == isNewFile ? _self.isNewFile : isNewFile // ignore: cast_nullable_to_non_nullable
as bool,isDeletedFile: null == isDeletedFile ? _self.isDeletedFile : isDeletedFile // ignore: cast_nullable_to_non_nullable
as bool,isBinary: null == isBinary ? _self.isBinary : isBinary // ignore: cast_nullable_to_non_nullable
as bool,isLargeFile: null == isLargeFile ? _self.isLargeFile : isLargeFile // ignore: cast_nullable_to_non_nullable
as bool,isTruncated: null == isTruncated ? _self.isTruncated : isTruncated // ignore: cast_nullable_to_non_nullable
as bool,isUntracked: null == isUntracked ? _self.isUntracked : isUntracked // ignore: cast_nullable_to_non_nullable
as bool,linesAdded: null == linesAdded ? _self.linesAdded : linesAdded // ignore: cast_nullable_to_non_nullable
as int,linesRemoved: null == linesRemoved ? _self.linesRemoved : linesRemoved // ignore: cast_nullable_to_non_nullable
as int,unifiedPatch: null == unifiedPatch ? _self.unifiedPatch : unifiedPatch // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$TurnDiff {

 String get id; String get assistantMessageId; String get userPromptPreview; DateTime get timestamp; TurnDiffSource get source; List<TurnDiffFile> get files; int get filesChanged; int get linesAdded; int get linesRemoved; List<String> get changedFilePaths;
/// Create a copy of TurnDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnDiffCopyWith<TurnDiff> get copyWith => _$TurnDiffCopyWithImpl<TurnDiff>(this as TurnDiff, _$identity);

  /// Serializes this TurnDiff to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TurnDiff;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnDiff&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.assistantMessageId, _this.assistantMessageId) || other.assistantMessageId == _this.assistantMessageId)&&(identical(other.userPromptPreview, _this.userPromptPreview) || other.userPromptPreview == _this.userPromptPreview)&&(identical(other.timestamp, _this.timestamp) || other.timestamp == _this.timestamp)&&(identical(other.source, _this.source) || other.source == _this.source)&&const DeepCollectionEquality().equals(other.files, _this.files)&&(identical(other.filesChanged, _this.filesChanged) || other.filesChanged == _this.filesChanged)&&(identical(other.linesAdded, _this.linesAdded) || other.linesAdded == _this.linesAdded)&&(identical(other.linesRemoved, _this.linesRemoved) || other.linesRemoved == _this.linesRemoved)&&const DeepCollectionEquality().equals(other.changedFilePaths, _this.changedFilePaths));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TurnDiff;
  return Object.hash(runtimeType,_this.id,_this.assistantMessageId,_this.userPromptPreview,_this.timestamp,_this.source,const DeepCollectionEquality().hash(_this.files),_this.filesChanged,_this.linesAdded,_this.linesRemoved,const DeepCollectionEquality().hash(_this.changedFilePaths));
}

@override
String toString() {
  final _this = this as TurnDiff;
  return 'TurnDiff(id: ${_this.id}, assistantMessageId: ${_this.assistantMessageId}, userPromptPreview: ${_this.userPromptPreview}, timestamp: ${_this.timestamp}, source: ${_this.source}, files: ${_this.files}, filesChanged: ${_this.filesChanged}, linesAdded: ${_this.linesAdded}, linesRemoved: ${_this.linesRemoved}, changedFilePaths: ${_this.changedFilePaths})';
}


}

/// @nodoc
abstract mixin class $TurnDiffCopyWith<$Res>  {
  factory $TurnDiffCopyWith(TurnDiff value, $Res Function(TurnDiff) _then) = _$TurnDiffCopyWithImpl;
@useResult
$Res call({
 String id, String assistantMessageId, String userPromptPreview, DateTime timestamp, TurnDiffSource source, List<TurnDiffFile> files, int filesChanged, int linesAdded, int linesRemoved, List<String> changedFilePaths
});




}
/// @nodoc
class _$TurnDiffCopyWithImpl<$Res>
    implements $TurnDiffCopyWith<$Res> {
  _$TurnDiffCopyWithImpl(this._self, this._then);

  final TurnDiff _self;
  final $Res Function(TurnDiff) _then;

/// Create a copy of TurnDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? assistantMessageId = null,Object? userPromptPreview = null,Object? timestamp = null,Object? source = null,Object? files = null,Object? filesChanged = null,Object? linesAdded = null,Object? linesRemoved = null,Object? changedFilePaths = null,}) {
  return _then(TurnDiff(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,assistantMessageId: null == assistantMessageId ? _self.assistantMessageId : assistantMessageId // ignore: cast_nullable_to_non_nullable
as String,userPromptPreview: null == userPromptPreview ? _self.userPromptPreview : userPromptPreview // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as TurnDiffSource,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as List<TurnDiffFile>,filesChanged: null == filesChanged ? _self.filesChanged : filesChanged // ignore: cast_nullable_to_non_nullable
as int,linesAdded: null == linesAdded ? _self.linesAdded : linesAdded // ignore: cast_nullable_to_non_nullable
as int,linesRemoved: null == linesRemoved ? _self.linesRemoved : linesRemoved // ignore: cast_nullable_to_non_nullable
as int,changedFilePaths: null == changedFilePaths ? _self.changedFilePaths : changedFilePaths // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [TurnDiff].
extension TurnDiffPatterns on TurnDiff {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnDiff value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnDiff() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnDiff value)  $default,){
final _that = this;
switch (_that) {
case _TurnDiff():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnDiff value)?  $default,){
final _that = this;
switch (_that) {
case _TurnDiff() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String assistantMessageId,  String userPromptPreview,  DateTime timestamp,  TurnDiffSource source,  List<TurnDiffFile> files,  int filesChanged,  int linesAdded,  int linesRemoved,  List<String> changedFilePaths)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnDiff() when $default != null:
return $default(_that.id,_that.assistantMessageId,_that.userPromptPreview,_that.timestamp,_that.source,_that.files,_that.filesChanged,_that.linesAdded,_that.linesRemoved,_that.changedFilePaths);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String assistantMessageId,  String userPromptPreview,  DateTime timestamp,  TurnDiffSource source,  List<TurnDiffFile> files,  int filesChanged,  int linesAdded,  int linesRemoved,  List<String> changedFilePaths)  $default,) {final _that = this;
switch (_that) {
case _TurnDiff():
return $default(_that.id,_that.assistantMessageId,_that.userPromptPreview,_that.timestamp,_that.source,_that.files,_that.filesChanged,_that.linesAdded,_that.linesRemoved,_that.changedFilePaths);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String assistantMessageId,  String userPromptPreview,  DateTime timestamp,  TurnDiffSource source,  List<TurnDiffFile> files,  int filesChanged,  int linesAdded,  int linesRemoved,  List<String> changedFilePaths)?  $default,) {final _that = this;
switch (_that) {
case _TurnDiff() when $default != null:
return $default(_that.id,_that.assistantMessageId,_that.userPromptPreview,_that.timestamp,_that.source,_that.files,_that.filesChanged,_that.linesAdded,_that.linesRemoved,_that.changedFilePaths);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TurnDiff extends TurnDiff {
  const _TurnDiff({required this.id, required this.assistantMessageId, required this.userPromptPreview, required this.timestamp, this.source = TurnDiffSource.tool,  List<TurnDiffFile> files = const <TurnDiffFile>[], this.filesChanged = 0, this.linesAdded = 0, this.linesRemoved = 0,  List<String> changedFilePaths = const <String>[]}): _files = files,_changedFilePaths = changedFilePaths,super._();
  factory _TurnDiff.fromJson(Map<String, dynamic> json) => _$TurnDiffFromJson(json);

@override final  String id;
@override final  String assistantMessageId;
@override final  String userPromptPreview;
@override final  DateTime timestamp;
@override@JsonKey() final  TurnDiffSource source;
 final  List<TurnDiffFile> _files;
@override@JsonKey() List<TurnDiffFile> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

@override@JsonKey() final  int filesChanged;
@override@JsonKey() final  int linesAdded;
@override@JsonKey() final  int linesRemoved;
 final  List<String> _changedFilePaths;
@override@JsonKey() List<String> get changedFilePaths {
  if (_changedFilePaths is EqualUnmodifiableListView) return _changedFilePaths;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changedFilePaths);
}


/// Create a copy of TurnDiff
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnDiffCopyWith<_TurnDiff> get copyWith => __$TurnDiffCopyWithImpl<_TurnDiff>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TurnDiffToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnDiff&&(identical(other.id, id) || other.id == id)&&(identical(other.assistantMessageId, assistantMessageId) || other.assistantMessageId == assistantMessageId)&&(identical(other.userPromptPreview, userPromptPreview) || other.userPromptPreview == userPromptPreview)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.files, _files)&&(identical(other.filesChanged, filesChanged) || other.filesChanged == filesChanged)&&(identical(other.linesAdded, linesAdded) || other.linesAdded == linesAdded)&&(identical(other.linesRemoved, linesRemoved) || other.linesRemoved == linesRemoved)&&const DeepCollectionEquality().equals(other.changedFilePaths, _changedFilePaths));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,assistantMessageId,userPromptPreview,timestamp,source,const DeepCollectionEquality().hash(_files),filesChanged,linesAdded,linesRemoved,const DeepCollectionEquality().hash(_changedFilePaths));
}

@override
String toString() {
    return 'TurnDiff(id: $id, assistantMessageId: $assistantMessageId, userPromptPreview: $userPromptPreview, timestamp: $timestamp, source: $source, files: $files, filesChanged: $filesChanged, linesAdded: $linesAdded, linesRemoved: $linesRemoved, changedFilePaths: $changedFilePaths)';
}


}

/// @nodoc
abstract mixin class _$TurnDiffCopyWith<$Res> implements $TurnDiffCopyWith<$Res> {
  factory _$TurnDiffCopyWith(_TurnDiff value, $Res Function(_TurnDiff) _then) = __$TurnDiffCopyWithImpl;
@override @useResult
$Res call({
 String id, String assistantMessageId, String userPromptPreview, DateTime timestamp, TurnDiffSource source, List<TurnDiffFile> files, int filesChanged, int linesAdded, int linesRemoved, List<String> changedFilePaths
});




}
/// @nodoc
class __$TurnDiffCopyWithImpl<$Res>
    implements _$TurnDiffCopyWith<$Res> {
  __$TurnDiffCopyWithImpl(this._self, this._then);

  final _TurnDiff _self;
  final $Res Function(_TurnDiff) _then;

/// Create a copy of TurnDiff
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? assistantMessageId = null,Object? userPromptPreview = null,Object? timestamp = null,Object? source = null,Object? files = null,Object? filesChanged = null,Object? linesAdded = null,Object? linesRemoved = null,Object? changedFilePaths = null,}) {
  return _then(_TurnDiff(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,assistantMessageId: null == assistantMessageId ? _self.assistantMessageId : assistantMessageId // ignore: cast_nullable_to_non_nullable
as String,userPromptPreview: null == userPromptPreview ? _self.userPromptPreview : userPromptPreview // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as TurnDiffSource,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<TurnDiffFile>,filesChanged: null == filesChanged ? _self.filesChanged : filesChanged // ignore: cast_nullable_to_non_nullable
as int,linesAdded: null == linesAdded ? _self.linesAdded : linesAdded // ignore: cast_nullable_to_non_nullable
as int,linesRemoved: null == linesRemoved ? _self.linesRemoved : linesRemoved // ignore: cast_nullable_to_non_nullable
as int,changedFilePaths: null == changedFilePaths ? _self._changedFilePaths : changedFilePaths // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
