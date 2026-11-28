import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A complete, transport-neutral representation of the workshop's local data.
typedef SyncSnapshot = Map<String, List<Map<String, Object?>>>;

abstract interface class CloudSyncClient {
  Future<void> upload(SyncSnapshot snapshot);
  Future<SyncSnapshot?> download();
}

/// Stores the workshop snapshot in Supabase. Authentication and row-level
/// security are enforced by the database; this client never uses a service
/// role key in the mobile application.
class SupabaseCloudSyncClient implements CloudSyncClient {
  SupabaseCloudSyncClient(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> validationDraft(String table, String id) async {
    final result = await _client.rpc(
      'get_forage_validation_draft',
      params: {'p_table': table, 'p_id': id},
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> saveValidationDraft({
    required String table,
    required String id,
    required String revision,
    required Map<String, Object?> changes,
    required List<int> removedPhotos,
    required List<String> addedPhotos,
  }) async {
    final result = await _client.rpc(
      'edit_forage_validation_draft',
      params: {
        'p_table': table,
        'p_id': id,
        'p_revision': revision,
        'p_changes': changes,
        'p_removed_photos': removedPhotos,
        'p_added_photos': addedPhotos,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Uint8List>> loadTransactionPhotos({
    required bool sale,
    required String id,
  }) async {
    final photos = await _client.rpc(
      'get_forage_transaction_photos',
      params: {'p_sale': sale, 'p_id': id},
    );
    return (photos as List).cast<String>().map(base64Decode).toList();
  }

  @override
  Future<void> upload(SyncSnapshot snapshot) async {
    await _client.rpc('save_forage_workshop', params: {'p_snapshot': snapshot});
  }

  @override
  Future<SyncSnapshot?> download() async {
    final snapshot = await _downloadWorkshop();
    if (snapshot == null) {
      return null;
    }
    if (snapshot is! Map) {
      throw const FormatException('Réponse serveur invalide.');
    }

    final result = <String, List<Map<String, Object?>>>{};
    for (final entry in snapshot.entries) {
      if (entry.value is! List) {
        throw const FormatException(
          'La synchronisation distante est invalide.',
        );
      }
      result[entry.key.toString()] = (entry.value as List).map((rawRow) {
        if (rawRow is! Map) {
          throw const FormatException(
            'La synchronisation distante est invalide.',
          );
        }
        return Map<String, Object?>.fromEntries(
          rawRow.entries.map(
            (field) => MapEntry(field.key.toString(), field.value),
          ),
        );
      }).toList();
    }
    return result;
  }

  Future<dynamic> _downloadWorkshop() async {
    try {
      return await _client.rpc(
        'get_forage_workshop',
        params: {
          'p_include_families': true,
          'p_include_catalog_families': true,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202') rethrow;
      return _client.rpc('get_forage_workshop');
    }
  }
}
