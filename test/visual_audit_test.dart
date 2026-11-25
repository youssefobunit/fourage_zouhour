import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forage/main.dart' as forage;
import 'package:forage/security_activity_page.dart';

import 'atelier_glass_test.dart' show testLiquidStage;

const _output = String.fromEnvironment('FORAGE_VISUAL_AUDIT');
const _fontPath = String.fromEnvironment('ATELIER_PREVIEW_FONT');
const _phone = bool.fromEnvironment('FORAGE_VISUAL_AUDIT_PHONE');

void _noop() {}
Future<void> _ignore(Object? value) async {}

class _Demo {
  final admin = forage.AppUser(
    id: 'admin',
    username: 'demo',
    password: '',
    fullName: 'Camille Demo',
    admin: true,
    canExport: true,
  );
  final employee = forage.AppUser(
    id: 'operator',
    username: 'atelier',
    password: '',
    fullName: 'Alex Atelier',
    loginStartTime: '08:00:00',
    loginEndTime: '18:00:00',
  );
  static const depot = forage.Depot(id: 'main', name: 'Dépôt principal');
  static const secondDepot = forage.Depot(id: 'aux', name: 'Dépôt secondaire');
  static const product = forage.Product(
    id: 'product',
    name: 'Tôle acier',
    reference: 'AC-12',
    width: .93,
    lengthMeters: 15,
    lengthUnit: forage.LengthUnit.meter,
    thickness: 5,
    kind: forage.ProductKind.standard,
    initialStock: 500,
    initialDepotId: 'main',
    material: forage.MaterialType.steel,
  );
  static const output = forage.Product(
    id: 'out',
    name: 'Tôle roulée',
    reference: 'RO-04',
    width: .9,
    lengthMeters: 11,
    lengthUnit: forage.LengthUnit.meter,
    thickness: 5,
    kind: forage.ProductKind.manufactured,
    initialStock: 40,
    initialDepotId: 'main',
    material: forage.MaterialType.steel,
  );
  final categories = [
    forage.ProductCategory(
      id: 'steel',
      name: 'Matières premières',
      image: Uint8List(0),
      productIds: const ['product'],
    ),
    forage.ProductCategory(
      id: 'rolled',
      name: 'Pièces roulées',
      image: Uint8List(0),
      productIds: const ['out'],
    ),
  ];
  static const families = [
    forage.CatalogFamily(
      id: 'family',
      name: 'Acier',
      categoryIds: ['steel', 'rolled'],
    ),
  ];
  static const factory = forage.FactoryMachine(
    id: 'machine',
    name: 'Rouleuse A',
    type: forage.MachineType.roulage,
    categoryId: 'steel',
    outputId: 'out',
    units: [forage.MachineUnit(number: 1)],
    operatorIds: ['admin', 'operator'],
  );
  static const supplier = forage.Supplier(
    id: 'supplier',
    name: 'Fournisseur Démo',
    company: 'Atelier démo',
    contact: '',
    images: [],
  );
  static const client = forage.Client(
    id: 'client',
    name: 'Client Démo',
    company: 'Chantier démo',
    phone: '',
    ice: '',
    images: [],
  );
  static const products = [product, output];
  static const depots = [depot, secondDepot];
  static const machines = [factory];
  static const suppliers = [supplier];
  static const clients = [client];

