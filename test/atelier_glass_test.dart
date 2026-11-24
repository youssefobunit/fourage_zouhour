import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forage/main.dart';

const previewDirectory = String.fromEnvironment('ATELIER_PREVIEW_DIRECTORY');
const previewFont = String.fromEnvironment('ATELIER_PREVIEW_FONT');

void main() {
  testWidgets('glass dashboard and mobile navigation work on a compact phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 670));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openedFamilies = false;
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: testLiquidStage(context, child),
        ),
        home: dashboard(
          onFamilies: () => openedFamilies = true,
          onNavigate: (value) => page = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Machines de l’atelier'), findsOneWidget);
    final families = find.text('Familles');
    await tester.ensureVisible(families);
    await tester.pumpAndSettle();
    final press = await tester.startGesture(tester.getCenter(families));
    await tester.pump(const Duration(milliseconds: 100));
    expect(openedFamilies, isFalse);
    await press.up();
    await tester.pumpAndSettle();
    expect(openedFamilies, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(MobileGlassNavigation),
        matching: find.text('Stock'),
      ),
    );
    expect(page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home header opens analytics, activity and profile actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 570));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openedAnalytics = false;
    var openedActivity = false;
    var openedExport = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme().copyWith(platform: TargetPlatform.iOS),
        builder: testLiquidStage,
        home: dashboard(
          onAnalytics: () => openedAnalytics = true,
          onActivity: () => openedActivity = true,
          onExport: () => openedExport = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Analyses'));
    await tester.tap(find.byTooltip('Notifications et contrôles'));
    expect(openedAnalytics && openedActivity, isTrue);
    await tester.tap(find.byTooltip('Profil'));
    await tester.pumpAndSettle();
    final export = find.text('Exporter vers Excel');
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(openedExport, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'glass login submits the existing credentials on a narrow phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 590));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      (String, String)? submitted;
      await tester.pumpWidget(
        MaterialApp(
          theme: atelierTheme(),
          builder: testLiquidStage,
          home: LoginPage(
            onLogin: (email, secret) async {
              submitted = (email, secret);
              return const LoginResult.failure(LoginFailure.invalidCredentials);
            },
            onApprovedDeviceLogin: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'test@example.com');
      await tester.enterText(find.byType(TextField).last, 'mock-password');
      final submit = find.widgetWithText(FilledButton, 'Connexion');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(submitted, ('test@example.com', 'mock-password'));
      expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('glass login gives the brand and form separate desktop space', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: atelierDarkTheme(),
        builder: testLiquidStage,
        home: LoginPage(
          onLogin: (_, _) async => const LoginResult.failure(
            LoginFailure.invalidCredentials,
          ),
          onApprovedDeviceLogin: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final brand = tester.getRect(find.text('FORAGE ZOUHOUR'));
    final email = tester.getRect(find.byType(TextField).first);
    expect(brand.height, lessThan(100));
    expect(brand.right, lessThan(email.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the workspace rail and dashboard fit a wide window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1678, 896));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var section = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: atelierTheme(),
        builder: testLiquidStage,
        home: dashboard(desktop: true, onNavigate: (value) => section = value),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Voici un aperçu de votre atelier aujourd’hui.'),
      findsOneWidget,
    );
    expect(find.text('Rechercher un produit, une machine, …'), findsOneWidget);
    expect(find.text('Accès rapide'), findsOneWidget);
    await tester.tap(find.byTooltip('Réduire le menu'));
    await tester.pumpAndSettle();
    expect(find.text('FORAGE'), findsNothing);
    expect(find.text('Vue générale'), findsNothing);
    expect(find.byTooltip('Vue générale'), findsOneWidget);
    await tester.tap(find.byTooltip('Stock'));
    expect(section, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the photo field follows the theme and still opens the picker', (
    tester,
  ) async {
    var launches = 0;
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, mode, child) => MaterialApp(
          theme: atelierTheme(),
          darkTheme: atelierDarkTheme(),
          themeMode: mode,
          builder: testLiquidStage,
          home: FormShell(
            title: 'Nouveau produit',
            child: ImageInput(
              bytes: null,
              label: 'Photo du produit *',
              onTap: () => launches++,
            ),
          ),
        ),
      ),
    );
    final title = find.text('Photo du produit *');
    final hint = find.text('Touchez pour choisir une image');
    for (final theme in [atelierTheme(), atelierDarkTheme()]) {
      mode.value = theme.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(title).style?.color,
        theme.colorScheme.onSurface,
      );
      expect(
        tester.widget<Text>(hint).style?.color,
        theme.colorScheme.onSurfaceVariant,
      );
      await tester.tap(title);
      await tester.pumpAndSettle();
    }
    expect(launches, 2);
    expect(tester.takeException(), isNull);
  });

  test('liquid bevel displaces pixels from the wallpaper', () async {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/atelier_liquid.frag',
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawColor(Colors.black, BlendMode.src)
      ..drawRect(
        const Rect.fromLTWH(51, 0, 10, 64),
        Paint()..color = Colors.white,
      );
    final picture = recorder.endRecording();
    final texture = picture.toImageSync(128, 64);
    picture.dispose();

    Future<int> firstBrightPixel(double depth, {required bool dark}) async {
      final shader = program.fragmentShader();
      final floats = [
        64.0,
        64.0,
        32.0,
        0.0,
        128.0,
        64.0,
        0.0,
        0.0,
        0.0,
        14.0,
        depth,
        0.0,
        1.0,
        dark ? 1.0 : 0.0,
      ];
      for (final (index, value) in floats.indexed) {
        shader.setFloat(index, value);
      }
      shader.setImageSampler(0, texture);
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..shader = shader);
      final frame = recorder.endRecording();
      final image = frame.toImageSync(64, 64);
      final pixels = (await image.toByteData())!;
      image.dispose();
      frame.dispose();
      shader.dispose();
      // Skip the specular rim so a reflection can't be mistaken for the stripe.
      return List.generate(24, (index) => index + 6).firstWhere(
        (x) => pixels.getUint8((32 * 64 + x) * 4 + 1) > 135,
        orElse: () => -1,
      );
    }

    try {
      for (final dark in [false, true]) {
        final flat = await firstBrightPixel(0, dark: dark);
        final refracted = await firstBrightPixel(1, dark: dark);
        expect(flat, inInclusiveRange(18, 20));
        expect(refracted, greaterThan(0));
        expect(refracted, lessThanOrEqualTo(flat - 3));
      }
    } finally {
      texture.dispose();
    }
  });

  if (previewDirectory.isNotEmpty) {
    testWidgets('bakes the two optical backdrop textures', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const backdrop = Aura(child: SizedBox.expand());
      await capture(
        tester,
        atelierTheme(),
        backdrop,
        'atelier-wallpaper-light.png',
        pixelRatio: 1,
        useStage: false,
      );
      await capture(
        tester,
        atelierDarkTheme(),
        backdrop,
        'atelier-wallpaper-dark.png',
        pixelRatio: 1,
        useStage: false,
      );
    });

    testWidgets('renders the home dashboard for visual inspection', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 784);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() async {
        await ui.FragmentProgram.fromAsset('shaders/atelier_liquid.frag');
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        if (previewFont.isNotEmpty) {
          final loader = FontLoader('AtelierPreview')
            ..addFont(
              File(previewFont).readAsBytes().then(ByteData.sublistView),
            );
          await loader.load();
        }
      });
      final theme = atelierTheme(
        fontFamily: previewFont.isEmpty ? null : 'AtelierPreview',
      );
      final darkTheme = atelierDarkTheme(
        fontFamily: previewFont.isEmpty ? null : 'AtelierPreview',
      );

      await capture(tester, theme, dashboard(), 'forage-ios-dashboard.png');
      tester.view.physicalSize = const Size(1678, 896);
      await capture(
        tester,
        theme,
        dashboard(desktop: true),
        'forage-windows-dashboard.png',
      );
      await capture(
        tester,
        darkTheme,
        dashboard(desktop: true),
        'forage-windows-dashboard-dark.png',
      );
      await capture(
        tester,
        darkTheme,
        FormShell(
          title: 'Nouveau produit',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImageInput(
                bytes: null,
                label: 'Photo du produit *',
                onTap: () {},
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {},
                child: const Text('Enregistrer le produit'),
              ),
            ],
          ),
        ),
        'forage-photo-field-dark.png',
      );
    });
  }
}

