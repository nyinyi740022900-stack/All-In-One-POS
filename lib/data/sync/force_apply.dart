/// Result of [SyncRemote.forceApply] — server-side heal that bypasses RLS
/// after JWT shop_id verification (Edge Function `sync_force_apply`).
enum ForceApplyStatus {
  /// Row written successfully via service role.
  applied,

  /// Remote already had this id for the shop — safe to clear outbox.
  alreadyThere,

  /// Payload failed validation / not allowlisted — client decides drop vs keep.
  rejectedInvalid,

  /// Network / auth / temporary server error — retry next sync.
  transient,
}

class ForceApplyResult {
  final ForceApplyStatus status;
  final String? detail;
  const ForceApplyResult(this.status, {this.detail});
}
