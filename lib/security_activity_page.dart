import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecurityActivityPage extends StatefulWidget {
  const SecurityActivityPage({
    super.key,
    this.loadEvents,
    this.loadLocalEvents,
  });
  final Future<List<Map<String, dynamic>>> Function()? loadEvents;
  final Future<List<Map<String, dynamic>>> Function()? loadLocalEvents;

  @override
  State<SecurityActivityPage> createState() => _SecurityActivityPageState();
}

const _actions = {
  'validation_edit': 'Correction de validation',
  'admin_rate_limit': 'Trop de tentatives de création de comptes',
  'device_rate_limit': 'Trop de demandes d’appareil',
  'device_requested': 'Nouvel appareil en attente',
  'device_login': 'Connexion sur un appareil autorisé',
  'profiles:insert': 'Compte créé',
  'profiles:update': 'Compte ou permissions modifiés',
  'trusted_devices:insert': 'Appareil enregistré',
  'trusted_devices:update': 'État d’un appareil modifié',
  'device_access_requests:update': 'Demande d’appareil traitée',
};

const _operations = {
  'purchase': 'Achat',
  'sale': 'Vente',
  'supplier_return': 'Retour fournisseur',
  'customer_return': 'Retour client',
  'transfer': 'Transfert',
  'production': 'Production',
  'external_production': 'Travail externe',
};

const _fields = {
  'pieces': 'Pièces',
  'quantity': 'Quantité',
  'unit': 'Unité',
  'product_id': 'Produit',
  'client_id': 'Client',
  'supplier_id': 'Fournisseur',
  'receipt_number': 'N° de bon',
  'transport_charge': 'Transport',
  'depot_id': 'Dépôt',
  'source_depot_id': 'Dépôt de départ',
  'destination_depot_id': 'Dépôt d’arrivée',
  'output_pieces': 'Pièces fabriquées',
  'output_depot_id': 'Dépôt du produit fini',
  'remainder_pieces': 'Pièces restantes',
  'remainder_depot_id': 'Dépôt des pièces restantes',
  'scrap_pieces': 'Quantité de déchets',
  'scrap_depot_id': 'Dépôt des déchets',
  'scrap_product_id': 'Produit de déchets',
  'images': 'Photos jointes',
  'final_image': 'Photo du produit fabriqué',
  'remainder_image': 'Photo des pièces restantes',
  'scrap_image': 'Photo des déchets',
};

typedef _Filters = ({
  String action,
  String operation,
  String field,
  String actor,
  DateTimeRange? period,
});
const _emptyFilters = (
  action: '',
  operation: '',
  field: '',
  actor: '',
  period: null,
);

DateTime? _time(Map<String, dynamic> event) =>
    DateTime.tryParse(event['occurred_at']?.toString() ?? '')?.toLocal();

DateTime _endExclusive(DateTimeRange range) =>
    DateTime(range.end.year, range.end.month, range.end.day + 1);

