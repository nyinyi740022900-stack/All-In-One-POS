/// Rows at/above this attempts count are treated as likely "poison pill"
/// writes and should be surfaced explicitly before destructive transitions.
const kOutboxStuckThreshold = 3;
