import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The database independently checks the current role for every read.
class SecurityActivityPage extends StatefulWidget {
  const SecurityActivityPage({
    super.key,
    this.loadEvents = _loadSecurityEvents,
  });
  final Future<List<Map<String, dynamic>>> Function() loadEvents;
  @override
  State<SecurityActivityPage> createState() => _SecurityActivityPageState();
}

Future<List<Map<String, dynamic>>> _loadSecurityEvents() async {
  final client = Supabase.instance.client;
  if (await client.rpc('is_admin') != true) {
    throw StateError('Accès administrateur requis.');
  }
  return client
      .from('forage_security_events')
      .select('occurred_at,actor_id,event,target,details')
      .order('id', ascending: false)
      .limit(100);
}

class _SecurityActivityPageState extends State<SecurityActivityPage> {
  List<Map<String, dynamic>> _events = [];
  Timer? _timer;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final events = await widget.loadEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _events = [];
          _error = 'Journal indisponible. Vérifiez votre accès et la configuration du serveur.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _labels = {
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Journal de sécurité'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _refresh,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '100 derniers événements · Actualisation toutes les 30 secondes pendant l’ouverture de cette page.',
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        if (!_loading && _events.isEmpty && _error == null)
          const Text('Aucun événement.'),
        Expanded(
          child: ListView.builder(
            itemCount: _events.length,
            itemBuilder: (context, index) {
              final entry = _events[index];
              final event = entry['event'] as String? ?? '';
              final time = DateTime.tryParse(
                entry['occurred_at']?.toString() ?? '',
              )?.toLocal();
              final details = entry['details'] as Map? ?? {};
              return ListTile(
                leading: Icon(
                  event.endsWith('rate_limit')
                      ? Icons.warning_amber_rounded
                      : Icons.shield_outlined,
                  color: event.endsWith('rate_limit') ? Colors.orange : null,
                ),
                title: Text(_labels[event] ?? event),
                subtitle: Text(
                  [
                    if (time != null) time.toString().split('.').first,
                    if (entry['actor_id'] != null)
                      'Compte : ${entry['actor_id']}',
                    if (details['role'] != null) 'Rôle : ${details['role']}',
                    if (details['status'] != null)
                      'État : ${details['status']}',
                  ].join('\n'),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
