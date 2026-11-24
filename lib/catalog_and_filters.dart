part of 'main.dart';

class CatalogFamiliesPage extends StatefulWidget {
  const CatalogFamiliesPage({
    super.key,
    required this.loadCategories,
    required this.loadFamilies,
    required this.admin,
    required this.onSaveFamily,
    required this.onAddCategory,
    required this.onEditCategory,
  });

  final List<ProductCategory> Function() loadCategories;
  final List<CatalogFamily> Function() loadFamilies;
  final bool admin;
  final Future<void> Function(CatalogFamily) onSaveFamily;
  final Future<void> Function(String) onAddCategory;
  final Future<void> Function(ProductCategory) onEditCategory;

  @override
  State<CatalogFamiliesPage> createState() => _CatalogFamiliesPageState();
}

class _CatalogFamiliesPageState extends State<CatalogFamiliesPage> {
  Future<void> refreshAfter(Future<void> action) async {
    await action;
    if (mounted) setState(() {});
  }

  Future<void> editFamily([CatalogFamily? family]) async {
    final families = widget.loadFamilies();
    final result = await Navigator.push<CatalogFamily>(
      context,
      MaterialPageRoute(
        builder: (_) => _CatalogFamilyEditor(
          initial: family,
          categories: widget.loadCategories(),
          otherNames: families
              .where((item) => item.id != family?.id)
              .map((item) => item.name)
              .toSet(),
        ),
      ),
    );
    if (result != null && mounted) {
      await refreshAfter(widget.onSaveFamily(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final families = widget.loadFamilies();
    final groups = _catalogGroups(widget.loadCategories(), families);
    final byGroup = {
      for (final family in families) 'family:${family.id}': family,
    };
    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHero(
            icon: Icons.folder_outlined,
            title: 'Familles',
            subtitle: 'Ouvrez une famille pour gérer ses catégories.',
            trailing: widget.admin
                ? IconButton.filled(
                    onPressed: () => editFamily(),
                    icon: const Icon(Icons.add),
                    tooltip: 'Ajouter une famille',
                  )
                : null,
          ),
          const SizedBox(height: 12),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                child: ExpansionTile(
                  key: PageStorageKey(group.id),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(group.name),
                  subtitle: Text('${group.sections.length} catégorie(s)'),
                  children: [
                    if (byGroup[group.id] case final family?
                        when widget.admin) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter une catégorie'),
                            onPressed: () =>
                                refreshAfter(widget.onAddCategory(family.id)),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Modifier la famille'),
                            onPressed: () => editFamily(family),
                          ),
                        ],
                      ),
                    ],
                    for (final section in group.sections)
                      ListTile(
                        leading: CategoryImage(
                          category: section.category,
                          size: 38,
                        ),
                        title: Text(section.category.name),
                        subtitle: Text(
                          '${section.productIds.length} produit(s)',
                        ),
                        trailing: widget.admin
                            ? IconButton(
                                tooltip: 'Modifier la catégorie',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => refreshAfter(
                                  widget.onEditCategory(section.category),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogFamilyEditor extends StatefulWidget {
  const _CatalogFamilyEditor({
    required this.initial,
    required this.categories,
    required this.otherNames,
  });
  final CatalogFamily? initial;
  final List<ProductCategory> categories;
  final Set<String> otherNames;

  @override
  State<_CatalogFamilyEditor> createState() => _CatalogFamilyEditorState();
}

class _CatalogFamilyEditorState extends State<_CatalogFamilyEditor> {
  late final name = TextEditingController(text: widget.initial?.name);
  late Set<String> categoryIds = {...?widget.initial?.categoryIds};

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void save() {
    final value = name.text.trim();
    if (value.isEmpty || value.contains(RegExp(r'[<>\x00-\x1F\x7F]'))) {
      return message(context, 'Indiquez un nom de famille valide.');
    }
    if (widget.otherNames.any(
      (item) => _searchKey(item) == _searchKey(value),
    )) {
      return message(context, 'Ce nom de famille existe déjà.');
    }
    Navigator.pop(
      context,
      CatalogFamily(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: value,
        categoryIds: categoryIds.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: widget.initial == null
        ? 'Ajouter une famille'
        : 'Modifier la famille',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Nom de la famille *'),
        ),
        if (widget.categories.isNotEmpty) ...[
          SearchChoiceField(
            label: 'Rattacher des catégories existantes',
            options: _choices(
              widget.categories,
              (item) => item.id,
              (item) => item.name,
            ),
            selected: categoryIds,
            multiple: true,
            onChanged: (ids) => setState(() => categoryIds = ids),
          ),
          const SizedBox(height: 8),
          const Text(
            'Les catégories sélectionnées sont déplacées vers cette famille.',
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: save,
          child: const Text('Enregistrer la famille'),
        ),
      ],
    ),
  );
}

class CatalogFamily {
  const CatalogFamily({
    required this.id,
    required this.name,
    this.categoryIds = const [],
  });

  final String id;
  final String name;
  final List<String> categoryIds;

  factory CatalogFamily.fromRow(Map<String, Object?> row) => CatalogFamily(
    id: row['id'] as String,
    name: row['name'] as String,
    categoryIds: List<String>.from(
      jsonDecode(row['category_ids'] as String) as List,
    ),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'category_ids': jsonEncode(categoryIds),
  };
}

class _CatalogSection {
  const _CatalogSection(this.category, this.productIds, [this.legacyFamilyId]);
  final ProductCategory category;
  final Set<String> productIds;
  final String? legacyFamilyId;
}

class _CatalogGroup {
  _CatalogGroup(this.id, this.name, this.sections);
  final String id;
  final String name;
  final List<_CatalogSection> sections;
}

List<_CatalogGroup> _catalogGroups(
  List<ProductCategory> categories,
  List<CatalogFamily> families, {
  List<Product> products = const [],
}) {
  final byId = {for (final category in categories) category.id: category};
  final assigned = families.expand((family) => family.categoryIds).toSet();
  final legacy = <String, _CatalogGroup>{};
  final unassigned = <_CatalogSection>[];
  for (final category in categories) {
    if (assigned.contains(category.id)) continue;
    final remaining = category.productIds.toSet();
    for (final family in category.families) {
      final members = family.productIds.toSet().intersection(remaining);
      remaining.removeAll(members);
      final key = 'legacy:${family.name.trim().toLowerCase()}';
      legacy
          .putIfAbsent(key, () => _CatalogGroup(key, family.name, []))
          .sections
          .add(_CatalogSection(category, members, family.id));
    }
    if (remaining.isNotEmpty || category.families.isEmpty) {
      unassigned.add(_CatalogSection(category, remaining));
    }
  }
  if (products.isNotEmpty) {
    final categorized = categories
        .expand((category) => category.productIds)
        .toSet();
    final loose = products
        .map(_catalogMembershipId)
        .where((id) => !categorized.contains(id))
        .toSet();
    if (loose.isNotEmpty) {
      unassigned.add(
        _CatalogSection(
          ProductCategory(
            id: '',
            name: 'Sans catégorie',
            productIds: const [],
            image: Uint8List(0),
          ),
          loose,
        ),
      );
    }
  }
  return [
    for (final family in families)
      _CatalogGroup('family:${family.id}', family.name, [
        for (final id in family.categoryIds)
          if (byId[id] case final category?)
            _CatalogSection(category, category.productIds.toSet()),
        ...?legacy
            .remove('legacy:${family.name.trim().toLowerCase()}')
            ?.sections,
      ]),
    ...legacy.values,
    if (unassigned.isNotEmpty)
      _CatalogGroup('unassigned', 'Sans famille', unassigned),
  ];
}

String _catalogMembershipId(Product product) =>
    product.parentProductId != null && product.isManufacturedVariant
    ? product.parentProductId!
    : product.id;

Map<String, String> _choices<T>(
  Iterable<T> values,
  String Function(T) id,
  String Function(T) label,
) => {for (final value in values) id(value): label(value)};

String _partnerLabel(String name, String company) =>
    [name.trim(), company.trim()].where((text) => text.isNotEmpty).join(' · ');

String _searchKey(String text) {
  var value = text.trim().toLowerCase();
  const replacements = {
    'àâäáã': 'a',
    'ç': 'c',
    'éèêë': 'e',
    'îïí': 'i',
    'ôöó': 'o',
    'ùûüú': 'u',
    'ÿ': 'y',
    'œ': 'oe',
  };
  for (final entry in replacements.entries) {
    value = value.replaceAll(RegExp('[${entry.key}]'), entry.value);
  }
  return value;
}

class SearchChoiceField extends StatelessWidget {
  const SearchChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multiple = false,
    this.allowClear = true,
  });

  final String label;
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool multiple;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final summary = selected
        .map((value) => options[value])
        .whereType<String>()
        .join(', ');
    return InkWell(
      onTap: () async {
        final result = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _SearchChoiceDialog(
            label: label,
            options: options,
            selected: selected,
            multiple: multiple,
            allowClear: allowClear,
          ),
        );
        if (result != null && context.mounted) onChanged(result);
      },
      child: InputDecorator(
        isEmpty: summary.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        child: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _SearchChoiceDialog extends StatefulWidget {
  const _SearchChoiceDialog({
    required this.label,
    required this.options,
    required this.selected,
    required this.multiple,
    required this.allowClear,
  });

  final String label;
  final Map<String, String> options;
  final Set<String> selected;
  final bool multiple;
  final bool allowClear;

  @override
  State<_SearchChoiceDialog> createState() => _SearchChoiceDialogState();
}

class _SearchChoiceDialogState extends State<_SearchChoiceDialog> {
  late final selected = {...widget.selected};
  String query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.options.entries
        .where((entry) => _searchKey(entry.value).contains(query))
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.label),
      content: SizedBox(
        width: 420,
        height: min(340.0, 66.0 + 56 * max(1, widget.options.length)),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Rechercher par nom',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = _searchKey(value)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('Aucun résultat'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final entry = matches[index];
                        if (!widget.multiple) {
                          final selectedItem = selected.contains(entry.key);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(context, {entry.key}),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: selectedItem
                                      ? scheme.primary.withValues(alpha: .18)
                                      : scheme.surfaceContainerHigh.withValues(
                                          alpha: .56,
                                        ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selectedItem
                                        ? scheme.primary.withValues(alpha: .56)
                                        : scheme.outline.withValues(alpha: .50),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      color: selectedItem
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(entry.value)),
                                    if (selectedItem)
                                      Icon(
                                        Icons.check_rounded,
                                        color: scheme.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        final selectedItem = selected.contains(entry.key);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Material(
                            color: selectedItem
                                ? scheme.primary.withValues(alpha: .18)
                                : scheme.surfaceContainerHigh.withValues(
                                    alpha: .56,
                                  ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: selectedItem
                                    ? scheme.primary.withValues(alpha: .56)
                                    : scheme.outline.withValues(alpha: .50),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CheckboxListTile(
                              value: selectedItem,
                              title: Text(entry.value),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  selected.add(entry.key);
                                } else {
                                  selected.remove(entry.key);
                                }
                              }),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        if (widget.allowClear)
          TextButton(
            onPressed: () => Navigator.pop(context, <String>{}),
            child: const Text('Tout afficher'),
          ),
        if (widget.multiple)
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('Appliquer'),
          ),
      ],
    );
  }
}

bool transferMatchesDepots(StockTransfer item, String? first, String? second) {
  bool includes(String depot) =>
      item.sourceDepotId == depot || item.destinationDepotId == depot;
  if (first != null && !includes(first)) return false;
  return second == null || includes(second);
}

class _TransferDepotFields extends StatelessWidget {
  const _TransferDepotFields({
    required this.depots,
    required this.first,
    required this.second,
    required this.onChanged,
  });
  final List<Depot> depots;
  final String? first;
  final String? second;
  final void Function(String?, String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final options = _choices(depots, (item) => item.id, (item) => item.name);
    return Column(
      children: [
        SearchChoiceField(
          label: 'Dépôt concerné',
          options: options,
          selected: {?first},
          onChanged: (ids) {
            final value = ids.firstOrNull;
            onChanged(value, value == null || value == second ? null : second);
          },
        ),
        if (first != null) ...[
          const SizedBox(height: 8),
          SearchChoiceField(
            label: 'Autre dépôt (facultatif)',
            options: {...options}..remove(first),
            selected: {?second},
            onChanged: (ids) => onChanged(first, ids.firstOrNull),
          ),
        ],
      ],
    );
  }
}
