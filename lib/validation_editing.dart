part of 'main.dart';

enum _ValidationDraftType {
  purchase('stock_additions'),
  sale('sales'),
  transfer('stock_transfers'),
  customerReturn('sale_returns'),
  operation('operations');

  const _ValidationDraftType(this.table);
  final String table;

  bool get hasAttachments => this == purchase || this == sale;

  bool isPending(Map<String, Object?> row) => switch (this) {
    operation => row['completion_draft'] == 1 && row['validated_at'] == null,
    customerReturn => row['status'] == ReturnValidationStatus.pending.name,
    _ => row['draft'] == 1,
  };

  String kind(Map<String, Object?> row) => switch (this) {
    purchase =>
      row['return_purchase_id'] == null ? 'purchase' : 'supplier_return',
    sale => 'sale',
    transfer => 'transfer',
    customerReturn => 'customer_return',
    operation =>
      row['external_production'] == 1 ? 'external_production' : 'production',
  };
}

class ValidationDraftPhotos {
  ValidationDraftPhotos({required this.count, required this.previews});
  final int count;
  final List<Uint8List> previews;
  final removed = <int>{};
  int get remaining => count - removed.length;
}

class _ValidationDraft {
  const _ValidationDraft({
    required this.type,
    required this.id,
    required this.row,
    required this.localRow,
    required this.revision,
    required this.attachments,
  });

  final _ValidationDraftType type;
  final String id;
  final Map<String, Object?> row;
  final Map<String, Object?> localRow;
  final String? revision;
  final ValidationDraftPhotos attachments;
}

bool _sameDraftValue(Object? left, Object? right) =>
    left is Uint8List && right is Uint8List
    ? listEquals(left, right)
    : left == right;

const _validationAuditKey = 'validation_audit:';

extension _ValidationDraftDatabase on AppDatabase {
  Future<_ValidationDraft?> _loadValidationDraft(
    _ValidationDraftType type,
    String id, {
    required bool canViewPhotos,
  }) async {
    final database = await _database;
    final idValue = type == _ValidationDraftType.purchase ? int.parse(id) : id;
    final local = (await database.query(
      type.table,
      where: 'id = ?',
      whereArgs: [idValue],
      limit: 1,
    )).firstOrNull;
    if (local == null || !type.isPending(local)) return null;
    final cloud = cloudSync;
    final remote = cloud is SupabaseCloudSyncClient
        ? await cloud
              .validationDraft(type.table, id)
              .timeout(const Duration(seconds: 12))
        : null;
    final row = remote == null
        ? local
        : _cloudRowForDatabase(
            type.table,
            Map<String, Object?>.from(remote['row'] as Map),
          );
    final creationField = type == _ValidationDraftType.operation
        ? 'started_at'
        : 'created_at';
    if (row[creationField] != local[creationField]) {
      throw StateError(
        'La référence du brouillon diffère sur le serveur. Vérifiez la synchronisation.',
      );
    }
    final previews = type.hasAttachments && (canViewPhotos || remote == null)
        ? _imagesFromJson(row['images'] as String? ?? '[]')
        : const <Uint8List>[];
    return _ValidationDraft(
      type: type,
      id: id,
      row: row,
      localRow: local,
      revision: remote?['revision'] as String?,
      attachments: ValidationDraftPhotos(
        count: remote?['photo_count'] as int? ?? previews.length,
        previews: canViewPhotos ? previews : const [],
      ),
    );
  }