  final purchase = forage.StockAddition(
    id: 1,
    productId: 'product',
    depotId: 'main',
    pieces: 120,
    receiptNumber: 'A-012',
    quantity: 120,
    unit: forage.InventoryUnit.piece,
    images: [],
    addedAt: DateTime.now(),
    supplierId: 'supplier',
    draft: false,
  );
  final draftPurchase = forage.StockAddition(
    id: 2,
    productId: 'product',
    depotId: 'main',
    pieces: 24,
    receiptNumber: 'A-013',
    quantity: 24,
    unit: forage.InventoryUnit.piece,
    images: [],
    addedAt: DateTime.now(),
    supplierId: 'supplier',
  );
  final sale = forage.Sale(
    id: 'sale',
    productId: 'product',
    depotId: 'main',
    clientId: 'client',
    pieces: 32,
    quantity: 32,
    unit: forage.InventoryUnit.piece,
    images: [],
    createdAt: DateTime.now(),
    draft: false,
  );
  final operation = forage.Operation(
    id: 'operation',
    machineId: 'machine',
    operatorId: 'operator',
    pieces: 16,
    productId: 'product',
    sourceDepotId: 'main',
    machineUnitNumber: 1,
    startedAt: DateTime.now().subtract(const Duration(hours: 2)),
  );
  late final finishedOperation = forage.Operation(
    id: 'completed',
    machineId: factory.id,
    operatorId: employee.id,
    pieces: 16,
    productId: product.id,
    sourceDepotId: depot.id,
    machineUnitNumber: 1,
    startedAt: operation.startedAt,
    finishedAt: DateTime.now(),
    outputPieces: 12,
    remainderPieces: 4,
    outputDepotId: depot.id,
    remainderDepotId: depot.id,
    needsReview: true,
  );

  int stock(String id) => id == 'product' ? 500 : 40;
  int available(String id, String depotId) => depotId == 'main' ? stock(id) : 0;
  String depotName(String id) => id == 'main' ? depot.name : secondDepot.name;
  String productName(String id) =>
      id == product.id ? product.name : output.name;
  Future<forage.AppUser> addUser(forage.AppUser user) async => user;

