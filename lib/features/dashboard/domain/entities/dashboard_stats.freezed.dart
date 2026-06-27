// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dashboard_stats.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DashboardStats {

 int get sessionCount; int get messageCount; int get totalTokens; int get activeDays; int get currentStreakDays; int get longestStreakDays; int? get peakHour; ActivityHeatmap get heatmap; double? get funFactMultiple;
/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DashboardStatsCopyWith<DashboardStats> get copyWith => _$DashboardStatsCopyWithImpl<DashboardStats>(this as DashboardStats, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DashboardStats&&(identical(other.sessionCount, sessionCount) || other.sessionCount == sessionCount)&&(identical(other.messageCount, messageCount) || other.messageCount == messageCount)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.activeDays, activeDays) || other.activeDays == activeDays)&&(identical(other.currentStreakDays, currentStreakDays) || other.currentStreakDays == currentStreakDays)&&(identical(other.longestStreakDays, longestStreakDays) || other.longestStreakDays == longestStreakDays)&&(identical(other.peakHour, peakHour) || other.peakHour == peakHour)&&(identical(other.heatmap, heatmap) || other.heatmap == heatmap)&&(identical(other.funFactMultiple, funFactMultiple) || other.funFactMultiple == funFactMultiple));
}


@override
int get hashCode => Object.hash(runtimeType,sessionCount,messageCount,totalTokens,activeDays,currentStreakDays,longestStreakDays,peakHour,heatmap,funFactMultiple);

@override
String toString() {
  return 'DashboardStats(sessionCount: $sessionCount, messageCount: $messageCount, totalTokens: $totalTokens, activeDays: $activeDays, currentStreakDays: $currentStreakDays, longestStreakDays: $longestStreakDays, peakHour: $peakHour, heatmap: $heatmap, funFactMultiple: $funFactMultiple)';
}


}

/// @nodoc
abstract mixin class $DashboardStatsCopyWith<$Res>  {
  factory $DashboardStatsCopyWith(DashboardStats value, $Res Function(DashboardStats) _then) = _$DashboardStatsCopyWithImpl;
@useResult
$Res call({
 int sessionCount, int messageCount, int totalTokens, int activeDays, int currentStreakDays, int longestStreakDays, int? peakHour, ActivityHeatmap heatmap, double? funFactMultiple
});


$ActivityHeatmapCopyWith<$Res> get heatmap;

}
/// @nodoc
class _$DashboardStatsCopyWithImpl<$Res>
    implements $DashboardStatsCopyWith<$Res> {
  _$DashboardStatsCopyWithImpl(this._self, this._then);

  final DashboardStats _self;
  final $Res Function(DashboardStats) _then;

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionCount = null,Object? messageCount = null,Object? totalTokens = null,Object? activeDays = null,Object? currentStreakDays = null,Object? longestStreakDays = null,Object? peakHour = freezed,Object? heatmap = null,Object? funFactMultiple = freezed,}) {
  return _then(_self.copyWith(
sessionCount: null == sessionCount ? _self.sessionCount : sessionCount // ignore: cast_nullable_to_non_nullable
as int,messageCount: null == messageCount ? _self.messageCount : messageCount // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,activeDays: null == activeDays ? _self.activeDays : activeDays // ignore: cast_nullable_to_non_nullable
as int,currentStreakDays: null == currentStreakDays ? _self.currentStreakDays : currentStreakDays // ignore: cast_nullable_to_non_nullable
as int,longestStreakDays: null == longestStreakDays ? _self.longestStreakDays : longestStreakDays // ignore: cast_nullable_to_non_nullable
as int,peakHour: freezed == peakHour ? _self.peakHour : peakHour // ignore: cast_nullable_to_non_nullable
as int?,heatmap: null == heatmap ? _self.heatmap : heatmap // ignore: cast_nullable_to_non_nullable
as ActivityHeatmap,funFactMultiple: freezed == funFactMultiple ? _self.funFactMultiple : funFactMultiple // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}
/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityHeatmapCopyWith<$Res> get heatmap {
  
  return $ActivityHeatmapCopyWith<$Res>(_self.heatmap, (value) {
    return _then(_self.copyWith(heatmap: value));
  });
}
}


/// Adds pattern-matching-related methods to [DashboardStats].
extension DashboardStatsPatterns on DashboardStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DashboardStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DashboardStats value)  $default,){
final _that = this;
switch (_that) {
case _DashboardStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DashboardStats value)?  $default,){
final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int sessionCount,  int messageCount,  int totalTokens,  int activeDays,  int currentStreakDays,  int longestStreakDays,  int? peakHour,  ActivityHeatmap heatmap,  double? funFactMultiple)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
return $default(_that.sessionCount,_that.messageCount,_that.totalTokens,_that.activeDays,_that.currentStreakDays,_that.longestStreakDays,_that.peakHour,_that.heatmap,_that.funFactMultiple);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int sessionCount,  int messageCount,  int totalTokens,  int activeDays,  int currentStreakDays,  int longestStreakDays,  int? peakHour,  ActivityHeatmap heatmap,  double? funFactMultiple)  $default,) {final _that = this;
switch (_that) {
case _DashboardStats():
return $default(_that.sessionCount,_that.messageCount,_that.totalTokens,_that.activeDays,_that.currentStreakDays,_that.longestStreakDays,_that.peakHour,_that.heatmap,_that.funFactMultiple);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int sessionCount,  int messageCount,  int totalTokens,  int activeDays,  int currentStreakDays,  int longestStreakDays,  int? peakHour,  ActivityHeatmap heatmap,  double? funFactMultiple)?  $default,) {final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
return $default(_that.sessionCount,_that.messageCount,_that.totalTokens,_that.activeDays,_that.currentStreakDays,_that.longestStreakDays,_that.peakHour,_that.heatmap,_that.funFactMultiple);case _:
  return null;

}
}

}