  Future<Map<String, Object?>?> _saveValidationDraft(
    _ValidationDraft draft,
    Map<String, Object?> updates, {
    required AppUser actor,
    List<Uint8List> addedPhotos = const [],
  }) async {
    final table = draft.type.table;
    final changes = Map<String, Object?>.fromEntries(
      updates.entries.where(
        (entry) => !_sameDraftValue(draft.row[entry.key], entry.value),
      ),
    );
    final removed = draft.attachments.removed.toList()..sort();
    if (changes.isEmpty && removed.isEmpty && addedPhotos.isEmpty) {
      return null;
    }
    final database = await _database;
    final idValue = draft.localRow['id'];

    Future<void> checkLocal(DatabaseExecutor executor) async {
      final current = (await executor.query(
        table,
        where: 'id = ?',
        whereArgs: [idValue],
        limit: 1,
      )).firstOrNull;
      if (current == null ||
          !draft.type.isPending(current) ||
          draft.localRow.entries.any(
            (entry) => !_sameDraftValue(current[entry.key], entry.value),
          )) {
        throw StateError(
          'Le brouillon a changé. Rouvrez-le avant de recommencer.',
        );
      }
    }

    final cloud = cloudSync;
    final revision = draft.revision;
    if (revision != null && cloud is SupabaseCloudSyncClient) {
      await checkLocal(database);
      final saved = await cloud
          .saveValidationDraft(
            table: table,
            id: draft.id,
            revision: revision,
            changes: _cloudRow(table, changes),
            removedPhotos: removed,
            addedPhotos: addedPhotos.map(base64Encode).toList(),
          )
          .timeout(const Duration(seconds: 15));
      final row = _cloudRowForDatabase(
        table,
        Map<String, Object?>.from(saved['row'] as Map),
      );
      await database.update(table, row, where: 'id = ?', whereArgs: [idValue]);
      return row;
    }

    return database.transaction((transaction) async {
      await checkLocal(transaction);
      final row = {...draft.row, ...changes};
      if (draft.type.hasAttachments &&
          (removed.isNotEmpty || addedPhotos.isNotEmpty)) {
        final original = _imagesFromJson(
          draft.row['images'] as String? ?? '[]',
        );
        row['images'] = _imagesToJson([
          for (final (index, image) in original.indexed)
            if (!draft.attachments.removed.contains(index)) image,
          ...addedPhotos,
        ]);
      }
      await transaction.update(
        table,
        row,
        where: 'id = ?',
        whereArgs: [idValue],
      );
      final time = DateTime.now().toUtc();
      const imageFields = {'final_image', 'remainder_image', 'scrap_image'};
      await transaction.insert('app_settings', {
        'key':
            '$_validationAuditKey${time.microsecondsSinceEpoch}:$table:${draft.id}',
        'value': jsonEncode({
          'occurred_at': time.toIso8601String(),
          'actor_id': actor.id,
          'event': 'validation_edit',
          'target': draft.id,
          'details': {
            'kind': draft.type.kind(row),
            'actor_name': actor.fullName,
            'local': true,
            'changes': {
              for (final entry in changes.entries)
                entry.key: {
                  'before': imageFields.contains(entry.key)
                      ? (draft.row[entry.key] == null ? null : 'Photo')
                      : draft.row[entry.key],
                  'after': imageFields.contains(entry.key)
                      ? (entry.value == null ? null : 'Photo modifiée')
                      : entry.value,
                },
              if (removed.isNotEmpty || addedPhotos.isNotEmpty)
                'images': {
                  'before': draft.attachments.count,
                  'after': draft.attachments.remaining + addedPhotos.length,
                  'removed': removed.map((index) => index + 1).toList(),
                  'added': addedPhotos.length,
                },
            },
          },
        }),
      });
      return row;
    });
  }

  Future<List<Map<String, dynamic>>> _loadLocalValidationEvents() async {
    final rows = await (await _database).query(
      'app_settings',
      columns: ['value'],
      where: 'key LIKE ?',
      whereArgs: ['$_validationAuditKey%'],
      orderBy: 'key DESC',
      limit: 500,
    );
    return [
      for (final row in rows)
        jsonDecode(row['value'] as String) as Map<String, dynamic>,
    ];
  }
}

class _ExistingDraftPhotos extends StatelessWidget {
  const _ExistingDraftPhotos({required this.photos, required this.onRemove});
  final ValidationDraftPhotos photos;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var index = 0; index < photos.count; index++)
          if (!photos.removed.contains(index))
            InputChip(
              avatar: index < photos.previews.length
                  ? ClipOval(
                      child: Image.memory(
                        photos.previews[index],
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(Icons.lock_outline, size: 16),
              label: Text('Photo ${index + 1}'),
              onPressed: index < photos.previews.length
                  ? () => _showTransactionPhotos(
                      context,
                      Future.value([photos.previews[index]]),
                    )
                  : null,
              onDeleted: () => onRemove(index),
              deleteButtonTooltipMessage: 'Retirer la photo ${index + 1}',
            ),
      ],
    ),
  );
}

class _ReturnQuantityForm extends StatefulWidget {
  const _ReturnQuantityForm({
    required this.title,
    required this.summary,
    required this.maximum,
    this.initial,
    this.receipt,
    this.onSaveReceipt,
  });

  final String title;
  final String summary;
  final int maximum;
  final int? initial;
  final String? receipt;
  final ValueChanged<String>? onSaveReceipt;

  @override
  State<_ReturnQuantityForm> createState() => _ReturnQuantityFormState();
}

class _ReturnQuantityFormState extends State<_ReturnQuantityForm> {
  final _form = GlobalKey<FormState>();
  late final _pieces = TextEditingController(text: widget.initial?.toString());
  late final _receipt = TextEditingController(text: widget.receipt);

  @override
  void dispose() {
    _pieces.dispose();
    _receipt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: widget.title,
    subtitle: widget.summary,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _pieces,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Pièces retournées *'),
            validator: (value) {
              final pieces = int.tryParse(value ?? '') ?? 0;
              return pieces < 1 || pieces > widget.maximum
                  ? 'Quantité autorisée : de 1 à ${widget.maximum} pièce(s).'
                  : null;
            },
          ),
          if (widget.receipt != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _receipt,
              decoration: const InputDecoration(labelText: 'N° de bon *'),
              validator: required,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                widget.onSaveReceipt?.call(_receipt.text.trim());
                Navigator.pop(context, int.parse(_pieces.text));
              }
            },
            child: Text(
              widget.initial == null
                  ? 'Envoyer à la validation'
                  : 'Enregistrer les modifications',
            ),
          ),
        ],
      ),
    ),
  );
}