  List<_Screen> screens() => [
    _Screen(
      'connexion',
      () => forage.LoginPage(
        onLogin: (_, _) async => const forage.LoginResult.failure(
          forage.LoginFailure.invalidCredentials,
        ),
        onApprovedDeviceLogin: (_) async {},
      ),
    ),
    _Screen(
      'connexion-schema',
      () => forage.LoginPage(
        onLogin: (_, _) async => const forage.LoginResult.failure(
          forage.LoginFailure.invalidCredentials,
        ),
        onApprovedDeviceLogin: (_) async {},
      ),
      open: 'Schéma',
    ),
    _Screen(
      'premier-administrateur',
      () => forage.InitialAdminSetup(onCreate: _ignore),
    ),
    _Screen(
      'accueil',
      () => _hub(
        0,
        'Accueil',
        forage.DashboardPage(
          user: admin,
          productCount: products.length,
          machineCount: machines.length,
          pendingReviews: 1,
          forceDesktopLayout: !_phone,
          onProducts: _noop,
          onStock: _noop,
          onMachines: _noop,
          onTeam: _noop,
          onValidation: _noop,
          onCategories: _noop,
          onReviews: _noop,
        ),
      ),
    ),
    _Screen(
      'produits',
      () => _hub(
        1,
        'Produits',
        forage.ProductsPage(
          products: products,
          categories: categories,
          catalogFamilies: families,
          stock: stock,
          depots: depots,
          depotStock: available,
          canEdit: true,
          onAdd: _noop,
          onAddStock: (_) {},
          onOpenCategories: _noop,
        ),
      ),
    ),
    _Screen(
      'fiche-produit',
      () => forage.ProductDetailsPage(
        product: product,
        stockPieces: 500,
        allProducts: products,
        stock: stock,
        categories: categories,
        depots: depots,
        depotStock: available,
        canEdit: true,
        onAddStock: (_) {},
      ),
    ),
    _Screen('familles', () => _management('Familles', _families())),
    _Screen(
      'ajout-famille',
      () => _management('Familles', _families()),
      open: 'Ajouter une famille',
    ),
    _Screen('categorie', () => forage.CategoryForm(initial: categories.first)),
    _Screen('type-produit', () => const forage.ProductKindPage()),
    for (final kind in forage.ProductKind.values)
      _Screen(
        'produit-${kind.name}',
        () => forage.ProductForm(
          kind: kind,
          depots: depots,
          categories: categories,
          catalogFamilies: families,
        ),
      ),
    _Screen(
      'stock',
      () => _hub(
        2,
        'Stock',
        forage.StockPage(
          products: products,
          categories: categories,
          catalogFamilies: families,
          stock: stock,
          draftCount: 1,
          canEdit: true,
          onPurchase: _noop,
          onSale: _noop,
          onOpenDepots: _noop,
          onOpenRecords: _noop,
          onOpenPayments: _noop,
        ),
      ),
    ),
    _Screen(
      'achat',
      () => forage.StockForm(
        products: products,
        categories: categories,
        catalogFamilies: families,
        stock: stock,
        depots: depots,
        suppliers: suppliers,
        onAddSupplier: () async => null,
        allowGallery: true,
        initialProductId: product.id,
      ),
    ),
    _Screen(
      'vente',
      () => forage.SaleForm(
        products: products,
        categories: categories,
        catalogFamilies: families,
        depots: depots,
        clients: clients,
        available: available,
        onAddClient: () async => null,
        allowGallery: true,
      ),
    ),
    _Screen('registres-achats', _records),
    _Screen('registres-ventes', _records, open: 'Ventes'),
    _Screen('registres-transferts', _records, open: 'Transferts'),
    _Screen(
      'paiements',
      () => forage.TransactionPaymentsPage(
        payments: [],
        purchases: [purchase],
        sales: [sale],
        products: products,
        clients: clients,
        suppliers: suppliers,
        competitors: [],
        depotName: depotName,
      ),
    ),
    _Screen(
      'enregistrement-paiement',
      () => const forage.PaymentForm(competitors: []),
    ),
    _Screen(
      'depots',
      () => _management(
        'Dépôts',
        forage.DepotsPage(
          depots: depots,
          products: products,
          categories: categories,
          catalogFamilies: families,
          stock: available,
          canEdit: true,
          canTransfer: true,
          onAdd: _noop,
          onTransfer: _noop,
        ),
      ),
    ),
    _Screen(
      'fiche-depot',
      () => _management(
        'Dépôt principal',
        forage.DepotDetailsPage(
          depot: depot,
          products: products,
          categories: categories,
          catalogFamilies: families,
          stock: available,
        ),
      ),
    ),
    _Screen('ajout-depot', () => const forage.DepotForm(allowGallery: true)),
    _Screen(
      'transfert',
      () => forage.StockTransferForm(
        products: products,
        categories: categories,
        catalogFamilies: families,
        depots: depots,
        available: available,
      ),
    ),
    _Screen('fournisseur', () => const forage.SupplierForm()),
    _Screen('client', () => const forage.ClientForm()),
    _Screen(
      'machines',
      () => _hub(
        3,
        'Machines',
        forage.MachinesPage(
          machines: machines,
          operations: [operation],
          user: admin,
          userName: (_) => employee.fullName,
          categoryName: (_) => categories.first.name,
          productName: productName,
          hasActive: false,
          onAdd: _noop,
          onStart: (_, _) {},
          onFinish: (_) {},
          onManage: (_) {},
          pendingReviews: 1,
          onOpenReviews: _noop,
        ),
      ),
    ),
    _Screen('ajout-machine', _machine),
    _Screen(
      'travail-externe',
      _machine,
      open: 'Travail externe temporaire',
      scrollAfterOpen: true,
    ),
    _Screen(
      'exemplaires-machine',
      () => const forage.MachineUnitsPage(machine: factory),
    ),
    _Screen(
      'demarrage-operation',
      () => forage.StartOperation(
        machine: factory,
        available: available,
        user: admin,
        category: categories.first,
        products: products,
        depots: depots,
        unitNumber: 1,
      ),
    ),
    _Screen(
      'fin-operation',
      () => forage.FinishOperation(
        operation: operation,
        machine: factory,
        output: output,
        depots: depots,
      ),
    ),
    _Screen(
      'bon-production',
      () => _modal(
        forage.Receipt(
          operation: finishedOperation,
          machine: factory,
          output: output,
          operator: employee,
        ),
      ),
    ),
    _Screen(
      'controles',
      () => _management(
        'Contrôles',
        forage.ReviewsPage(
          operations: [finishedOperation],
          product: (id) => id == product.id ? product : output,
          userName: (_) => employee.fullName,
          depots: depots,
          admin: true,
          onApprove: (_, _) async {},
        ),
      ),
    ),
    _Screen(
      'validations',
      () => _hub(
        5,
        'Validations',
        forage.ValidationPage(
          products: products,
          depots: depots,
          stockDrafts: [draftPurchase],
          saleDrafts: [],
          returnDrafts: [],
          operationDrafts: [],
          transferDrafts: [],
          onApproveStock: _ignore,
          onEditStock: _ignore,
          onCancelStock: _ignore,
          onApproveSale: _ignore,
          onEditSale: _ignore,
          onCancelSale: _ignore,
          onApproveReturn: _ignore,
          onEditReturn: _ignore,
          onRejectReturn: _ignore,
          onCancelReturn: _ignore,
          onApproveOperation: _ignore,
          onEditOperation: _ignore,
          onCancelOperation: _ignore,
          onApproveTransfer: _ignore,
          onEditTransfer: _ignore,
          onCancelTransfer: _ignore,
        ),
      ),
    ),
    _Screen(
      'equipe',
      () => _hub(
        4,
        'Équipe',
        forage.UsersPage(
          users: [admin, employee],
          admin: true,
          onAdd: addUser,
          onUpdate: _ignore,
          onLoadSessions: (_) async => [],
          onOpenPayroll: _noop,
          onOpenDeviceRequests: _noop,
        ),
      ),
    ),
    _Screen('fiche-utilisateur', _user),
    _Screen('mot-de-passe-utilisateur', _user, open: 'Modifier'),
    _Screen('ajout-utilisateur', () => const forage.UserForm()),
    _Screen(
      'paie-operateurs',
      () => _management(
        'Paiements des opérateurs',
        forage.PayrollPage(
          users: [admin, employee],
          products: products,
          operations: [operation],
          payments: [],
          meterRate: 2,
          onPay: (_, _) async {},
          onRateChanged: _ignore,
        ),
      ),
    ),
    _Screen(
      'appareils',
      () => forage.DeviceRequestsPage(
        userName: (_) => employee.fullName,
        loadRequests: () async => [
          forage.DeviceAccessRequest(
            id: 'request',
            userId: employee.id,
            userLabel: employee.fullName,
            deviceId: 'phone',
            deviceLabel: 'iPhone (démo)',
            requestedAt: DateTime.now(),
          ),
        ],
        loadDevices: () async => [
          forage.TrustedDevice(
            id: 'desktop',
            userId: employee.id,
            label: 'Windows (démo)',
            primary: true,
            status: 'active',
            email: 'operateur@example.test',
            lastLoginAt: DateTime.now(),
          ),
        ],
      ),
    ),
    _Screen(
      'journal-securite',
      () => SecurityActivityPage(
        loadEvents: () async => [
          {
            'event': 'device_login',
            'occurred_at': DateTime.now().toIso8601String(),
            'actor_id': employee.id,
            'details': {'status': 'active'},
          },
        ],
      ),
    ),
    _Screen(
      'analyses',
      () => forage.AnalyticsPage(
        products: products,
        operations: [operation],
        sales: [sale],
        purchases: [purchase],
        stock: stock,
      ),
    ),
    _Screen(
      'analyses-sans-mouvements',
      () => forage.AnalyticsPage(
        products: products,
        operations: [],
        sales: [],
        purchases: [],
        stock: stock,
      ),
    ),
    _Screen(
      'profil',
      () => _modal(
        forage.ProfileSheet(
          user: admin,
          onOpenTeam: _noop,
          onOpenBackups: _noop,
          onLogout: _noop,
          onOpenExport: _noop,
          onOpenDeveloper: _noop,
        ),
      ),
    ),
    _Screen(
      'sauvegardes',
      () => forage.BackupPage(
        lastBackupAt: () async => DateTime.now(),
        onDownload: () async => false,
        onRestore: () async {},
        onClearData: () async => false,
      ),
    ),
    _Screen(
      'developpeur',
      () => forage.DeveloperModePage(
        products: products,
        categories: categories,
        depots: depots,
        purchases: [purchase],
        sales: [sale],
        machines: machines,
        operations: [operation],
        transfers: [],
        returns: [],
        database: forage.AppDatabase(databasePath: ':memory:'),
        onChanged: () async {},
      ),
    ),
    _Screen('export-excel', _excel),
    _Screen('export-familles', _excel, open: 'Produits', thenOpen: 'Familles'),
  ];

