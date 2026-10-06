import 'package:freezed_annotation/freezed_annotation.dart';

part 'farm_run_record.freezed.dart';
part 'farm_run_record.g.dart';

/// One entry in the FARM run ledger: a background run started, or an
/// unattended attempt skipped and why.
///
/// The ledger is FARM5's observability minimum, adopted on 2026-09-26 in place
/// of the OBS1 gate: every unattended decision leaves a record a person can
/// read the next morning. The LL13 registry still holds each run's result.
@freezed
abstract class FarmRunRecord with _$FarmRunRecord {
  const factory FarmRunRecord({
    required String id,
    required String projectId,

    /// `manual` (Run in background) or `unattended` (idle maintenance).
    required String trigger,
    required DateTime at,

    /// `enqueued` or `skipped`.
    required String outcome,
    @Default('') String taskId,
    @Default('') String command,
    @Default('') String branch,

    /// For a skip: the machine reason, such as `daily_limit` or `needsHuman`.
    @Default('') String detail,
  }) = _FarmRunRecord;

  factory FarmRunRecord.fromJson(Map<String, dynamic> json) =>
      _$FarmRunRecordFromJson(json);
}
