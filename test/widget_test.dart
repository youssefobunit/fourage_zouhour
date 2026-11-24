import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:forage/main.dart' hide MaterialType;
import 'package:forage/main.dart' as forage show MaterialType;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('requires creation of a unique administrator on first startup',
      (WidgetTester tester) async {
    final directory = await Directory.systemTemp.createTemp('forage-first-run-test-');
    final database = AppDatabase(
      databasePath: path.join(directory.path, 'forage-test.db'),
    );
    try {
      await tester.pumpWidget(ForageApp(database: database));
      await tester.pumpAndSettle();

      expect(find.text('Créer le compte administrateur'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
    } finally {
      await database.close();
      await Directory(directory.path).delete(recursive: true);
    }
  });

  test('converts centimetres and millimetres before calculating kilograms', () {
    // 930 cm = 9.30 m and 5 mm = 0.005 m.
    expect(
      kilogramsForDimensions(
        widthMeters: 1.5,
        lengthMeters: 930 * LengthUnit.centimeter.metres,
        thicknessMillimetres: 5 * ThicknessUnit.millimeter.millimetres,
        densityKilogramsPerCubicMeter: forage.MaterialType.steel.density,
      ),
      closeTo(547.5375, 0.0001),
    );

    // If the intended length is 930 mm rather than 930 cm, it is ten times
    // shorter and therefore weighs ten times less.
    expect(
      kilogramsForDimensions(
        widthMeters: 1.5,
        lengthMeters: 930 * LengthUnit.millimeter.metres,
        thicknessMillimetres: 5,
        densityKilogramsPerCubicMeter: forage.MaterialType.steel.density,
      ),
      closeTo(54.75375, 0.0001),
    );
  });

  test('a newly created administrator can log in with the same credentials',
      () async {
    final directory = await Directory.systemTemp.createTemp('forage-auth-test-');
    final database = AppDatabase(
      databasePath: path.join(directory.path, 'forage-test.db'),
    );
    const username = 'Admin.Test';
    const password = 'Correct_password_2026';

    try {
      final created = await database.insertUser(
        AppUser(
          id: 'test-admin',
          username: username,
          password: password,
          fullName: 'Test Administrator',
          admin: true,
          role: UserRole.admin,
          roles: {UserRole.admin},
        ),
      );

      expect(created.password, isNot(password));
      expect(CredentialSecurity.isHash(created.password), isTrue);
      expect(await database.authenticate(username, password).then((result) => result.succeeded), isTrue);
      expect(await database.authenticate(username.toLowerCase(), password).then((result) => result.succeeded), isTrue);
      expect(await database.authenticate(username, 'incorrect-password').then((result) => result.succeeded), isFalse);

      final rotated = await database.updateUser(
        created.copyWith(password: 'New_secure_password_2026'),
      );
      expect(CredentialSecurity.isHash(rotated.password), isTrue);
      expect(await database.authenticate(username, password).then((result) => result.succeeded), isFalse);
      expect(await database.authenticate(username, 'New_secure_password_2026').then((result) => result.succeeded), isTrue);
    } finally {
      await database.close();
      await Directory(directory.path).delete(recursive: true);
    }
  });

  testWidgets('a first-run administrator chooses the credential',
      (WidgetTester tester) async {
    final directory = await Directory.systemTemp.createTemp('forage-setup-test-');
    final database = AppDatabase(
      databasePath: path.join(directory.path, 'forage-setup-test.db'),
    );
    try {
      await tester.pumpWidget(ForageApp(database: database));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Responsible Admin');
      await tester.enterText(find.byType(TextFormField).at(1), 'responsible.admin');
      await tester.enterText(find.byType(TextFormField).at(2), 'Correct_password_2026');
      await tester.enterText(find.byType(TextFormField).at(3), 'Correct_password_2026');
      await tester.tap(find.widgetWithText(FilledButton, 'Créer et continuer'));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.text('Accueil'), findsOneWidget);
      expect(await database.authenticate('responsible.admin', 'Correct_password_2026').then((result) => result.succeeded), isTrue);
      expect(await database.authenticate('former-default-user', 'not-usable-password').then((result) => result.succeeded), isFalse);
    } finally {
      await database.close();
      await Directory(directory.path).delete(recursive: true);
    }
  });

  testWidgets('the dark dashboard renders its overview on a desktop layout',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final user = AppUser(
      id: 'dashboard-admin',
      username: 'dashboard.admin',
      password: 'Correct_password_2026',
      fullName: 'Youssef Forage',
      admin: true,
      role: UserRole.admin,
      roles: {UserRole.admin},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme(),
        darkTheme: atelierDarkTheme(),
        themeMode: ThemeMode.dark,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: ForageAppearanceScope(
            appearance: ForageAppearance.dark,
            onChanged: (_) {},
            child: DashboardPage(
              user: user,
              productCount: 49,
              machineCount: 6,
              pendingReviews: 2,
              forceDesktopLayout: true,
              onProducts: () {},
              onStock: () {},
              onMachines: () {},
              onTeam: () {},
              onValidation: () {},
              onCategories: () {},
              onReviews: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Bonjour, Youssef'), findsOneWidget);
    expect(find.text('Accès rapide'), findsOneWidget);
    expect(find.text('Machines de l’atelier'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('VUE D’ENSEMBLE')).style?.color,
      atelierDarkTheme().colorScheme.primary,
    );
    expect(
      tester.widget<Text>(find.text('Voici un aperçu de votre atelier aujourd’hui.'))
          .style?.color,
      atelierDarkTheme().colorScheme.onSurfaceVariant,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('atelier-overview'))).height,
      greaterThanOrEqualTo(176),
    );
  });

  testWidgets('the dark dashboard remains visible on a phone layout',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final user = AppUser(
      id: 'mobile-dashboard-admin',
      username: 'mobile.dashboard.admin',
      password: 'Correct_password_2026',
      fullName: 'Youssef Forage',
      admin: true,
      role: UserRole.admin,
      roles: {UserRole.admin},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme(),
        darkTheme: atelierDarkTheme(),
        themeMode: ThemeMode.dark,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: ForageAppearanceScope(
            appearance: ForageAppearance.dark,
            onChanged: (_) {},
            child: DashboardPage(
              user: user,
              productCount: 49,
              machineCount: 6,
              pendingReviews: 2,
              onProducts: () {},
              onStock: () {},
              onMachines: () {},
              onTeam: () {},
              onValidation: () {},
              onCategories: () {},
              onReviews: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bonjour, Youssef'), findsOneWidget);
    expect(find.text('Machines de l’atelier'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('atelier-overview'))).height,
      greaterThan(180),
    );
  });

  testWidgets('the Excel family filter inherits the dark dialog theme',
      (tester) async {
    final theme = atelierDarkTheme();
    await tester.binding.setSurfaceSize(const Size(650, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme(),
        darkTheme: theme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ExcelExportDialog(
                  products: const [],
                  categories: const [],
                  catalogFamilies: const [
                    CatalogFamily(id: 'forage', name: 'Forage', categoryIds: []),
                  ],
                  depots: const [],
                  stockAdditions: const [],
                  sales: const [],
                  operations: const [],
                  transfers: const [],
                  returns: const [],
                  machines: const [],
                  suppliers: const [],
                  clients: const [],
                  productName: (id) => id,
                  depotName: (id) => id,
                  clientName: (id) => id,
                  supplierName: (id) => id,
                  saveSheets: (_) async {},
                ),
              ),
              child: const Text('Exporter'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Exporter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Produits'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SearchChoiceField, 'Familles'));
    await tester.pumpAndSettle();

    final pickerSurface = tester.widget<Material>(
      find.descendant(of: find.byType(Dialog).last, matching: find.byType(Material)).first,
    );
    expect(pickerSurface.color, theme.dialogTheme.backgroundColor);
    await tester.tap(find.text('Forage'));
    await tester.pumpAndSettle();
    final checkbox = find.descendant(
      of: find.widgetWithText(CheckboxListTile, 'Forage'),
      matching: find.byType(Checkbox),
    );
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(
      CheckboxTheme.of(tester.element(checkbox)).fillColor?.resolve({
        WidgetState.selected,
      }),
      theme.colorScheme.primary,
    );
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(find.text('Exporter vers Excel'), findsOneWidget);
    expect(find.text('Forage'), findsOneWidget);
  });

  test('reset does not recreate a default administrator', () async {
    final directory = await Directory.systemTemp.createTemp('forage-reset-test-');
    final database = AppDatabase(
      databasePath: path.join(directory.path, 'forage-reset-test.db'),
    );

    try {
      await database.insertUser(
        AppUser(
          id: 'existing-admin',
          username: 'existing-admin',
          password: 'Correct_password_2026',
          fullName: 'Existing Administrator',
          admin: true,
          role: UserRole.admin,
          roles: {UserRole.admin},
        ),
      );
      await database.resetApplication();

      expect(await database.loadUsers(), isEmpty);
      expect(await database.authenticate('former-default-user', 'not-usable-password').then((result) => result.succeeded), isFalse);
    } finally {
      await database.close();
      await Directory(directory.path).delete(recursive: true);
    }
  });

  test('locks an account after repeated failed login attempts', () async {
    final directory = await Directory.systemTemp.createTemp('forage-lockout-test-');
    final database = AppDatabase(
      databasePath: path.join(directory.path, 'forage-test.db'),
    );
    try {
      await database.insertUser(
        AppUser(
          id: 'lockout-user',
          username: 'lockout.user',
          password: 'Correct_password_2026',
          fullName: 'Lockout Test',
        ),
      );

      for (var attempt = 0; attempt < 4; attempt++) {
        expect(
          (await database.authenticate('lockout.user', 'incorrect-password')).failure,
          LoginFailure.invalidCredentials,
        );
      }
      expect(
        (await database.authenticate('lockout.user', 'incorrect-password')).failure,
        LoginFailure.temporarilyLocked,
      );
      expect(
        (await database.authenticate('lockout.user', 'Correct_password_2026')).failure,
        LoginFailure.temporarilyLocked,
      );
    } finally {
      await database.close();
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