  Widget _hub(int index, String title, Widget child) => Scaffold(
    extendBody: _phone,
    body: forage.Aura(
      child: _phone
          ? SafeArea(
              child: Column(
                children: [
                  forage.AppHeader(
                    title: title,
                    user: admin,
                    onLogout: _noop,
                    onOpenTeam: _noop,
                    onOpenBackups: _noop,
                    onOpenAnalytics: _noop,
                    onOpenActivity: _noop,
                    canAccessAnalytics: true,
                    canExport: true,
                    onOpenExport: _noop,
                    onOpenDeveloper: _noop,
                  ),
                  Expanded(child: child),
                ],
              ),
            )
          : forage.WindowsWorkspaceShell(
              title: title,
              user: admin,
              section: index,
              onSectionChanged: (_) {},
              onLogout: _noop,
              onOpenTeam: _noop,
              onOpenBackups: _noop,
              onOpenAnalytics: _noop,
              canAccessAnalytics: true,
              canExport: true,
              onOpenExport: _noop,
              onOpenDeveloper: _noop,
              child: child,
            ),
    ),
    bottomNavigationBar: _phone
        ? forage.MobileGlassNavigation(
            index: index,
            onTap: (_) {},
            showTeam: true,
          )
        : null,
  );

  Widget _management(String title, Widget child) =>
      forage.ManagementScreen(title: title, child: child);