/// @nodoc


class _DashboardStats implements DashboardStats {
  const _DashboardStats({this.sessionCount = 0, this.messageCount = 0, this.totalTokens = 0, this.activeDays = 0, this.currentStreakDays = 0, this.longestStreakDays = 0, this.peakHour, required this.heatmap, this.funFactMultiple});
  

@override@JsonKey() final  int sessionCount;
@override@JsonKey() final  int messageCount;
@override@JsonKey() final  int totalTokens;
@override@JsonKey() final  int activeDays;
@override@JsonKey() final  int currentStreakDays;
@override@JsonKey() final  int longestStreakDays;
@override final  int? peakHour;
@override final  ActivityHeatmap heatmap;
@override final  double? funFactMultiple;

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DashboardStatsCopyWith<_DashboardStats> get copyWith => __$DashboardStatsCopyWithImpl<_DashboardStats>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardStats&&(identical(other.sessionCount, sessionCount) || other.sessionCount == sessionCount)&&(identical(other.messageCount, messageCount) || other.messageCount == messageCount)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.activeDays, activeDays) || other.activeDays == activeDays)&&(identical(other.currentStreakDays, currentStreakDays) || other.currentStreakDays == currentStreakDays)&&(identical(other.longestStreakDays, longestStreakDays) || other.longestStreakDays == longestStreakDays)&&(identical(other.peakHour, peakHour) || other.peakHour == peakHour)&&(identical(other.heatmap, heatmap) || other.heatmap == heatmap)&&(identical(other.funFactMultiple, funFactMultiple) || other.funFactMultiple == funFactMultiple));
}


@override
int get hashCode => Object.hash(runtimeType,sessionCount,messageCount,totalTokens,activeDays,currentStreakDays,longestStreakDays,peakHour,heatmap,funFactMultiple);

@override
String toString() {
  return 'DashboardStats(sessionCount: $sessionCount, messageCount: $messageCount, totalTokens: $totalTokens, activeDays: $activeDays, currentStreakDays: $currentStreakDays, longestStreakDays: $longestStreakDays, peakHour: $peakHour, heatmap: $heatmap, funFactMultiple: $funFactMultiple)';
}


}

