/// Boundary for a future Cloudflare sync implementation.
typedef SyncSnapshot = Map<String, List<Map<String, Object?>>>;

abstract interface class CloudSyncClient {
  Future<void> upload(SyncSnapshot snapshot);
  Future<SyncSnapshot?> download();
}