  Widget _modal(Widget child) => Scaffold(
    body: forage.Aura(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: child,
        ),
      ),
    ),
  );

  Widget _families() => forage.CatalogFamiliesPage(
    loadCategories: () => categories,
    loadFamilies: () => families,
    admin: true,
    onSaveFamily: _ignore,
    onAddCategory: (_) async {},
    onEditCategory: _ignore,
  );

  Widget _records() => forage.StockRecordsPage(
    products: products,
    additions: [purchase, draftPurchase],
    sales: [sale],
    transfers: [],
    depots: depots,
    saleReturns: [],
    suppliers: suppliers,
    clients: clients,
    depotName: depotName,
    canReturn: true,
    onReturn: (_, _) async => null,
    canReturnPurchase: true,
    onReturnPurchase: (_, _) async => null,
  );

  Widget _machine() => forage.MachineForm(
    categories: categories,
    products: products,
    users: [admin, employee],
    onUserAdded: addUser,
    canManageUsers: true,
    canCreateTemporary: true,
    allowGallery: true,
    depots: depots,
    available: available,
  );

  Widget _user() => forage.UserDetailsPage(
    user: employee,
    canManage: true,
    loadSessions: (_) async => [],
  );

  Widget _excel() => _modal(
    forage.ExcelExportDialog(
      products: products,
      categories: categories,
      catalogFamilies: families,
      depots: depots,
      stockAdditions: [purchase],
      sales: [sale],
      operations: [operation],
      transfers: [],
      returns: [],
      machines: machines,
      suppliers: suppliers,
      clients: clients,
      productName: productName,
      depotName: depotName,
      clientName: (_) => client.name,
      supplierName: (_) => supplier.name,
      saveSheets: (_) async {},
    ),
  );
}

class _Screen {
  const _Screen(
    this.name,
    this.build, {
    this.open,
    this.thenOpen,
    this.scrollAfterOpen = false,
  });
  final String name;
  final Widget Function() build;
  final String? open;
  final String? thenOpen;
  final bool scrollAfterOpen;
}