class _SecurityActivityPageState extends State<SecurityActivityPage> {
  final _search = TextEditingController();
  _Filters _filters = _emptyFilters;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _local = [];
  Timer? _timer;
  bool _loading = false;
  bool _unavailable = false;
  bool _hasMore = false;
  int _limit = 100;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading) unawaited(_refresh());
    });
  }

  Future<List<Map<String, dynamic>>> _load(_Filters filters, int limit) async {
    if (widget.loadEvents case final load?) return load();
    final client = Supabase.instance.client;
    if (await client.rpc('is_admin') != true) {
      throw StateError('Accès administrateur requis.');
    }
    var query = client
        .from('forage_security_events')
        .select('occurred_at,actor_id,event,target,details');
    if (filters.action.isNotEmpty) query = query.eq('event', filters.action);
    if (filters.operation.isNotEmpty) {
      query = query.eq('details->>kind', filters.operation);
    }
    if (filters.field.isNotEmpty) {
      query = query.not('details->changes->${filters.field}', 'is', null);
    }
    if (filters.period case final range?) {
      query = query
          .gte('occurred_at', range.start.toUtc().toIso8601String())
          .lt('occurred_at', _endExclusive(range).toUtc().toIso8601String());
    }
    return query.order('id', ascending: false).limit(limit + 1);
  }

  Future<void> _refresh() async {
    final request = ++_request;
    final limit = _limit;
    setState(() => _loading = true);
    List<Map<String, dynamic>>? remote;
    var local = _local;
    try {
      remote = await _load(
        _filters,
        limit,
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // A server outage does not prevent reading local corrections.
    }
    if (widget.loadLocalEvents case final load?) {
      try {
        local = await load();
      } catch (_) {
        // Keep the most recent local result.
      }
    }
    if (!mounted || request != _request) return;
    setState(() {
      _events = remote?.take(limit).toList() ?? [];
      _local = local;
      _hasMore = widget.loadEvents == null && (remote?.length ?? 0) > limit;
      _unavailable = remote == null;
      _loading = false;
    });
  }

  bool _matches(Map<String, dynamic> entry) {
    final action = '${entry['event']}';
    final details = entry['details'] as Map? ?? const {};
    final operation = '${details['kind']}';
    final changes = details['changes'] as Map? ?? const {};
    final actor = '${details['actor_name'] ?? ''} ${entry['actor_id'] ?? ''}';
    if (_filters.action.isNotEmpty && _filters.action != action ||
        _filters.operation.isNotEmpty && _filters.operation != operation ||
        _filters.field.isNotEmpty && !changes.containsKey(_filters.field) ||
        !actor.toLowerCase().contains(_filters.actor.toLowerCase())) {
      return false;
    }
    if (_filters.period case final period?) {
      final time = _time(entry);
      if (time == null ||
          time.isBefore(period.start) ||
          !time.isBefore(_endExclusive(period))) {
        return false;
      }
    }
    final text = [
      _actions[action] ?? action,
      _operations[operation] ?? '',
      entry['target'],
      details['record'],
      actor,
      ...changes.values,
      for (final key in changes.keys) _fields[key] ?? key,
    ].join(' ').toLowerCase();
    return _search.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_Filters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SecurityFilterForm(initial: _filters),
    );
    if (!mounted || result == null) return;
    _filters = result;
    _limit = 100;
    await _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = [..._events, ..._local].where(_matches).toList()
      ..sort(
        (a, b) =>
            (_time(b) ?? DateTime(1970)).compareTo(_time(a) ?? DateTime(1970)),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal de sécurité'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              if (_loading) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Rechercher par nom, référence ou valeur',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${events.length} événement(s) affiché(s)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openFilters,
                      icon: const Icon(Icons.tune),
                      label: Text(
                        _filters == _emptyFilters
                            ? 'Filtres'
                            : 'Filtres actifs',
                      ),
                    ),
                  ],
                ),
              ),
              if (_unavailable)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Journal du serveur indisponible. Les corrections locales restent consultables.',
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: events.length + 1,
                  itemBuilder: (context, index) {
                    if (index < events.length) {
                      return _SecurityEventTile(entry: events[index]);
                    }
                    if (_hasMore) {
                      return Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  _limit += 100;
                                  _refresh();
                                },
                          child: const Text(
                            'Charger les événements précédents',
                          ),
                        ),
                      );
                    }
                    return events.isEmpty && !_loading
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Aucun événement correspondant.'),
                          )
                        : const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityEventTile extends StatelessWidget {
  const _SecurityEventTile({required this.entry});
  final Map<String, dynamic> entry;
  String _value(Object? value) =>
      value?.toString().isNotEmpty == true ? '$value' : '—';

  @override
  Widget build(BuildContext context) {
    final action = '${entry['event'] ?? ''}';
    final details = entry['details'] as Map? ?? const {};
    final changes = details['changes'] as Map? ?? const {};
    final time = _time(entry);
    final operation = _operations[details['kind']];
    final actor = details['actor_name'] ?? entry['actor_id'];
    final title = [_actions[action] ?? action, ?operation].join(' · ');
    final subtitle = [
      if (time != null) time.toString().split('.').first,
      if (actor != null) 'Compte : $actor',
      if (details['local'] == true) 'Sur cet appareil',
      if (details['record'] != null) '${details['record']}',
      if (entry['target'] != null) 'Réf. ${entry['target']}',
      if (details['role'] != null) 'Rôle : ${details['role']}',
      if (details['status'] != null) 'État : ${details['status']}',
    ].join(' · ');
    final icon = Icon(
      action == 'validation_edit'
          ? Icons.edit_note_rounded
          : Icons.shield_outlined,
    );
    return Card(
      child: changes.isEmpty
          ? ListTile(
              leading: icon,
              title: Text(title),
              subtitle: Text(subtitle),
            )
          : ExpansionTile(
              leading: icon,
              title: Text(title),
              subtitle: Text(
                '$subtitle\n${changes.length} champ(s) modifié(s)',
              ),
              children: [
                for (final change in changes.entries)
                  if (change.value case final Map values)
                    ListTile(
                      title: Text(_fields[change.key] ?? '${change.key}'),
                      subtitle: SelectableText(
                        [
                          'Avant : ${_value(values['before'])}',
                          'Après : ${_value(values['after'])}',
                          if (values['removed'] case final List positions
                              when positions.isNotEmpty)
                            'Photos retirées : ${positions.join(', ')}',
                          if (values['added'] case final int count
                              when count > 0)
                            'Photos ajoutées : $count',
                        ].join('\n'),
                      ),
                    ),
              ],
            ),
    );
  }
}