/// @nodoc
abstract mixin class _$DashboardStatsCopyWith<$Res> implements $DashboardStatsCopyWith<$Res> {
  factory _$DashboardStatsCopyWith(_DashboardStats value, $Res Function(_DashboardStats) _then) = __$DashboardStatsCopyWithImpl;
@override @useResult
$Res call({
 int sessionCount, int messageCount, int totalTokens, int activeDays, int currentStreakDays, int longestStreakDays, int? peakHour, ActivityHeatmap heatmap, double? funFactMultiple
});


@override $ActivityHeatmapCopyWith<$Res> get heatmap;

}
/// @nodoc
class __$DashboardStatsCopyWithImpl<$Res>
    implements _$DashboardStatsCopyWith<$Res> {
  __$DashboardStatsCopyWithImpl(this._self, this._then);

  final _DashboardStats _self;
  final $Res Function(_DashboardStats) _then;

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionCount = null,Object? messageCount = null,Object? totalTokens = null,Object? activeDays = null,Object? currentStreakDays = null,Object? longestStreakDays = null,Object? peakHour = freezed,Object? heatmap = null,Object? funFactMultiple = freezed,}) {
  return _then(_DashboardStats(
sessionCount: null == sessionCount ? _self.sessionCount : sessionCount // ignore: cast_nullable_to_non_nullable
as int,messageCount: null == messageCount ? _self.messageCount : messageCount // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,activeDays: null == activeDays ? _self.activeDays : activeDays // ignore: cast_nullable_to_non_nullable
as int,currentStreakDays: null == currentStreakDays ? _self.currentStreakDays : currentStreakDays // ignore: cast_nullable_to_non_nullable
as int,longestStreakDays: null == longestStreakDays ? _self.longestStreakDays : longestStreakDays // ignore: cast_nullable_to_non_nullable
as int,peakHour: freezed == peakHour ? _self.peakHour : peakHour // ignore: cast_nullable_to_non_nullable
as int?,heatmap: null == heatmap ? _self.heatmap : heatmap // ignore: cast_nullable_to_non_nullable
as ActivityHeatmap,funFactMultiple: freezed == funFactMultiple ? _self.funFactMultiple : funFactMultiple // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityHeatmapCopyWith<$Res> get heatmap {
  
  return $ActivityHeatmapCopyWith<$Res>(_self.heatmap, (value) {
    return _then(_self.copyWith(heatmap: value));
  });
}
}

/// @nodoc
mixin _$ActivityHeatmap {

 DateTime get startDay; DateTime get endDay; List<int> get dailyCounts; List<int> get dailyBuckets;
/// Create a copy of ActivityHeatmap
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityHeatmapCopyWith<ActivityHeatmap> get copyWith => _$ActivityHeatmapCopyWithImpl<ActivityHeatmap>(this as ActivityHeatmap, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityHeatmap&&(identical(other.startDay, startDay) || other.startDay == startDay)&&(identical(other.endDay, endDay) || other.endDay == endDay)&&const DeepCollectionEquality().equals(other.dailyCounts, dailyCounts)&&const DeepCollectionEquality().equals(other.dailyBuckets, dailyBuckets));
}


@override
int get hashCode => Object.hash(runtimeType,startDay,endDay,const DeepCollectionEquality().hash(dailyCounts),const DeepCollectionEquality().hash(dailyBuckets));

@override
String toString() {
  return 'ActivityHeatmap(startDay: $startDay, endDay: $endDay, dailyCounts: $dailyCounts, dailyBuckets: $dailyBuckets)';
}


}

