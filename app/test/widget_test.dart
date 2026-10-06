// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_dictionary/main.dart';
import 'package:local_dictionary/models/article.dart';
import 'package:local_dictionary/models/dictionary_library_entry.dart';
import 'package:local_dictionary/platform/reader_platform_policy.dart';
import 'package:local_dictionary/screens/home_page.dart';
import 'package:local_dictionary/services/dictionary_engine.dart';
import 'package:local_dictionary/services/dictionary_library.dart';
import 'package:local_dictionary/services/word_records.dart';

void main() {
  testWidgets('shows the empty local-dictionary state', (tester) async {
    await tester.pumpWidget(const DictionaryApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('建立你的离线词典库'), findsOneWidget);
    expect(find.text('导入第一本词典'), findsOneWidget);
  });

  testWidgets('empty state stays overflow-free in a short window',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DictionaryApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('uses bottom navigation on compact screens', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DictionaryApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.auto_stories_outlined));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏词汇'), findsOneWidget);
  });

  testWidgets('1080p and 4K at 200 percent share the wide logical layout',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> expectWideLayout(Size physicalSize, double pixelRatio) async {
      tester.view.physicalSize = physicalSize;
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(const DictionaryApp());
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(tester.takeException(), isNull);
    }

    await expectWideLayout(const Size(1920, 1080), 1);
    await expectWideLayout(const Size(3840, 2160), 2);
  });

  testWidgets('global desktop theme remains touch friendly', (tester) async {
    await tester.pumpWidget(const DictionaryApp());
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final behavior = materialApp.scrollBehavior!;
    expect(behavior, isA<LumaLexScrollBehavior>());
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
    expect(behavior.dragDevices, contains(PointerDeviceKind.stylus));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.visualDensity, VisualDensity.standard);
    expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
  });

  testWidgets('process-text mode shows a compact floating lookup shell',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const DictionaryApp(
        processTextMode: true,
        initialQuery: 'increase',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LumaLex'), findsOneWidget);
    expect(find.text('increase'), findsOneWidget);
    expect(find.byKey(const ValueKey('process-text-search-navigation')),
        findsOneWidget);
    final searchBar = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(searchBar.constraints?.minHeight, 44);
    expect(searchBar.constraints?.maxHeight, 44);
    expect(find.byTooltip('调整字号'), findsOneWidget);
    expect(find.byTooltip('收藏单词'), findsOneWidget);
    expect(find.byTooltip('最大化或恢复窗口'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persistent text-size entry toggles without scrolling',
      (tester) async {
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ReaderTextScaleToggleButton(
                key: const ValueKey('reader-text-scale-toggle'),
                expanded: expanded,
                onPressed: () => setState(() => expanded = !expanded),
              );
            },
          ),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('reader-text-scale-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.byTooltip('调整字号'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byTooltip('收起字号调整'), findsOneWidget);
  });

  testWidgets('narrow lookup header uses a compact home action',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LookupHomeButton(iconOnly: true, onPressed: () {}),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('lookup-home-icon-button')), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('查词首页'), findsNothing);
    expect(find.byTooltip('返回查词首页'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LookupHomeButton(iconOnly: false, onPressed: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('lookup-home-labeled-button')),
        findsOneWidget);
    expect(find.text('查词首页'), findsOneWidget);
  });

  testWidgets('reader favorite keeps a transparent full-size tap target',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderFavoriteButton(
            favorite: false,
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    final finder = find.byKey(const ValueKey('reader-favorite-button'));
    final button = tester.widget<IconButton>(finder);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(
      button.style?.minimumSize?.resolve(<WidgetState>{}),
      const Size.square(48),
    );
    await tester.tap(finder);
    expect(taps, 1);
  });

  testWidgets('lookup correction notice can close and auto-dismisses',
      (tester) async {
    var visible = true;
    var dismissCount = 0;

    Widget buildBanner() => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => visible
                  ? LookupCorrectionBanner(
                      original: 'temporery',
                      replacement: 'temporary',
                      onDismiss: () {
                        dismissCount += 1;
                        setState(() => visible = false);
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        );

    await tester.pumpWidget(buildBanner());
    expect(find.text('未找到“temporery”，已显示“temporary”。'), findsOneWidget);
    expect(find.byTooltip('关闭提示'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(LookupCorrectionBanner), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LookupCorrectionBanner), findsNothing);
    expect(dismissCount, 1);

    visible = true;
    await tester.pumpWidget(buildBanner());
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();
    expect(find.byType(LookupCorrectionBanner), findsNothing);
    expect(dismissCount, 2);
  });

  testWidgets('foreground refreshes records written by a floating lookup',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final wordRecords = InMemoryWordRecordsStore();

    await tester.pumpWidget(DictionaryApp(wordRecords: wordRecords));
    await tester.pumpAndSettle();

    // A PROCESS_TEXT window runs in another Flutter engine. Writing directly
    // to the shared store models that engine while this launcher keeps its
    // original in-memory snapshot.
    await wordRecords.saveHistory(['floating-history']);
    await wordRecords.saveFavorites(['floating-favorite']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_stories_outlined));
    await tester.pumpAndSettle();
    expect(find.text('floating-favorite'), findsOneWidget);

    await tester.tap(find.text('管理历史'));
    await tester.pumpAndSettle();
    expect(find.text('floating-history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold aggregate lookup restores all dictionaries before query',
      (tester) async {
    const fileAccessChannel = MethodChannel('local_dictionary/file_access');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fileAccessChannel, (call) async {
      if (call.method == 'restoreReadBookmark') return true;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(fileAccessChannel, null),
    );

    final directory = Directory.systemTemp.createTempSync('lumalex-cold-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final library = InMemoryDictionaryLibrary();
    final paths = <String>[];
    for (var index = 0; index < 3; index++) {
      final path = '${directory.path}/dictionary-$index.mdx';
      File(path).writeAsBytesSync(const [0]);
      paths.add(path);
      await library.upsert(
        DictionaryLibraryEntry(
          title: 'Dictionary $index',
          mdxPath: path,
          importedAtMilliseconds: index,
        ),
      );
    }
    final engine = _RecordingDictionaryEngine();

    await tester.pumpWidget(
      DictionaryApp(
        engine: engine,
        library: library,
        initialQuery: 'lookup',
        readerPlatformPolicy:
            ReaderPlatformPolicy.forOperatingSystem('android'),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 50 && engine.lookedUpPaths.toSet().length < paths.length;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(engine.importedPaths.toSet(), paths.toSet());
    expect(engine.lookedUpPaths.toSet(), paths.toSet());
    expect(engine.firstLookupImportCount, paths.length);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uses comfortable navigation sizing on wide tablets',
      (tester) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DictionaryApp());
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.minExtendedWidth, 244);
    expect(rail.selectedIconTheme?.size, 32);
    expect(rail.unselectedIconTheme?.size, 30);
    expect(rail.selectedLabelTextStyle?.fontSize, 17);
    expect(rail.unselectedLabelTextStyle?.fontSize, 17);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide iPad lookup does not show the desktop dictionary rail',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync('lumalex-ipad-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final mdx = File('${directory.path}/test.mdx');
    mdx.writeAsBytesSync(const [0]);
    final library = InMemoryDictionaryLibrary();
    await library.upsert(
      DictionaryLibraryEntry(
        title: 'Test Dictionary',
        mdxPath: mdx.path,
        importedAtMilliseconds: 0,
      ),
    );

    await tester.pumpWidget(
      DictionaryApp(
        engine: const _AvailableDictionaryEngine(),
        library: library,
        initialQuery: 'lookup',
        readerPlatformPolicy: ReaderPlatformPolicy.forOperatingSystem('ios'),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.text('在以下词典中找到'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('condenses wordbook and dictionary headers on short phones',
      (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DictionaryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_stories_outlined));
    await tester.pumpAndSettle();
    expect(find.byTooltip('管理历史'), findsOneWidget);
    expect(find.text('收藏词汇会保存在这里，并自动加入闪卡复习计划。'), findsNothing);

    await tester.tap(find.byIcon(Icons.library_books_outlined));
    await tester.pumpAndSettle();
    expect(find.byTooltip('导入词典'), findsOneWidget);
    expect(find.text('管理本地 MDX/MDD 文件，启用的词典会参与查词。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dictionary management rows do not select or leave the page',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('lumalex-library-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final mdx = File('${directory.path}/test.mdx');
    mdx.writeAsBytesSync(const [0]);
    final library = InMemoryDictionaryLibrary();
    await library.upsert(
      DictionaryLibraryEntry(
        title: 'Test Dictionary',
        mdxPath: mdx.path,
        importedAtMilliseconds: 0,
      ),
    );

    await tester.pumpWidget(
      DictionaryApp(
        engine: const _AvailableDictionaryEngine(),
        library: library,
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.library_books_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final row = find.ancestor(
      of: find.text('Test Dictionary'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNothing,
    );
    expect(tester.widget<ListTile>(row).onTap, isNull);

    await tester.tap(find.text('Test Dictionary'));
    await tester.pump();
    expect(find.text('Test Dictionary'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a saved word enters the first flashcard review session',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final wordRecords = InMemoryWordRecordsStore();
    await wordRecords.saveFavorites(['review']);

    await tester.pumpWidget(DictionaryApp(wordRecords: wordRecords));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_stories_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习'));
    await tester.pumpAndSettle();

    expect(find.text('待复习 1 张'), findsOneWidget);
    expect(find.text('review'), findsOneWidget);
    await tester.tap(find.text('显示释义'));
    await tester.pumpAndSettle();
    expect(find.text('词典摘要'), findsOneWidget);
    expect(find.text('再来一次'), findsOneWidget);
  });
}

final class _AvailableDictionaryEngine implements DictionaryEngine {
  const _AvailableDictionaryEngine();

  @override
  void clearActiveDictionary() {}

  @override
  Future<void> ensureIndex({required String mdxPath}) async {}

  @override
  Future<String> importMdx({required String mdxPath, String? mddPath}) async =>
      'Test Dictionary';

  @override
  Future<List<Article>> lookup(String query, {String? mdxPath}) async =>
      const [];

  @override
  Future<DictionaryResourceData?> readResource(
    String resourcePath, {
    required int maxBytes,
    String? mdxPath,
  }) async =>
      null;

  @override
  Future<List<String>> suggest(
    String prefix, {
    required int limit,
    String? mdxPath,
  }) async =>
      const [];
}

final class _RecordingDictionaryEngine implements DictionaryEngine {
  final List<String> importedPaths = [];
  final List<String> lookedUpPaths = [];
  int? firstLookupImportCount;

  @override
  void clearActiveDictionary() {}

  @override
  Future<void> ensureIndex({required String mdxPath}) async {}

  @override
  Future<String> importMdx({required String mdxPath, String? mddPath}) async {
    importedPaths.add(mdxPath);
    return File(mdxPath).uri.pathSegments.last;
  }

  @override
  Future<List<Article>> lookup(String query, {String? mdxPath}) async {
    firstLookupImportCount ??= importedPaths.length;
    if (mdxPath != null) lookedUpPaths.add(mdxPath);
    return const [];
  }

  @override
  Future<DictionaryResourceData?> readResource(
    String resourcePath, {
    required int maxBytes,
    String? mdxPath,
  }) async =>
      null;

  @override
  Future<List<String>> suggest(
    String prefix, {
    required int limit,
    String? mdxPath,
  }) async =>
      const [];
}