class _SecurityFilterForm extends StatefulWidget {
  const _SecurityFilterForm({required this.initial});
  final _Filters initial;
  @override
  State<_SecurityFilterForm> createState() => _SecurityFilterFormState();
}

class _SecurityFilterFormState extends State<_SecurityFilterForm> {
  late String _action = widget.initial.action;
  late String _operation = widget.initial.operation;
  late String _field = widget.initial.field;
  late DateTimeRange? _period = widget.initial.period;
  late final _actor = TextEditingController(text: widget.initial.actor);

  Widget _select(
    String label,
    String current,
    Map<String, String> options,
    ValueChanged<String> onChange,
  ) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      title: Text(label),
      subtitle: Text(options[current] ?? 'Tous'),
      trailing: const Icon(Icons.expand_more_rounded),
      onTap: () async {
        final selection = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text(label),
            children: [
              for (final option in {'': 'Tous', ...options}.entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, option.key),
                  child: Row(
                    children: [
                      Expanded(child: Text(option.value)),
                      if (option.key == current)
                        const Icon(Icons.check_rounded),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (mounted && selection != null) setState(() => onChange(selection));
      },
    ),
  );

  @override
  void dispose() {
    _actor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filtres du journal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _select(
              'Type d’événement',
              _action,
              _actions,
              (value) => _action = value,
            ),
            const SizedBox(height: 10),
            _select(
              'Opération',
              _operation,
              _operations,
              (value) => _operation = value,
            ),
            const SizedBox(height: 10),
            _select(
              'Champ modifié',
              _field,
              _fields,
              (value) => _field = value,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _actor,
              decoration: const InputDecoration(
                labelText: 'Nom ou identifiant du compte',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _period,
                );
                if (mounted && range != null) setState(() => _period = range);
              },
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                _period == null
                    ? 'Toutes les dates'
                    : '${MaterialLocalizations.of(context).formatShortDate(_period!.start)} – ${MaterialLocalizations.of(context).formatShortDate(_period!.end)}',
              ),
            ),
            const SizedBox(height: 12),
            OverflowBar(
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, _emptyFilters),
                  child: const Text('Réinitialiser'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    action: _action,
                    operation: _operation,
                    field: _field,
                    actor: _actor.text.trim(),
                    period: _period,
                  )),
                  child: const Text('Appliquer'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
