part of 'main.dart';

// Keep supplier details in the existing contact column so older clients can
// round-trip them through workshop snapshots and backups.
const _supplierContactPrefix = 'forage:supplier-contact:v1:';

String _encodeSupplierContact(Supplier supplier) {
  if (supplier.fax.isEmpty &&
      supplier.ice.isEmpty &&
      !supplier.contact.startsWith(_supplierContactPrefix)) {
    return supplier.contact;
  }
  return '$_supplierContactPrefix${jsonEncode({'contact': supplier.contact, 'fax': supplier.fax, 'ice': supplier.ice})}';
}

({String contact, String fax, String ice}) _decodeSupplierContact(
  String value,
) {
  if (value.startsWith(_supplierContactPrefix)) {
    try {
      final decoded = jsonDecode(
        value.substring(_supplierContactPrefix.length),
      );
      if (decoded case {
        'contact': final String contact,
        'fax': final String fax,
        'ice': final String ice,
      }) {
        return (contact: contact, fax: fax, ice: ice);
      }
    } on FormatException {
      // An older contact may contain arbitrary text.
    }
  }
  return (contact: value, fax: '', ice: '');
}

enum _StockPartnerKind {
  supplier('Fournisseurs', 'Fournisseur', Icons.local_shipping_outlined),
  client('Clients', 'Client', Icons.person_outline_rounded);

  const _StockPartnerKind(this.plural, this.label, this.icon);

  final String plural;
  final String label;
  final IconData icon;
}

class _StockPartnersPage extends StatefulWidget {
  const _StockPartnersPage({
    required this.suppliers,
    required this.clients,
    required this.onOpenPartner,
    required this.onAddSupplier,
    required this.onAddClient,
  });

  final List<Supplier> suppliers;
  final List<Client> clients;
  final void Function(_StockPartnerKind, String) onOpenPartner;
  final VoidCallback? onAddSupplier;
  final VoidCallback? onAddClient;

  @override
  State<_StockPartnersPage> createState() => _StockPartnersPageState();
}

class _StockPartnersPageState extends State<_StockPartnersPage> {
  final _search = TextEditingController();
  var _section = _StockPartnerKind.supplier;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersSelected = _section == _StockPartnerKind.supplier;
    final addPartner = suppliersSelected
        ? widget.onAddSupplier
        : widget.onAddClient;
    final partners = suppliersSelected
        ? widget.suppliers.map(
            (item) => (id: item.id, name: item.name, company: item.company),
          )
        : widget.clients.map(
            (item) => (id: item.id, name: item.name, company: item.company),
          );
    final query = _searchKey(_search.text);
    final terms = query.split(RegExp(r'\s+'));
    final matches = [
      for (final partner in partners)
        if (terms.every(
          _searchKey('${partner.name} ${partner.company}').contains,
        ))
          (
            partner: partner,
            sortKey: _searchKey(
              partner.name.trim().isEmpty ? partner.company : partner.name,
            ),
          ),
    ]..sort((left, right) => left.sortKey.compareTo(right.sortKey));