/// @nodoc
abstract mixin class $ActivityHeatmapCopyWith<$Res>  {
  factory $ActivityHeatmapCopyWith(ActivityHeatmap value, $Res Function(ActivityHeatmap) _then) = _$ActivityHeatmapCopyWithImpl;
@useResult
$Res call({
 DateTime startDay, DateTime endDay, List<int> dailyCounts, List<int> dailyBuckets
});




}
/// @nodoc
class _$ActivityHeatmapCopyWithImpl<$Res>
    implements $ActivityHeatmapCopyWith<$Res> {
  _$ActivityHeatmapCopyWithImpl(this._self, this._then);

  final ActivityHeatmap _self;
  final $Res Function(ActivityHeatmap) _then;

/// Create a copy of ActivityHeatmap
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? startDay = null,Object? endDay = null,Object? dailyCounts = null,Object? dailyBuckets = null,}) {
  return _then(_self.copyWith(
startDay: null == startDay ? _self.startDay : startDay // ignore: cast_nullable_to_non_nullable
as DateTime,endDay: null == endDay ? _self.endDay : endDay // ignore: cast_nullable_to_non_nullable
as DateTime,dailyCounts: null == dailyCounts ? _self.dailyCounts : dailyCounts // ignore: cast_nullable_to_non_nullable
as List<int>,dailyBuckets: null == dailyBuckets ? _self.dailyBuckets : dailyBuckets // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

}


/// Adds pattern-matching-related methods to [ActivityHeatmap].
extension ActivityHeatmapPatterns on ActivityHeatmap {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityHeatmap value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityHeatmap() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityHeatmap value)  $default,){
final _that = this;
switch (_that) {
case _ActivityHeatmap():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityHeatmap value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityHeatmap() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime startDay,  DateTime endDay,  List<int> dailyCounts,  List<int> dailyBuckets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityHeatmap() when $default != null:
return $default(_that.startDay,_that.endDay,_that.dailyCounts,_that.dailyBuckets);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime startDay,  DateTime endDay,  List<int> dailyCounts,  List<int> dailyBuckets)  $default,) {final _that = this;
switch (_that) {
case _ActivityHeatmap():
return $default(_that.startDay,_that.endDay,_that.dailyCounts,_that.dailyBuckets);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime startDay,  DateTime endDay,  List<int> dailyCounts,  List<int> dailyBuckets)?  $default,) {final _that = this;
switch (_that) {
case _ActivityHeatmap() when $default != null:
return $default(_that.startDay,_that.endDay,_that.dailyCounts,_that.dailyBuckets);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityHeatmap implements ActivityHeatmap {
  const _ActivityHeatmap({required this.startDay, required this.endDay, final  List<int> dailyCounts = const <int>[], final  List<int> dailyBuckets = const <int>[]}): _dailyCounts = dailyCounts,_dailyBuckets = dailyBuckets;
  

@override final  DateTime startDay;
@override final  DateTime endDay;
 final  List<int> _dailyCounts;
@override@JsonKey() List<int> get dailyCounts {
  if (_dailyCounts is EqualUnmodifiableListView) return _dailyCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dailyCounts);
}

 final  List<int> _dailyBuckets;
@override@JsonKey() List<int> get dailyBuckets {
  if (_dailyBuckets is EqualUnmodifiableListView) return _dailyBuckets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dailyBuckets);
}


/// Create a copy of ActivityHeatmap
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityHeatmapCopyWith<_ActivityHeatmap> get copyWith => __$ActivityHeatmapCopyWithImpl<_ActivityHeatmap>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityHeatmap&&(identical(other.startDay, startDay) || other.startDay == startDay)&&(identical(other.endDay, endDay) || other.endDay == endDay)&&const DeepCollectionEquality().equals(other._dailyCounts, _dailyCounts)&&const DeepCollectionEquality().equals(other._dailyBuckets, _dailyBuckets));
}


@override
int get hashCode => Object.hash(runtimeType,startDay,endDay,const DeepCollectionEquality().hash(_dailyCounts),const DeepCollectionEquality().hash(_dailyBuckets));

@override
String toString() {
  return 'ActivityHeatmap(startDay: $startDay, endDay: $endDay, dailyCounts: $dailyCounts, dailyBuckets: $dailyBuckets)';
}


}

/// @nodoc
abstract mixin class _$ActivityHeatmapCopyWith<$Res> implements $ActivityHeatmapCopyWith<$Res> {
  factory _$ActivityHeatmapCopyWith(_ActivityHeatmap value, $Res Function(_ActivityHeatmap) _then) = __$ActivityHeatmapCopyWithImpl;
@override @useResult
$Res call({
 DateTime startDay, DateTime endDay, List<int> dailyCounts, List<int> dailyBuckets
});




}
/// @nodoc
class __$ActivityHeatmapCopyWithImpl<$Res>
    implements _$ActivityHeatmapCopyWith<$Res> {
  __$ActivityHeatmapCopyWithImpl(this._self, this._then);

  final _ActivityHeatmap _self;
  final $Res Function(_ActivityHeatmap) _then;

/// Create a copy of ActivityHeatmap
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startDay = null,Object? endDay = null,Object? dailyCounts = null,Object? dailyBuckets = null,}) {
  return _then(_ActivityHeatmap(
startDay: null == startDay ? _self.startDay : startDay // ignore: cast_nullable_to_non_nullable
as DateTime,endDay: null == endDay ? _self.endDay : endDay // ignore: cast_nullable_to_non_nullable
as DateTime,dailyCounts: null == dailyCounts ? _self._dailyCounts : dailyCounts // ignore: cast_nullable_to_non_nullable
as List<int>,dailyBuckets: null == dailyBuckets ? _self._dailyBuckets : dailyBuckets // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}


}

// dart format on