void main() {
  if (_output.isEmpty) return;
  final screens = _Demo().screens();
  final directory = Directory(_output);

  setUpAll(() async {
    await directory.create(recursive: true);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    if (_fontPath.isNotEmpty) {
      final font = FontLoader('Audit')
        ..addFont(File(_fontPath).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final screen in screens) {
      testWidgets('${screen.name} ($mode)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = _phone
            ? const Size(390, 844)
            : const Size(1440, 920);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final key = GlobalKey();
        final font = _fontPath.isEmpty ? null : 'Audit';
        await tester.runAsync(_warmOptics);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark
                  ? forage.atelierDarkTheme(fontFamily: font)
                  : forage.atelierTheme(fontFamily: font),
              builder: testLiquidStage,
              home: screen.build(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final labels = [screen.open, screen.thenOpen].whereType<String>();
        for (final label in labels) {
          final choice = find.widgetWithText(forage.SearchChoiceField, label);
          final candidates = choice.evaluate().isEmpty
              ? find.text(label)
              : choice;
          final target = candidates.evaluate().isEmpty
              ? find.byTooltip(label).last
              : candidates.last;
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }
        if (screen.name == 'export-familles') {
          expect(find.text('Rechercher par nom'), findsOneWidget);
        }
        final base = '$mode-${screen.name}';
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() => _writeShot(boundary, directory, base));

        if (labels.isEmpty || screen.scrollAfterOpen) {
          final scrollables = find
              .byType(Scrollable)
              .evaluate()
              .map(
                (element) =>
                    (element as StatefulElement).state as ScrollableState,
              )
              .where(
                (state) =>
                    state.position.axis == Axis.vertical &&
                    state.position.maxScrollExtent > 80,
              )
              .toList();
          if (scrollables.isNotEmpty) {
            final position = scrollables.first.position;
            final step = position.viewportDimension * .83;
            var offset = 0.0;
            var part = 2;
            while (offset < position.maxScrollExtent - 1) {
              offset = (offset + step)
                  .clamp(0, position.maxScrollExtent)
                  .toDouble();
              position.jumpTo(offset);
              await tester.pumpAndSettle();
              final file = '$base-$part';
              await tester.runAsync(
                () => _writeShot(boundary, directory, file),
              );
              part++;
            }
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  tearDownAll(() async {
    final shots = await directory
        .list()
        .where((entry) => entry is File)
        .map((file) => file.uri.pathSegments.last)
        .where((name) => RegExp(r'^(light|dark)-[\w-]+\.png$').hasMatch(name))
        .toList();
    shots.sort();
    await File('${directory.path}/index.html').writeAsString('''
<!doctype html>
<html lang="fr"><meta charset="utf-8"><title>FORAGE — audit visuel</title>
<style>body{font:16px system-ui;background:#140c20;color:#fff;margin:24px}
main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(340px,100%),1fr));gap:16px}
figure{margin:0;padding:6px;border:1px solid #795493;border-radius:10px;overflow:hidden}
img{display:block;width:100%;height:auto}figcaption{padding:8px}a{color:inherit}</style>
<h1>FORAGE — audit visuel</h1>
<p>Données de démonstration · ${shots.length} captures · cliquez sur une capture pour l’agrandir.</p>
<main>
${shots.map((shot) {
      final split = shot.indexOf('-');
      final label = '${shot.substring(split + 1, shot.length - 4)} · ${shot.substring(0, split)}';
      return '<figure><a href="$shot"><img loading="lazy" src="$shot" alt="$label"></a><figcaption>$label</figcaption></figure>';
    }).join('\n')}
</main></html>''');
  });
}

Future<void>? _optics;

Future<void> _warmOptics() => _optics ??= Future.wait<void>([
  ui.FragmentProgram.fromAsset('shaders/atelier_liquid.frag').then((_) {}),
  _warmImage(const AssetImage('assets/app_logo.png')),
  _warmImage(const AssetImage('assets/atelier-login-daylight.png')),
  _warmImage(const AssetImage('assets/forage-login-daylight.jpg')),
  _warmImage(const AssetImage('assets/forage-login-drill.jpg')),
  for (final mode in ['light', 'dark'])
    _warmImage(AssetImage('assets/atelier-wallpaper-$mode.png')),
]);

Future<void> _warmImage(AssetImage asset) async {
  final stream = asset.resolve(ImageConfiguration.empty);
  final ready = Completer<void>();
  final listener = ImageStreamListener(
    (info, _) {
      info.dispose();
      if (!ready.isCompleted) ready.complete();
    },
    onError: (error, stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    await ready.future;
  } finally {
    stream.removeListener(listener);
  }
}

Future<void> _writeShot(
  RenderRepaintBoundary boundary,
  Directory directory,
  String name,
) async {
  final image = await boundary.toImage();
  try {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('${directory.path}/$name.png').writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}