    return _StockPartnerScaffold(
      title: 'Fournisseurs et clients',
      action: addPartner == null
          ? null
          : IconButton.filledTonal(
              tooltip: suppliersSelected
                  ? 'Ajouter un fournisseur'
                  : 'Ajouter un client',
              onPressed: addPartner,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Rechercher par nom ou société',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_StockPartnerKind>(
            segments: [
              for (final kind in _StockPartnerKind.values)
                ButtonSegment(value: kind, label: Text(kind.plural)),
            ],
            selected: {_section},
            onSelectionChanged: (selected) =>
                setState(() => _section = selected.first),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: matches.isEmpty
                ? ListView(
                    children: [
                      Empty(
                        icon: _section.icon,
                        title: query.isNotEmpty
                            ? 'Aucun résultat'
                            : 'Annuaire vide',
                        detail: query.isNotEmpty
                            ? 'Essayez un autre nom ou une autre société.'
                            : 'Aucune fiche enregistrée dans cette section.',
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final partner = matches[index].partner;
                      final name = partner.name.trim();
                      final company = partner.company.trim();
                      return Glass(
                        key: ValueKey((_section, partner.id)),
                        radius: 18,
                        child: ListTile(
                          leading: _AtelierIcon(_section.icon, size: 38),
                          title: Text(name.isEmpty ? company : name),
                          subtitle: name.isEmpty || company.isEmpty
                              ? null
                              : Text(company),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              widget.onOpenPartner(_section, partner.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StockPartnerDetails extends StatelessWidget {
  const _StockPartnerDetails({
    required this.kind,
    required this.supplier,
    required this.client,
    required this.purchases,
    required this.sales,
    required this.productName,
    required this.depotName,
    required this.onOpenAttachments,
  });

  final _StockPartnerKind kind;
  final Supplier? supplier;
  final Client? client;
  final List<StockAddition> purchases;
  final List<Sale> sales;
  final String Function(String) productName;
  final String Function(String) depotName;
  final OpenTransactionPhotos? onOpenAttachments;

  @override
  Widget build(BuildContext context) {
    final name = supplier?.name ?? client?.name ?? '';
    final company = supplier?.company ?? client?.company ?? '';
    final photos = supplier?.images ?? client?.images ?? const <Uint8List>[];
    final details = [
      (name, 'Nom', Icons.person_outline_rounded),
      (company, 'Société', Icons.business_outlined),
      (
        supplier?.contact ?? client?.phone ?? '',
        supplier == null ? 'Téléphone' : 'Téléphone / contact',
        Icons.phone_outlined,
      ),
      (supplier?.fax ?? '', 'Fax', Icons.print_outlined),
      (supplier?.ice ?? client?.ice ?? '', 'ICE', Icons.badge_outlined),
    ];
    final isSupplier = kind == _StockPartnerKind.supplier;
    final historyCount = isSupplier ? purchases.length : sales.length;
    final title = company.trim().isNotEmpty ? company : name;

    return _StockPartnerScaffold(
      title: title.isEmpty ? kind.label : title,
      child: supplier == null && client == null
          ? ListView(
              children: const [
                Empty(
                  icon: Icons.contacts_outlined,
                  title: 'Fiche indisponible',
                  detail: 'Cette fiche est introuvable dans l’annuaire.',
                ),
              ],
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Glass(
                        radius: 22,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (value, label, icon) in details)
                              if (value.trim().isNotEmpty)
                                ListTile(
                                  leading: Icon(icon),
                                  title: Text(label),
                                  subtitle: SelectableText(value),
                                ),
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: Text(
                                'Photos de la fiche (${photos.length})',
                              ),
                              trailing: photos.isEmpty
                                  ? null
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: photos.isEmpty
                                  ? null
                                  : () => _showTransactionPhotos(
                                      context,
                                      Future.value(photos),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isSupplier
                            ? 'Historique des achats ($historyCount)'
                            : 'Historique des ventes ($historyCount)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (historyCount == 0)
                        Empty(
                          icon: Icons.receipt_long_outlined,
                          title: isSupplier ? 'Aucun achat' : 'Aucune vente',
                          detail: 'Les opérations liées à cette fiche apparaîtront ici.',
                        ),
                    ],
                  ),
                ),
                SliverList.builder(
                  itemCount: historyCount,
                  itemBuilder: (context, index) {
                    if (!isSupplier) {
                      final sale = sales[index];
                      return _StockPartnerHistoryTile(
                        operation: 'Vente',
                        product: productName(sale.productId),
                        depot: depotName(sale.depotId),
                        quantity: formatQuantity(sale.quantity, sale.unit),
                        date: sale.createdAt,
                        draft: sale.draft,
                        onOpenPhotos: onOpenAttachments == null
                            ? null
                            : () => onOpenAttachments!(
                                context,
                                true,
                                sale.id,
                                sale.images,
                              ),
                      );
                    }
                    final purchase = purchases[index];
                    return _StockPartnerHistoryTile(
                      operation: purchase.returnOfPurchaseId == null
                          ? 'Achat'
                          : 'Retour fournisseur',
                      product: productName(purchase.productId),
                      depot: depotName(purchase.depotId),
                      quantity: formatQuantity(
                        purchase.quantity.abs(),
                        purchase.unit,
                      ),
                      date: purchase.addedAt,
                      draft: purchase.draft,
                      receiptNumber: purchase.receiptNumber,
                      onOpenPhotos: onOpenAttachments == null
                          ? null
                          : () => onOpenAttachments!(
                              context,
                              false,
                              purchase.id?.toString(),
                              purchase.images,
                            ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _StockPartnerHistoryTile extends StatelessWidget {
  const _StockPartnerHistoryTile({
    required this.operation,
    required this.product,
    required this.depot,
    required this.quantity,
    required this.date,
    required this.draft,
    required this.onOpenPhotos,
    this.receiptNumber = '',
  });

  final String operation;
  final String product;
  final String depot;
  final String quantity;
  final DateTime date;
  final bool draft;
  final VoidCallback? onOpenPhotos;
  final String receiptNumber;

  @override
  Widget build(BuildContext context) {
    final dateLabel = date.millisecondsSinceEpoch == 0
        ? 'Ajout antérieur'
        : dateText(date);
    final status = draft ? 'Brouillon à valider' : 'Validé';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        radius: 18,
        child: ListTile(
          title: Text('$operation · $product'),
          subtitle: Text(
            [
              '$quantity · $depot',
              '$dateLabel · $status',
              if (receiptNumber.trim().isNotEmpty) 'Bon n° $receiptNumber',
            ].join('\n'),
          ),
          trailing: onOpenPhotos == null
              ? null
              : IconButton(
                  onPressed: onOpenPhotos,
                  tooltip: 'Voir les photos jointes',
                  icon: const Icon(Icons.photo_library_outlined),
                ),
        ),
      ),
    );
  }
}

class _StockPartnerScaffold extends StatelessWidget {
  const _StockPartnerScaffold({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Aura(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Glass(
                    radius: 22,
                    depth: 1.65,
                    opacity: .81,
                    padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
                    child: Row(
                      children: [
                        const _AtelierBackButton(),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        ?action,
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