Widget testLiquidStage(BuildContext context, Widget? child) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return ForageAppearanceScope(
    appearance: dark ? ForageAppearance.dark : ForageAppearance.light,
    onChanged: (_) {},
    child: AtelierLiquidStage(dark: dark, child: child!),
  );
}

Widget dashboard({
  VoidCallback? onFamilies,
  VoidCallback? onAnalytics,
  VoidCallback? onActivity,
  VoidCallback? onExport,
  ValueChanged<int>? onNavigate,
  bool desktop = false,
}) {
  final user = AppUser(
    id: 'preview',
    username: 'youssef',
    password: '',
    fullName: 'Youssef',
    admin: true,
  );
  final page = DashboardPage(
    user: user,
    productCount: 48,
    machineCount: 6,
    pendingReviews: 2,
    onProducts: () {},
    onStock: () {},
    onMachines: () {},
    onTeam: () {},
    onValidation: () {},
    onCategories: onFamilies ?? () {},
    onReviews: () {},
    forceDesktopLayout: desktop,
  );
  if (desktop) {
    return Scaffold(
      body: Aura(
        child: WindowsWorkspaceShell(
          title: 'Accueil',
          user: user,
          section: 0,
          onSectionChanged: onNavigate ?? (_) {},
          onLogout: () {},
          onOpenTeam: () {},
          onOpenBackups: () {},
          onOpenAnalytics: () {},
          canAccessAnalytics: true,
          canExport: true,
          onOpenExport: () {},
          onOpenDeveloper: () {},
          child: page,
        ),
      ),
    );
  }
  return Scaffold(
    extendBody: true,
    body: Aura(
      child: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Accueil',
              user: user,
              onLogout: () {},
              onOpenTeam: () {},
              onOpenBackups: () {},
              onOpenAnalytics: onAnalytics ?? () {},
              onOpenActivity: onActivity ?? () {},
              canAccessAnalytics: true,
              canExport: true,
              onOpenExport: onExport ?? () {},
            ),
            Expanded(child: page),
          ],
        ),
      ),
    ),
    bottomNavigationBar: MobileGlassNavigation(
      index: 0,
      showTeam: true,
      onTap: onNavigate ?? (_) {},
    ),
  );
}

Future<void> capture(
  WidgetTester tester,
  ThemeData theme,
  Widget screen,
  String file, {
  double pixelRatio = 1.5,
  bool useStage = true,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: useStage ? testLiquidStage : null,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$previewDirectory/$file').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}
