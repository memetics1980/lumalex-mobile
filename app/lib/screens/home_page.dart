import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/article.dart';
import '../models/dictionary_group.dart';
import '../models/dictionary_library_entry.dart';
import '../models/dictionary_result_navigation.dart';
import '../models/dictionary_result_position.dart';
import '../models/lookup_navigation.dart';
import '../models/lookup_result_cache.dart';
import '../models/reader_position_cache.dart';
import '../models/reader_page_swipe.dart';
import '../models/review_card.dart';
import '../models/retained_reader_order.dart';
import '../models/retained_reader_slots.dart';
import '../models/search_fallback.dart';
import '../platform/android_process_text_window.dart';
import '../platform/android_reader_memory.dart';
import '../platform/reader_platform_policy.dart';
import '../services/app_diagnostics.dart';
import '../services/dictionary_engine.dart';
import '../services/dictionary_content_server.dart';
import '../services/dictionary_file_access.dart';
import '../services/dictionary_folder_scanner.dart';
import '../services/dictionary_groups.dart';
import '../services/dictionary_library.dart';
import '../services/dictionary_reader_prewarmer.dart';
import '../services/ios_dictionary_home.dart';
import '../services/learning_data_transfer.dart';
import '../services/reader_diagnostics.dart';
import '../services/word_records.dart';
import 'aggregate_article_page.dart';
import 'app_diagnostics_sheet.dart';
import 'article_page.dart';

enum _AppDestination { lookup, wordbook, dictionaries }

typedef _DictionaryImportTarget = ({
  List<String> mdxPaths,
  String accessPath,
  bool copiedIntoIosHome,
  int skippedFolderCount,
  Map<String, List<String>> mddPathsByMdx,
  Map<String, List<DictionarySidecarResource>> sidecarResourcesByMdx,
  Map<String, AndroidDictionarySource> androidSourcesByMdx,
});

const _dictionaryGroupColors = <Color>[
  Color(0xFF087E87),
  Color(0xFF356FD4),
  Color(0xFF2D8A57),
  Color(0xFFD08A16),
  Color(0xFF7B57C2),
  Color(0xFFC6536A),
];

const _dictionaryGroupColorNames = <String>[
  '青绿',
  '蓝色',
  '绿色',
  '琥珀',
  '紫色',
  '玫红',
];

class LookupHomeButton extends StatelessWidget {
  const LookupHomeButton({
    required this.iconOnly,
    required this.onPressed,
    super.key,
  });

  final bool iconOnly;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return IconButton(
        key: const ValueKey('lookup-home-icon-button'),
        tooltip: '返回查词首页',
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_rounded),
        style: IconButton.styleFrom(minimumSize: const Size.square(44)),
      );
    }
    return Tooltip(
      message: '结束当前阅读并返回查词首页',
      child: TextButton.icon(
        key: const ValueKey('lookup-home-labeled-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.search_rounded, size: 20),
        label: const Text('查词首页'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class ReaderTextScaleToggleButton extends StatelessWidget {
  const ReaderTextScaleToggleButton({
    required this.expanded,
    required this.onPressed,
    super.key,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: expanded ? '收起字号调整' : '调整字号',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          backgroundColor: expanded
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
        ),
        icon: Text(
          'Aa',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: expanded
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class ReaderFavoriteButton extends StatelessWidget {
  const ReaderFavoriteButton({
    required this.favorite,
    required this.onPressed,
    super.key,
  });

  final bool favorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('reader-favorite-button'),
      tooltip: favorite ? '取消收藏' : '收藏单词',
      onPressed: onPressed,
      iconSize: 30,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: Colors.transparent,
        foregroundColor:
            favorite ? const Color(0xFFF2A51A) : colors.onSurfaceVariant,
        overlayColor: colors.primary.withValues(alpha: 0.12),
      ),
      icon: Icon(
        favorite ? Icons.star_rounded : Icons.star_outline_rounded,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.engine,
    required this.dictionaryGroups,
    required this.library,
    required this.wordRecords,
    this.initialQuery = '',
    this.processTextMode = false,
    this.readerPlatformPolicy,
    super.key,
  });

  final DictionaryEngine engine;
  final DictionaryGroupsStore dictionaryGroups;
  final DictionaryLibrary library;
  final WordRecordsStore wordRecords;
  final String initialQuery;
  final bool processTextMode;
  final ReaderPlatformPolicy? readerPlatformPolicy;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _queryController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final _readerPlatformPolicy =
      widget.readerPlatformPolicy ?? ReaderPlatformPolicy.current;
  late int _maximumRetainedReaders;
  AndroidReaderMemoryProfile? _androidReaderMemoryProfile;
  // A fully rendered ODE_2024 entry can approach 1 MB of HTML before WebKit
  // expands it into a DOM, styles and decoded image resources. Retaining
  // several invisible WKWebViews is a memory-risk on iPhone/iPad.
  // Keep a small LRU of rendered dictionaries for the current word. Returning
  // to a recent dictionary becomes a pure IndexedStack switch instead of a
  // full Chromium navigation, while a 10+ dictionary library cannot create
  // an unbounded number of platform WebViews.
  final Map<String, ArticlePageController> _articleControllers = {};
  final _aggregateArticleController = AggregateArticlePageController();
  List<String> _retainedReaderPaths = const [];
  late List<String?> _retainedReaderSlots;
  final _readerPositionCache = ReaderPositionCache();
  String _readerQuery = '';
  Map<String, List<Article>> _articlesByDictionary = const {};
  Set<String> _availableMdxPaths = const {};
  final Set<String> _failedMdxPaths = {};
  final Map<String, Future<bool>> _dictionaryPreparations = {};
  double _textScale = 1;
  List<String> _history = const [];
  List<String> _favorites = const [];
  List<ReviewCard> _reviewCards = const [];
  String? _selectedMdxPath;
  String? _articleAnchor;
  double? _articleScrollOffset;
  ({String original, String replacement})? _lookupCorrection;
  bool _isSearching = false;
  bool _isImporting = false;
  bool _isScanningIosDictionaryHome = false;
  bool _isRefreshingIosSources = false;
  bool _isLibraryLoading = true;
  List<DictionaryLibraryEntry> _libraryEntries = const [];
  DictionaryGroupSnapshot _dictionaryGroupSnapshot =
      const DictionaryGroupSnapshot();
  final Set<String> _expandedDictionaryGroupIds = <String>{};
  List<String> _suggestions = const [];
  int _selectedSuggestionIndex = -1;
  Timer? _suggestionDebounce;
  Timer? _indexMigrationDelay;
  Timer? _dictionaryWarmupDelay;
  Timer? _readerWarmupDelay;
  Timer? _readerControlsTimer;
  Timer? _readerPreloadDelay;
  Timer? _readerRecoveryDelay;
  Timer? _iosDictionaryHomeScanDelay;
  Timer? _wordRecordsRefreshDelay;
  DateTime? _iosReaderBackgroundedAt;
  int _dictionaryWarmupGeneration = 0;
  int _suggestionRequest = 0;
  int _lookupRequest = 0;
  int _wordRecordsMutationGeneration = 0;
  late final Future<void> _wordRecordsReady;
  late final Future<Directory?> _iosDictionaryHomeReady;
  final _fileAccess = DictionaryFileAccess();
  final _appDiagnostics = AppDiagnosticsService();
  final _iosDictionaryHome = IosDictionaryHome();
  final _lookupNavigation = LookupNavigationHistory();
  final _lookupResultCache = LookupResultCache();
  _AppDestination _destination = _AppDestination.lookup;
  bool _showReaderTextControls = false;
  bool _reviewAnswerVisible = false;
  double _dictionarySelectorDragDistance = 0;
  final _readerPageSwipe = ReaderPageSwipeTracker();

  @override
  void initState() {
    super.initState();
    _maximumRetainedReaders = _readerPlatformPolicy.maximumRetainedReaders;
    _retainedReaderSlots = List<String?>.filled(
      _readerPlatformPolicy.maximumRetainedReaders,
      null,
      growable: false,
    );
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.onKeyEvent = _handleSearchKeyEvent;
    final initialQuery = widget.initialQuery.trim();
    if (initialQuery.isNotEmpty) {
      _queryController.value = TextEditingValue(
        text: initialQuery,
        selection: TextSelection.collapsed(offset: initialQuery.length),
      );
    }
    _iosDictionaryHomeReady = _iosDictionaryHome.ensureExists();
    final libraryReady = _loadLibrary();
    if (initialQuery.isNotEmpty) {
      unawaited(
        libraryReady.then((_) async {
          if (!mounted || _availableEntries.isEmpty) return;
          await _startNewLookup(initialQuery);
        }),
      );
    }
    if (Platform.isIOS) {
      unawaited(_scanIosDictionaryHomeAfterStartup(libraryReady));
    }
    _wordRecordsReady = _loadWordRecords();
    if (_readerPlatformPolicy.adaptiveReaderRetention) {
      unawaited(_loadAndroidReaderMemoryProfile());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Mobile is where cold WebView startup is visible and where a process
      // normally lives for the whole session. Desktop widget tests and short
      // desktop windows should not acquire a permanent loopback listener just
      // for showing an empty library.
      if (Platform.isAndroid || Platform.isIOS) {
        unawaited(DictionaryContentServer.instance.prewarm());
        _readerWarmupDelay = Timer(const Duration(milliseconds: 250), () {
          if (mounted) {
            unawaited(DictionaryReaderPrewarmer.instance.prewarm());
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _suggestionDebounce?.cancel();
    _indexMigrationDelay?.cancel();
    _dictionaryWarmupDelay?.cancel();
    _dictionaryWarmupGeneration++;
    _readerWarmupDelay?.cancel();
    unawaited(DictionaryReaderPrewarmer.instance.disposeUnused());
    _readerControlsTimer?.cancel();
    _readerPreloadDelay?.cancel();
    _readerRecoveryDelay?.cancel();
    _iosDictionaryHomeScanDelay?.cancel();
    _wordRecordsRefreshDelay?.cancel();
    _searchFocusNode.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleWordRecordsRefresh();
    }
    if (Platform.isAndroid) {
      if (state == AppLifecycleState.resumed) {
        _restoreAndroidReaderRetentionLimit();
      }
      return;
    }
    if (!Platform.isIOS) {
      return;
    }
    if (state != AppLifecycleState.resumed) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        _iosReaderBackgroundedAt ??= DateTime.now();
      }
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        _setMaximumRetainedReaders(
          _readerPlatformPolicy.memoryPressureRetainedReaders,
        );
      }
      return;
    }

    _setMaximumRetainedReaders(
      _readerPlatformPolicy.maximumRetainedReaders,
    );
    final backgroundedAt = _iosReaderBackgroundedAt;
    _iosReaderBackgroundedAt = null;
    final backgroundDuration = backgroundedAt == null
        ? Duration.zero
        : DateTime.now().difference(backgroundedAt);
    _readerRecoveryDelay?.cancel();
    _readerRecoveryDelay = Timer(const Duration(milliseconds: 350), () {
      _readerRecoveryDelay = null;
      if (mounted) {
        unawaited(
          _recoverReadersAfterForeground(
            backgroundDuration: backgroundDuration,
          ),
        );
      }
    });
    _iosDictionaryHomeScanDelay?.cancel();
    _iosDictionaryHomeScanDelay = Timer(
      const Duration(milliseconds: 700),
      () {
        _iosDictionaryHomeScanDelay = null;
        if (mounted && !_isLibraryLoading && !_isImporting) {
          unawaited(_refreshIosSourcesAfterForeground());
        }
      },
    );
  }

  void _scheduleWordRecordsRefresh() {
    _wordRecordsRefreshDelay?.cancel();
    // PROCESS_TEXT is hosted by a second Flutter engine. Both engines use the
    // same uncached SharedPreferencesAsync store, but each HomePage keeps its
    // own in-memory view of history and favorites. Give any final platform
    // write from the closing floating Activity a moment to finish, then make
    // the launcher reflect that shared durable state when it returns.
    _wordRecordsRefreshDelay = Timer(const Duration(milliseconds: 200), () {
      _wordRecordsRefreshDelay = null;
      if (mounted) {
        unawaited(_refreshWordRecords());
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    if (!mounted) return;
    final contentServer = DictionaryContentServer.instance;
    final cachedResourceBytes = contentServer.cachedResourceBytes;
    final cachedResourceCount = contentServer.cachedResourceCount;
    contentServer.releaseCachedResources();
    ReaderDiagnostics.instance.record(
      'memory-pressure',
      data: {
        'platform': Platform.operatingSystem,
        'cachedResourceBytesReleased': cachedResourceBytes,
        'cachedResourceCountReleased': cachedResourceCount,
        if (_selectedMdxPath != null) 'selectedDictionary': _selectedMdxPath,
        'readerCount': _retainedReaderPaths.length,
      },
    );
    final selectedPath = _selectedMdxPath;
    if (selectedPath != null) {
      unawaited(
        _articleControllers[selectedPath]?.releaseTransientResources() ??
            Future.value(),
      );
    }
    _setMaximumRetainedReaders(
      _readerPlatformPolicy.memoryPressureRetainedReaders,
    );
  }

  Future<void> _loadAndroidReaderMemoryProfile() async {
    final profile = await AndroidReaderMemory.readProfile();
    if (!mounted || profile == null) return;
    _androidReaderMemoryProfile = profile;
    _restoreAndroidReaderRetentionLimit();
  }

  void _restoreAndroidReaderRetentionLimit() {
    final profile = _androidReaderMemoryProfile;
    if (!mounted || profile == null) return;
    _setMaximumRetainedReaders(
      _readerPlatformPolicy.retainedReadersForMemory(
        memoryClassMb: profile.memoryClassMb,
        isLowRamDevice: profile.isLowRamDevice,
      ),
    );
  }

  void _setMaximumRetainedReaders(int requestedLimit) {
    if (!mounted) return;
    final nextLimit = requestedLimit.clamp(1, 5).toInt();
    if (nextLimit == _maximumRetainedReaders) return;
    _rememberCurrentReaderPosition();
    final previousLimit = _maximumRetainedReaders;
    setState(() {
      _maximumRetainedReaders = nextLimit;
      _retainedReaderPaths = _adoptRetainedReaderPaths(
        trimRetainedReaderLru(
          retainedLruPaths: _retainedReaderPaths,
          selectedPath: _selectedMdxPath,
          maximumReaders: nextLimit,
        ),
      );
    });
    final selected = _selectedMdxPath;
    if (nextLimit > previousLimit &&
        selected != null &&
        _readerPlatformPolicy.preloadAdjacentDictionaryReader) {
      _preloadNextDictionaryReader(selected);
    }
  }

  Future<void> _recoverReadersAfterForeground({
    required Duration backgroundDuration,
  }) async {
    var serverRecovery = DictionaryContentServerRecovery.healthy;
    Object? serverRecoveryError;
    try {
      serverRecovery =
          await DictionaryContentServer.instance.recoverAfterForeground();
    } catch (error) {
      serverRecoveryError = error;
      debugPrint(
          'Dictionary content server foreground recovery failed: $error');
    }
    ReaderDiagnostics.instance.record(
      'application-foreground-recovery',
      data: {
        'backgroundMilliseconds': backgroundDuration.inMilliseconds,
        'serverRecovery': serverRecovery.name,
        'serverRecoveryFailed': serverRecoveryError != null,
      },
    );
    if (!mounted) return;
    // iOS keeps only the selected reader alive. Reloading invisible WebViews
    // after a lock/unlock event can briefly make several large documents live
    // at once, which is precisely when the OS is most likely to kill the app.
    final selectedPath = _selectedMdxPath;
    if (selectedPath == null || !_retainedReaderPaths.contains(selectedPath)) {
      return;
    }
    await _articleControllers[selectedPath]?.recoverAfterForeground(
      forceReload:
          serverRecovery == DictionaryContentServerRecovery.restarted ||
              serverRecoveryError != null,
    );
  }

  Future<void> _lookup(
    String rawQuery, {
    String? preferredMdxPath,
    String? initialAnchor,
    double? initialScrollOffset,
  }) async {
    final lookupTimer = Stopwatch()..start();
    // Allocate the request before any asynchronous dictionary restoration so
    // clearing the field or submitting another word cancels this whole path.
    final request = ++_lookupRequest;
    // A person waiting for a definition always wins over disposable index
    // migration. Rust also cancels a build already in progress.
    _indexMigrationDelay?.cancel();
    _indexMigrationDelay = null;
    final query = rawQuery.trim();
    _rememberCurrentReaderPosition();
    if (query.isEmpty) {
      setState(() {
        _articlesByDictionary = const {};
        _readerQuery = '';
        _articleAnchor = null;
        _articleScrollOffset = null;
        _lookupCorrection = null;
        _isSearching = false;
      });
      return;
    }
    _dictionaryWarmupDelay?.cancel();
    _dictionaryWarmupDelay = null;
    _dictionaryWarmupGeneration++;
    _readerWarmupDelay?.cancel();
    _readerWarmupDelay = null;
    if (_readerPlatformPolicy.aggregateDictionaryResults &&
        _hasPendingEnabledDictionary) {
      setState(() {
        _readerQuery = query;
        _suggestions = const [];
        _selectedSuggestionIndex = -1;
        _lookupCorrection = null;
        _isSearching = true;
      });
      await _prepareEnabledDictionariesForAggregateLookup();
      if (!mounted || request != _lookupRequest) return;
    }
    final dictionaries = _availableEntries;
    if (dictionaries.isEmpty) {
      setState(() => _isSearching = false);
      _showMessage(
        _supportsDictionaryGroups &&
                _activeDictionaryScopeId != DictionaryGroupScope.all
            ? '当前分组没有已启用且可访问的词典。请切换分组或前往词典页调整。'
            : '请先在词典库中启用至少一本词典。',
      );
      return;
    }

    unawaited(_wordRecordsReady.then((_) => _recordHistory(query)));
    final availablePaths = dictionaries.map((entry) => entry.mdxPath).toSet();
    final requestedPreferred = preferredMdxPath ?? _selectedMdxPath;
    final preferred = availablePaths.contains(requestedPreferred)
        ? requestedPreferred!
        : dictionaries.first.mdxPath;
    final cachedResults = <String, List<Article>>{};
    for (final entry in dictionaries) {
      final cached = _lookupResultCache.get(entry.mdxPath, query);
      if (cached != null) {
        cachedResults[entry.mdxPath] = cached;
      }
    }
    final resolvedResults = <String, List<Article>>{...cachedResults};
    setState(() {
      // Keep the current article visible while an uncached word is resolved.
      // Once the preferred result arrives, the persistent web view swaps its
      // document instead of being destroyed behind a blocking spinner.
      _articlesByDictionary = {...cachedResults};
      _selectedMdxPath = preferred;
      _readerQuery = query;
      _retainedReaderPaths = _adoptRetainedReaderPaths([preferred]);
      _articleAnchor = initialAnchor;
      _articleScrollOffset = initialScrollOffset;
      _suggestions = const [];
      _selectedSuggestionIndex = -1;
      _lookupCorrection = null;
      _isSearching = cachedResults.length != dictionaries.length;
    });

    Future<MapEntry<String, List<Article>>> resolveEntry(
      DictionaryLibraryEntry entry,
    ) async {
      List<Article> articles;
      try {
        articles = await _resolveArticles(entry, query);
      } catch (_) {
        articles = const [];
      }
      _lookupResultCache.put(entry.mdxPath, query, articles);
      resolvedResults[entry.mdxPath] = articles;
      // Publish results independently so the selected dictionary never waits
      // for every enabled source. Each newly available background result also
      // gets another chance to enter the bounded reader preload queue. Without
      // this, the first preload attempt can run before a slower MDX lookup has
      // finished and that dictionary would load only after the user selects it.
      if (mounted && request == _lookupRequest) {
        setState(() {
          _articlesByDictionary = {
            ..._articlesByDictionary,
            entry.mdxPath: articles,
          };
        });
        final selectedPath = _selectedMdxPath;
        if (articles.isNotEmpty && selectedPath != null) {
          _preloadNextDictionaryReader(selectedPath);
        }
      }
      return MapEntry(entry.mdxPath, articles);
    }

    final uncachedEntries = dictionaries
        .where((entry) => !cachedResults.containsKey(entry.mdxPath))
        .toList(growable: false);
    final preferredEntry = uncachedEntries
        .where((entry) => entry.mdxPath == preferred)
        .firstOrNull;
    if (preferredEntry != null) {
      await resolveEntry(preferredEntry);
      if (!mounted || request != _lookupRequest) {
        return;
      }
    }
    debugPrint(
      'LumaLex preferred result ready: query=$query '
      'dictionary=$preferred articles=${resolvedResults[preferred]?.length ?? 0} '
      'source=${preferredEntry == null ? 'memory' : 'mdx'} '
      'readyMs=${lookupTimer.elapsedMilliseconds}',
    );
    // The selected dictionary resolves first. Limit the remaining work to a
    // small pool: opening and decompressing every MDX at once can saturate a
    // phone's flash storage, delaying the WebView's first paint and making
    // scrolling feel uneven. Results still publish independently as each
    // dictionary finishes.
    await _resolveBackgroundEntries(
      uncachedEntries
          .where((entry) => entry.mdxPath != preferred)
          .toList(growable: false),
      resolveEntry,
    );
    if (!mounted || request != _lookupRequest) {
      return;
    }
    var completed = resolvedResults;
    ({String original, String replacement})? correction;
    final hasExactResult =
        completed.values.any((articles) => articles.isNotEmpty);
    if (!hasExactResult) {
      final fallback = await _findFallbackLookup(query, dictionaries, request);
      if (!mounted || request != _lookupRequest) {
        return;
      }
      if (fallback != null) {
        completed = fallback.results;
        _queryController.value = TextEditingValue(
          text: fallback.query,
          selection: TextSelection.collapsed(offset: fallback.query.length),
        );
        unawaited(
            _wordRecordsReady.then((_) => _recordHistory(fallback.query)));
        correction = (original: query, replacement: fallback.query);
      }
    }
    var selection = preferred;
    if (completed[preferred]?.isEmpty ?? true) {
      selection = dictionaries
              .where((entry) => completed[entry.mdxPath]?.isNotEmpty ?? false)
              .map((entry) => entry.mdxPath)
              .firstOrNull ??
          preferred;
    }
    setState(() {
      _articlesByDictionary = {
        ..._articlesByDictionary,
        ...completed,
      };
      _selectedMdxPath = selection;
      _readerQuery = _queryController.text.trim();
      _retainedReaderPaths = _adoptRetainedReaderPaths(
        _retainReaderPath(
          _retainedReaderPaths,
          selection,
        ),
      );
      _articleAnchor = selection == preferred ? initialAnchor : null;
      _articleScrollOffset =
          selection == preferred ? initialScrollOffset : null;
      _lookupCorrection = correction;
      _isSearching = false;
    });
    _scheduleIndexMigration(
      _libraryEntries,
      delay: const Duration(seconds: 3),
    );
    _scheduleDictionaryWarmup(
      _libraryEntries,
      delay: const Duration(seconds: 4),
    );
    debugPrint(
      'LumaLex query timing: query=$query dictionaries=${dictionaries.length} '
      'withResults=${completed.values.where((value) => value.isNotEmpty).length} '
      'fallback=${correction != null} '
      'totalMs=${lookupTimer.elapsedMilliseconds}',
    );
  }

  Future<({String query, Map<String, List<Article>> results})?>
      _findFallbackLookup(
    String query,
    List<DictionaryLibraryEntry> dictionaries,
    int request,
  ) async {
    final directCandidates = morphologicalFallbacks(query);
    for (final candidate in directCandidates) {
      final results = await _lookupAlternative(candidate, dictionaries);
      if (!mounted || request != _lookupRequest) return null;
      if (results.values.any((articles) => articles.isNotEmpty)) {
        return (query: candidate, results: results);
      }
    }

    final suggestionPool = <String>[];
    for (final prefix in spellingSearchPrefixes(query)) {
      final batches = await _suggestFromDictionaries(
        prefix,
        dictionaries,
        limit: 20,
      );
      if (!mounted || request != _lookupRequest) return null;
      suggestionPool.addAll(batches);
    }
    for (final candidate in rankSpellingCandidates(query, suggestionPool)) {
      final results = await _lookupAlternative(candidate, dictionaries);
      if (!mounted || request != _lookupRequest) return null;
      if (results.values.any((articles) => articles.isNotEmpty)) {
        return (query: candidate, results: results);
      }
    }
    return null;
  }

  Future<Map<String, List<Article>>> _lookupAlternative(
    String query,
    List<DictionaryLibraryEntry> dictionaries,
  ) async {
    // This path only runs after an exact lookup missed, but it still must not
    // turn a spelling fallback into a burst of simultaneous MDX opens. The
    // same small pool used for normal background results keeps flash I/O and
    // decompression from starving the visible dictionary.
    final results = <String, List<Article>>{};
    await _resolveBackgroundEntries(dictionaries, (entry) async {
      try {
        final articles = await _resolveArticles(entry, query);
        results[entry.mdxPath] = articles;
        return MapEntry(entry.mdxPath, articles);
      } catch (_) {
        const articles = <Article>[];
        results[entry.mdxPath] = articles;
        return MapEntry(entry.mdxPath, articles);
      }
    });
    return results;
  }

  Future<void> _resolveBackgroundEntries(
    List<DictionaryLibraryEntry> entries,
    Future<MapEntry<String, List<Article>>> Function(DictionaryLibraryEntry)
        resolve,
  ) async {
    const maximumConcurrentLookups = 2;
    var next = 0;
    Future<void> worker() async {
      while (next < entries.length) {
        final entry = entries[next++];
        await resolve(entry);
      }
    }

    await Future.wait(
      List.generate(
        entries.length.clamp(0, maximumConcurrentLookups),
        (_) => worker(),
      ),
    );
  }

  Future<List<Article>> _resolveArticles(
    DictionaryLibraryEntry entry,
    String query,
  ) async {
    final totalTimer = Stopwatch()..start();
    final memory = _lookupResultCache.get(entry.mdxPath, query);
    if (memory != null) {
      debugPrint(
        'LumaLex lookup timing: dictionary=${entry.title} query=$query '
        'source=memory totalMs=${totalTimer.elapsedMilliseconds}',
      );
      return memory;
    }

    // A raw-exact indexed MDX read takes about 0–2 ms on the representative
    // corpus, while reading and JSON-decoding a 300–400 KB persisted article
    // is measurably slower. Keep the process LRU, but let the source-bound key
    // index remain the only disk cache on this latency-critical path.
    final engineTimer = Stopwatch()..start();
    final articles = await widget.engine.lookup(
      query,
      mdxPath: entry.mdxPath,
    );
    engineTimer.stop();
    _lookupResultCache.put(entry.mdxPath, query, articles);
    debugPrint(
      'LumaLex lookup timing: dictionary=${entry.title} query=$query '
      'source=mdx engineMs=${engineTimer.elapsedMilliseconds} '
      'totalMs=${totalTimer.elapsedMilliseconds}',
    );
    return articles;
  }

  Future<void> _startNewLookup(String query) async {
    // Submitting a query switches the task from editing to reading. Clearing
    // focus here hides the IME and prevents a blinking caret from remaining
    // beside the resolved word while the article is on screen.
    _searchFocusNode.unfocus();
    setState(() {
      _lookupNavigation.clear();
      _suggestionRequest++;
      _suggestions = const [];
      _selectedSuggestionIndex = -1;
    });
    await _lookup(query, preferredMdxPath: _selectedMdxPath);
  }

  Future<LookupLocation?> _captureLookupLocation() async {
    final query = _queryController.text.trim();
    final mdxPath = _selectedMdxPath;
    if (query.isEmpty || mdxPath == null) {
      return null;
    }
    final aggregateOffset = _readerPlatformPolicy.aggregateDictionaryResults
        ? await _aggregateArticleController.readScrollOffset()
        : null;
    final scrollOffset = aggregateOffset ??
        await _articleControllers[mdxPath]?.readScrollOffset() ??
        0;
    return LookupLocation(
      query: query,
      mdxPath: mdxPath,
      scrollOffset: scrollOffset,
    );
  }

  Future<void> _openLinkedHeadword(
    DictionaryLibraryEntry sourceDictionary,
    String headword,
    String? anchor,
    double sourceScrollOffset,
  ) async {
    final sourceQuery = _queryController.text.trim();
    if (sourceQuery.isNotEmpty) {
      setState(() {
        _lookupNavigation.recordDeparture(
          LookupLocation(
            query: sourceQuery,
            mdxPath: sourceDictionary.mdxPath,
            scrollOffset: sourceScrollOffset,
          ),
        );
      });
    }
    _queryController.value = TextEditingValue(
      text: headword,
      selection: TextSelection.collapsed(offset: headword.length),
    );
    await _lookup(
      headword,
      preferredMdxPath: sourceDictionary.mdxPath,
      initialAnchor: anchor,
    );
  }

  Future<void> _goBack() => _moveThroughLookupHistory(forward: false);

  Future<void> _goForward() => _moveThroughLookupHistory(forward: true);

  Future<void> _moveThroughLookupHistory({required bool forward}) async {
    if (_isSearching) {
      return;
    }
    final current = await _captureLookupLocation();
    if (!mounted || current == null) {
      return;
    }
    LookupLocation? destination;
    setState(() {
      destination = forward
          ? _lookupNavigation.goForwardFrom(current)
          : _lookupNavigation.goBackFrom(current);
    });
    final target = destination;
    if (target == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    _queryController.value = TextEditingValue(
      text: target.query,
      selection: TextSelection.collapsed(offset: target.query.length),
    );
    await _lookup(
      target.query,
      preferredMdxPath: target.mdxPath,
      initialScrollOffset: target.scrollOffset,
    );
  }

  void _suggest(String rawPrefix) {
    _suggestionDebounce?.cancel();
    final prefix = rawPrefix.trim();
    final request = ++_suggestionRequest;
    final dictionaries = _availableEntries;
    if (prefix.isEmpty || dictionaries.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = const [];
          _selectedSuggestionIndex = -1;
        });
      }
      return;
    }

    _suggestionDebounce = Timer(
      const Duration(milliseconds: 180),
      () => _runSuggestion(prefix, request, dictionaries),
    );
  }

  Future<void> _runSuggestion(
    String prefix,
    int request,
    List<DictionaryLibraryEntry> dictionaries,
  ) async {
    try {
      final suggestions = await _suggestFromDictionaries(
        prefix,
        dictionaries,
        limit: 8,
      );
      if (mounted && request == _suggestionRequest) {
        setState(() {
          _suggestions = suggestions;
          _selectedSuggestionIndex = suggestions.isEmpty ? -1 : 0;
        });
      }
    } catch (_) {
      if (mounted && request == _suggestionRequest) {
        setState(() {
          _suggestions = const [];
          _selectedSuggestionIndex = -1;
        });
      }
    }
  }

  Future<List<String>> _suggestFromDictionaries(
    String prefix,
    List<DictionaryLibraryEntry> dictionaries, {
    required int limit,
  }) async {
    final selectedPath = _selectedMdxPath;
    final ordered = List<DictionaryLibraryEntry>.of(dictionaries)
      ..sort((left, right) {
        final leftIsSelected = left.mdxPath == selectedPath;
        final rightIsSelected = right.mdxPath == selectedPath;
        if (leftIsSelected == rightIsSelected) return 0;
        return leftIsSelected ? -1 : 1;
      });
    final seen = <String>{};
    final suggestions = <String>[];
    for (final entry in ordered) {
      final batch = await widget.engine
          .suggest(prefix, limit: limit, mdxPath: entry.mdxPath)
          .catchError((Object _) => const <String>[]);
      for (final suggestion in batch) {
        if (seen.add(suggestion.toLowerCase())) {
          suggestions.add(suggestion);
        }
        if (suggestions.length == limit) {
          return suggestions;
        }
      }
    }
    return suggestions;
  }

  Future<void> _scanIosDictionaryHomeAfterStartup(
    Future<void> libraryReady,
  ) async {
    try {
      await libraryReady;
      await _iosDictionaryHomeReady;
    } catch (error, stackTrace) {
      debugPrint(
        'Unable to prepare the iOS dictionary home: $error\n$stackTrace',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scanIosDictionaryHome());
      }
    });
  }

  Future<void> _pickAndImport() async {
    if (Platform.isIOS) {
      await _scanIosDictionaryHome(announceWhenUnchanged: true);
      return;
    }
    await _pickExternalAndImport();
  }

  Future<void> _pickExternalAndImport() async {
    final target = await _selectDictionaryTarget();
    if (target == null) {
      return;
    }
    await _importDictionaryTarget(target);
  }

  Future<void> _scanIosDictionaryHome({
    bool announceWhenUnchanged = false,
  }) async {
    if (!Platform.isIOS ||
        _isImporting ||
        _isLibraryLoading ||
        _isScanningIosDictionaryHome) {
      return;
    }
    _isScanningIosDictionaryHome = true;
    try {
      final target = await _selectDictionaryTarget(
        useIosDictionaryHome: true,
        showEmptyMessage: announceWhenUnchanged,
      );
      if (target == null || !mounted) {
        return;
      }

      final discoveredPaths = target.mdxPaths.toSet();
      final knownPaths = _libraryEntries.map((entry) => entry.mdxPath).toSet();
      final changedPaths = <String>{};
      for (final entry in _libraryEntries.where(
        (entry) =>
            entry.accessPath == target.accessPath &&
            discoveredPaths.contains(entry.mdxPath),
      )) {
        try {
          final currentVersion =
              await _fileAccess.sourceVersionForMdx(entry.mdxPath);
          if (currentVersion != null && currentVersion != entry.sourceVersion) {
            changedPaths.add(entry.mdxPath);
          }
        } on FileSystemException {
          // The import pass will report a durable read failure. A transient
          // metadata failure must not make a healthy dictionary disappear.
        }
      }
      final missingPaths = _libraryEntries
          .where((entry) => entry.accessPath == target.accessPath)
          .map((entry) => entry.mdxPath)
          .where((path) => !discoveredPaths.contains(path))
          .toSet();
      final pathsToImport = target.mdxPaths
          .where(
            (path) =>
                !knownPaths.contains(path) ||
                _failedMdxPaths.contains(path) ||
                changedPaths.contains(path),
          )
          .toList(growable: false);

      if (missingPaths.isNotEmpty) {
        setState(() {
          _availableMdxPaths = {..._availableMdxPaths}..removeAll(missingPaths);
          _failedMdxPaths.addAll(missingPaths);
        });
      }
      if (pathsToImport.isEmpty) {
        if (announceWhenUnchanged) {
          _showMessage(
            missingPaths.isEmpty
                ? '词典目录已是最新，没有发现新的 MDX 文件。'
                : '已刷新词典目录；有 ${missingPaths.length} 本词典的源文件已移除。',
          );
        }
        return;
      }

      await _importDictionaryTarget((
        mdxPaths: pathsToImport,
        accessPath: target.accessPath,
        copiedIntoIosHome: target.copiedIntoIosHome,
        skippedFolderCount: target.skippedFolderCount,
        mddPathsByMdx: target.mddPathsByMdx,
        sidecarResourcesByMdx: target.sidecarResourcesByMdx,
        androidSourcesByMdx: target.androidSourcesByMdx,
      ));
    } finally {
      _isScanningIosDictionaryHome = false;
    }
  }

  Future<void> _importDictionaryTarget(_DictionaryImportTarget target) async {
    if (!mounted) {
      return;
    }

    final accessPath = target.accessPath;
    final mdxPaths = target.mdxPaths;
    final successfulPaths = <String>[];
    final failedPaths = <String>[];
    final importFailures = <String>[];
    var addedCount = 0;
    var refreshedCount = 0;
    var duplicateCount = 0;
    var unchangedCount = 0;
    var removedRedundantIosCopy = false;
    var libraryChanged = false;
    final changedSourcePaths = <String>{};
    var libraryEntries = List<DictionaryLibraryEntry>.of(_libraryEntries);
    var savedReadGrant = true;
    final progress = ValueNotifier((
      completed: 0,
      total: mdxPaths.length,
      fileName: '正在准备…',
    ));

    setState(() => _isImporting = true);
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.library_add_rounded),
          title: Text('正在检查 ${mdxPaths.length} 本词典'),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) => SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value:
                        value.total == 0 ? null : value.completed / value.total,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${value.completed}/${value.total}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      try {
        await _fileAccess.retain(accessPath);
      } catch (_) {
        savedReadGrant = false;
      }

      // Refresh existing rows without re-importing or replacing their user
      // settings. Unchanged registrations are deliberately a no-op in the
      // file-access layer, so live readers keep their resource handles.
      for (var index = 0; index < mdxPaths.length; index++) {
        final mdxPath = mdxPaths[index];
        final existingIndex = libraryEntries.indexWhere(
          (entry) => entry.mdxPath == mdxPath,
        );
        if (existingIndex < 0) continue;
        final existing = libraryEntries[existingIndex];
        final source = target.androidSourcesByMdx[mdxPath];
        final mddPaths = target.mddPathsByMdx[mdxPath] ?? existing.mddPaths;
        final sidecars =
            target.sidecarResourcesByMdx[mdxPath] ?? existing.sidecarResources;
        if (source != null) {
          _fileAccess.registerSource(
            mdxPath,
            mddPaths,
            sidecarResources: sidecars,
            accessPath: accessPath,
          );
        }
        progress.value = (
          completed: index,
          total: mdxPaths.length,
          fileName: _dictionaryFileName(mdxPath),
        );
        try {
          final currentSourceVersion = source?.sourceVersion ??
              await _fileAccess.sourceVersionForMdx(mdxPath);
          var refreshed = existing.copyWith(
            accessPath: accessPath,
            sourceRelativePath:
                source?.relativePath ?? existing.sourceRelativePath,
            sourceVersion: currentSourceVersion ?? existing.sourceVersion,
            mddPaths: mddPaths,
            sidecarResources: sidecars,
          );
          final sourceChanged = !_sameDictionarySource(existing, refreshed);
          final sourceVersionChanged = currentSourceVersion != null &&
              currentSourceVersion != existing.sourceVersion;
          if (sourceVersionChanged) {
            _fileAccess.invalidateMdxSource(mdxPath);
            changedSourcePaths.add(mdxPath);
          }
          final mustValidate = _failedMdxPaths.contains(mdxPath) ||
              !_availableMdxPaths.contains(mdxPath) ||
              sourceChanged;
          if (mustValidate) {
            await widget.engine.importMdx(mdxPath: mdxPath);
          }
          if (refreshed.contentFingerprint == null || sourceVersionChanged) {
            refreshed = refreshed.copyWith(
              contentFingerprint: await _fileAccess.fingerprintMdx(mdxPath),
            );
          }
          _failedMdxPaths.remove(mdxPath);
          libraryEntries[existingIndex] = refreshed;
          if (!_sameDictionaryEntry(existing, refreshed)) {
            libraryChanged = true;
            refreshedCount++;
          } else {
            unchangedCount++;
          }
          if (mustValidate) successfulPaths.add(mdxPath);
        } catch (error, stackTrace) {
          debugPrint(
            'Dictionary refresh failed for $mdxPath: $error\n$stackTrace',
          );
          failedPaths.add(mdxPath);
          _failedMdxPaths.add(mdxPath);
          importFailures.add(
            '${_dictionaryFileName(mdxPath)}：${_describeImportError(error)}',
          );
        }
      }

      final hasNewPaths = mdxPaths.any(
        (path) => !libraryEntries.any((entry) => entry.mdxPath == path),
      );
      if (hasNewPaths) {
        // This one-time migration gives legacy rows exact content identities.
        // Hashing is streamed from disk and never holds the MDX in memory.
        for (var index = 0; index < libraryEntries.length; index++) {
          final entry = libraryEntries[index];
          if (entry.contentFingerprint != null) continue;
          progress.value = (
            completed: 0,
            total: mdxPaths.length,
            fileName: '正在校验已有词典：${entry.title}',
          );
          try {
            _fileAccess.registerSource(
              entry.mdxPath,
              entry.mddPaths,
              sidecarResources: entry.sidecarResources,
              accessPath: entry.accessPath,
            );
            if (!await _fileAccess.restore(entry.accessPath)) continue;
            libraryEntries[index] = entry.copyWith(
              contentFingerprint:
                  await _fileAccess.fingerprintMdx(entry.mdxPath),
            );
            libraryChanged = true;
          } catch (error, stackTrace) {
            debugPrint(
              'Unable to fingerprint existing dictionary ${entry.mdxPath}: '
              '$error\n$stackTrace',
            );
          }
        }
      }

      final fingerprints = <String, DictionaryLibraryEntry>{
        for (final entry in libraryEntries)
          if (entry.contentFingerprint case final fingerprint?)
            fingerprint: entry,
      };
      for (var index = 0; index < mdxPaths.length; index++) {
        final mdxPath = mdxPaths[index];
        if (libraryEntries.any((entry) => entry.mdxPath == mdxPath)) {
          progress.value = (
            completed: index + 1,
            total: mdxPaths.length,
            fileName: _dictionaryFileName(mdxPath),
          );
          continue;
        }
        final source = target.androidSourcesByMdx[mdxPath];
        final mddPaths = target.mddPathsByMdx[mdxPath] ?? const <String>[];
        final sidecars = target.sidecarResourcesByMdx[mdxPath] ??
            const <DictionarySidecarResource>[];
        progress.value = (
          completed: index,
          total: mdxPaths.length,
          fileName: _dictionaryFileName(mdxPath),
        );
        try {
          if (source != null) {
            _fileAccess.registerSource(
              mdxPath,
              mddPaths,
              sidecarResources: sidecars,
              accessPath: accessPath,
            );
          }
          final fingerprint = await _fileAccess.fingerprintMdx(mdxPath);
          if (fingerprints.containsKey(fingerprint)) {
            duplicateCount++;
            _fileAccess.discardDuplicateSource(mdxPath);
            continue;
          }
          final title = await widget.engine.importMdx(mdxPath: mdxPath);
          final sourceVersion = source?.sourceVersion ??
              await _fileAccess.sourceVersionForMdx(mdxPath);
          final entry = DictionaryLibraryEntry(
            title: title,
            mdxPath: mdxPath,
            accessPath: accessPath,
            sourceRelativePath: source?.relativePath,
            sourceVersion: sourceVersion,
            contentFingerprint: fingerprint,
            mddPaths: mddPaths,
            sidecarResources: sidecars,
            importedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
          );
          libraryEntries.add(entry);
          fingerprints[fingerprint] = entry;
          _failedMdxPaths.remove(mdxPath);
          successfulPaths.add(mdxPath);
          addedCount++;
          libraryChanged = true;
        } catch (error, stackTrace) {
          debugPrint(
            'Dictionary import failed for $mdxPath: $error\n$stackTrace',
          );
          failedPaths.add(mdxPath);
          importFailures.add(
            '${_dictionaryFileName(mdxPath)}：${_describeImportError(error)}',
          );
        } finally {
          progress.value = (
            completed: index + 1,
            total: mdxPaths.length,
            fileName: _dictionaryFileName(mdxPath),
          );
        }
      }

      if (libraryChanged) {
        libraryEntries = List<DictionaryLibraryEntry>.of(
          await widget.library.replaceAll(libraryEntries),
        );
      }

      if (mounted) {
        for (final path in changedSourcePaths) {
          _lookupResultCache.removeDictionary(path);
          _readerPositionCache.removeDictionary(path);
        }
        setState(() {
          _libraryEntries = libraryEntries;
          _availableMdxPaths = {..._availableMdxPaths}
            ..removeAll(failedPaths)
            ..addAll(successfulPaths);
          _articlesByDictionary = {..._articlesByDictionary}
            ..removeWhere((path, _) => changedSourcePaths.contains(path));
          _retainedReaderPaths = _adoptRetainedReaderPaths(
            _retainedReaderPaths
                .where((path) => !changedSourcePaths.contains(path)),
          );
          _selectedMdxPath ??= dictionaryEntriesForScope(
            libraryEntries.where(
              (entry) =>
                  entry.isEnabled && _availableMdxPaths.contains(entry.mdxPath),
            ),
            _activeDictionaryScopeId,
          ).map((entry) => entry.mdxPath).firstOrNull;
        });
      }
      // Reader handles have already been warmed during import. Give the user
      // a quiet window to search before starting disposable full-key indexes;
      // Rust cancels this work if a foreground request arrives later.
      if (successfulPaths.isNotEmpty) {
        _scheduleIndexMigration(
          libraryEntries,
          delay: const Duration(seconds: 3),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _isImporting = false);
      }
      await progressDialog;
      progress.dispose();
    }

    if (target.copiedIntoIosHome &&
        addedCount == 0 &&
        duplicateCount == mdxPaths.length &&
        failedPaths.isEmpty) {
      try {
        removedRedundantIosCopy = await _iosDictionaryHome
            .removeRedundantCopiedImport(target.accessPath);
      } on FileSystemException catch (error) {
        debugPrint('Unable to remove redundant iOS dictionary copy: $error');
      }
    }

    if (!mounted) {
      return;
    }
    final handledCount =
        addedCount + refreshedCount + duplicateCount + unchangedCount;
    if (handledCount == 0) {
      _showMessage(
        '发现 ${mdxPaths.length} 个 MDX 文件，但都无法读取。'
        '${importFailures.isEmpty ? '' : '\n${importFailures.first}'}',
      );
      return;
    }

    final summary = <String>[
      '发现 ${mdxPaths.length} 个 MDX',
      if (target.copiedIntoIosHome && !removedRedundantIosCopy)
        '已复制到 LumaLex/Dictionaries',
      if (removedRedundantIosCopy) '重复副本已清理',
      if (addedCount > 0) '新增 $addedCount 本',
      if (refreshedCount > 0) '刷新 $refreshedCount 本',
      if (duplicateCount > 0) '跳过重复 $duplicateCount 本',
      if (unchangedCount > 0) '保持不变 $unchangedCount 本',
      if (failedPaths.isNotEmpty) '失败 ${failedPaths.length} 本',
      if (target.skippedFolderCount > 0)
        '跳过 ${target.skippedFolderCount} 个无法读取的子目录',
      if (!savedReadGrant) '未能保存重启后的访问授权',
      '快速检索索引正在后台建立',
    ];
    _showMessage(summary.join(' · '));

    final currentQuery = _queryController.text.trim();
    final selectedPath = _selectedMdxPath;
    if (changedSourcePaths.isNotEmpty &&
        currentQuery.isNotEmpty &&
        changedSourcePaths.any(successfulPaths.contains)) {
      await _lookup(
        currentQuery,
        preferredMdxPath: selectedPath,
      );
    }
  }

  String _describeImportError(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) {
      return '系统没有返回具体原因。';
    }
    return text.length <= 180 ? text : '${text.substring(0, 177)}…';
  }

  bool _sameDictionarySource(
    DictionaryLibraryEntry left,
    DictionaryLibraryEntry right,
  ) =>
      left.mdxPath == right.mdxPath &&
      left.accessPath == right.accessPath &&
      left.sourceRelativePath == right.sourceRelativePath &&
      left.sourceVersion == right.sourceVersion &&
      _sameStrings(left.mddPaths, right.mddPaths) &&
      _sameSidecars(left.sidecarResources, right.sidecarResources);

  bool _sameDictionaryEntry(
    DictionaryLibraryEntry left,
    DictionaryLibraryEntry right,
  ) =>
      left.title == right.title &&
      left.contentFingerprint == right.contentFingerprint &&
      left.importedAtMilliseconds == right.importedAtMilliseconds &&
      left.isEnabled == right.isEnabled &&
      left.groupId == right.groupId &&
      _sameDictionarySource(left, right);

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  bool _sameSidecars(
    List<DictionarySidecarResource> left,
    List<DictionarySidecarResource> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].uri != right[index].uri ||
          left[index].relativePath != right[index].relativePath) {
        return false;
      }
    }
    return true;
  }

  Future<void> _ensureIndexesInBackground(
    List<DictionaryLibraryEntry> entries,
  ) async {
    // Missing indexes are migrated sequentially so a large library cannot
    // saturate the machine. An active lookup always wins; migration schedules
    // itself again after the current lookup settles.
    final enabledEntries =
        entries.where((entry) => entry.isEnabled).toList(growable: false)
          ..sort((left, right) {
            final leftIsSelected = left.mdxPath == _selectedMdxPath;
            final rightIsSelected = right.mdxPath == _selectedMdxPath;
            if (leftIsSelected == rightIsSelected) return 0;
            return leftIsSelected ? -1 : 1;
          });
    for (final entry in enabledEntries) {
      if (!mounted) {
        return;
      }
      if (_isSearching || _isImporting) {
        _scheduleIndexMigration(entries);
        return;
      }
      if (!_availableMdxPaths.contains(entry.mdxPath)) {
        continue;
      }
      try {
        await widget.engine.ensureIndex(mdxPath: entry.mdxPath);
      } catch (error) {
        if (error.toString().toLowerCase().contains('cancelled')) {
          _scheduleIndexMigration(
            entries,
            delay: const Duration(seconds: 3),
          );
          return;
        }
        // A failed cache migration must never make a readable dictionary
        // unavailable. A later import can retry it.
      }
    }
  }

  void _scheduleIndexMigration(
    List<DictionaryLibraryEntry> entries, {
    Duration delay = const Duration(seconds: 1),
  }) {
    if (!mounted || entries.isEmpty) {
      return;
    }
    _indexMigrationDelay?.cancel();
    _indexMigrationDelay = Timer(
      delay,
      () {
        _indexMigrationDelay = null;
        unawaited(_ensureIndexesInBackground(entries));
      },
    );
  }

  Future<_DictionaryImportTarget?> _selectDictionaryTarget({
    bool useIosDictionaryHome = false,
    bool showEmptyMessage = true,
  }) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isIOS) {
      String? directoryPath;
      var copiedIntoIosHome = false;
      try {
        if (Platform.isIOS) {
          if (useIosDictionaryHome) {
            directoryPath = (await _iosDictionaryHomeReady)?.path;
          } else {
            String? initialDirectoryPath;
            try {
              initialDirectoryPath = (await _iosDictionaryHomeReady)?.path;
            } on FileSystemException {
              // A full or unavailable app container must not prevent the user
              // from authorizing an existing dictionary folder elsewhere.
            }
            final selection = await _fileAccess.pickIosDictionaryFolder(
              initialDirectoryPath: initialDirectoryPath,
            );
            directoryPath = selection?.path;
            copiedIntoIosHome = selection?.wasCopiedIntoDictionaryHome == true;
          }
        } else {
          directoryPath = await FilePicker.getDirectoryPath(
            dialogTitle: '选择词典总文件夹（将扫描所有子文件夹）',
          );
        }
      } on PlatformException catch (error) {
        debugPrint(
          'Dictionary folder picker failed: ${error.code}; '
          '${error.message}; details=${error.details}',
        );
        if (mounted) {
          _showMessage(error.message ?? '无法打开系统文件夹选择器。');
        }
        return null;
      } on FormatException catch (error) {
        debugPrint('Dictionary folder picker returned invalid data: $error');
        if (mounted) {
          _showMessage('系统返回的文件夹信息无效，请重试。');
        }
        return null;
      } on FileSystemException {
        if (mounted && showEmptyMessage) {
          _showMessage('无法建立 LumaLex 词典目录，请检查设备存储空间。');
        }
        return null;
      }
      if (directoryPath == null) {
        return null;
      }

      try {
        final scan = await scanDictionaryFolder(directoryPath);
        if (scan.mdxPaths.isEmpty) {
          if (mounted && showEmptyMessage) {
            _showMessage(
              useIosDictionaryHome
                  ? '还没有找到 MDX。请先将词典文件夹放入“${IosDictionaryHome.displayPath}”。'
                  : '所选文件夹及其子文件夹中没有 MDX 文件。',
            );
          }
          return null;
        }
        return (
          mdxPaths: scan.mdxPaths,
          accessPath: directoryPath,
          copiedIntoIosHome: copiedIntoIosHome,
          skippedFolderCount: scan.unreadableDirectoryCount,
          mddPathsByMdx: const <String, List<String>>{},
          sidecarResourcesByMdx: const <String,
              List<DictionarySidecarResource>>{},
          androidSourcesByMdx: const <String, AndroidDictionarySource>{},
        );
      } on FileSystemException {
        if (mounted) {
          _showMessage('无法读取所选文件夹。请检查访问权限后重试。');
        }
        return null;
      }
    }

    if (Platform.isAndroid) {
      try {
        final selection = await _fileAccess.pickAndroidDictionaryFolder();
        if (selection == null) {
          return null;
        }
        if (selection.dictionaries.isEmpty) {
          if (mounted) {
            _showMessage('所选文件夹及其子文件夹中没有 MDX 文件。');
          }
          return null;
        }
        final mddPathsByMdx = <String, List<String>>{
          for (final source in selection.dictionaries)
            source.mdxPath: source.mddPaths,
        };
        final sidecarResourcesByMdx = <String, List<DictionarySidecarResource>>{
          for (final source in selection.dictionaries)
            source.mdxPath: source.sidecarResources,
        };
        final androidSourcesByMdx = <String, AndroidDictionarySource>{
          for (final source in selection.dictionaries) source.mdxPath: source,
        };
        return (
          mdxPaths:
              selection.dictionaries.map((source) => source.mdxPath).toList(
                    growable: false,
                  ),
          accessPath: selection.accessPath,
          copiedIntoIosHome: false,
          skippedFolderCount: 0,
          mddPathsByMdx: mddPathsByMdx,
          sidecarResourcesByMdx: sidecarResourcesByMdx,
          androidSourcesByMdx: androidSourcesByMdx,
        );
      } on PlatformException catch (error) {
        if (mounted) {
          _showMessage(error.message ?? '无法读取所选文件夹。请检查访问权限后重试。');
        }
        return null;
      } on FormatException {
        if (mounted) {
          _showMessage('所选文件夹返回的数据无效，请重试。');
        }
        return null;
      }
    }

    final picked = await FilePicker.pickFile(
      dialogTitle: '选择 MDX 词典文件',
      type: FileType.custom,
      allowedExtensions: const ['mdx'],
    );
    final mdxPath = picked?.path;
    if (mdxPath == null) {
      return null;
    }
    return (
      mdxPaths: <String>[mdxPath],
      accessPath: mdxPath,
      copiedIntoIosHome: false,
      skippedFolderCount: 0,
      mddPathsByMdx: const <String, List<String>>{},
      sidecarResourcesByMdx: const <String, List<DictionarySidecarResource>>{},
      androidSourcesByMdx: const <String, AndroidDictionarySource>{},
    );
  }

  String _dictionaryFileName(String path) {
    final segments = File(path).uri.pathSegments;
    return segments.isEmpty ? path : segments.last;
  }

  Future<void> _loadWordRecords({int? expectedMutationGeneration}) async {
    try {
      final historyRequest = widget.wordRecords.loadHistory();
      final favoritesRequest = widget.wordRecords.loadFavorites();
      final reviewCardsRequest = widget.wordRecords.loadReviewCards();
      final textScaleRequest = widget.wordRecords.loadTextScale();
      final history = await historyRequest;
      final favorites = await favoritesRequest;
      final storedReviewCards = await reviewCardsRequest;
      final textScale = await textScaleRequest;
      final synchronizedReviewCards = synchronizeReviewCards(
        favorites,
        storedReviewCards,
        now: DateTime.now(),
      );
      if (expectedMutationGeneration != null &&
          expectedMutationGeneration != _wordRecordsMutationGeneration) {
        return;
      }
      if (mounted) {
        setState(() {
          _history = history.take(200).toList(growable: false);
          _favorites = favorites;
          _reviewCards = synchronizedReviewCards;
          _textScale = textScale;
        });
      }
      if (!_sameReviewCards(storedReviewCards, synchronizedReviewCards)) {
        unawaited(widget.wordRecords.saveReviewCards(synchronizedReviewCards));
      }
    } catch (_) {
      if (mounted) {
        _showMessage('无法读取查词历史和收藏。');
      }
    }
  }

  Future<void> _refreshWordRecords() async {
    await _wordRecordsReady;
    if (!mounted) return;
    final expectedMutationGeneration = _wordRecordsMutationGeneration;
    await _loadWordRecords(
      expectedMutationGeneration: expectedMutationGeneration,
    );
  }

  Future<void> _recordHistory(String word) async {
    final normalized = word.trim();
    if (normalized.isEmpty) {
      return;
    }
    final updated = addRecentWord(_history, normalized);
    _wordRecordsMutationGeneration++;
    if (mounted) {
      setState(() => _history = updated);
    }
    try {
      await widget.wordRecords.saveHistory(updated);
    } catch (_) {
      if (mounted) {
        _showMessage('查词成功，但无法保存历史记录。');
      }
    }
  }

  bool _isFavorite(String word) => _favorites.any(
        (favorite) => favorite.toLowerCase() == word.trim().toLowerCase(),
      );

  bool _sameReviewCards(
    List<ReviewCard> left,
    List<ReviewCard> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].toJson().toString() != right[index].toJson().toString()) {
        return false;
      }
    }
    return true;
  }

  List<ReviewCard> _addGlossToNewReviewCard(
    List<ReviewCard> cards,
    String word,
  ) {
    final selectedPath = _selectedMdxPath;
    final article = selectedPath == null
        ? null
        : _articlesByDictionary[selectedPath]?.firstOrNull;
    final gloss = article == null ? null : reviewGlossFromHtml(article.html);
    if (gloss == null) {
      return cards;
    }
    final normalized = word.trim().toLowerCase();
    return cards
        .map(
          (card) => card.word.toLowerCase() == normalized
              ? card.copyWith(gloss: gloss)
              : card,
        )
        .toList(growable: false);
  }

  Future<void> _toggleFavorite(String word) async {
    final normalized = word.trim();
    if (normalized.isEmpty) {
      return;
    }
    final updated = toggleSavedWord(_favorites, normalized);
    final wasFavorite = _isFavorite(normalized);
    final synchronizedReviewCards = synchronizeReviewCards(
      updated,
      _reviewCards,
      now: DateTime.now(),
    );
    final reviewCards = !wasFavorite
        ? _addGlossToNewReviewCard(
            synchronizedReviewCards,
            normalized,
          )
        : synchronizedReviewCards;
    _wordRecordsMutationGeneration++;
    if (mounted) {
      setState(() {
        _favorites = updated;
        _reviewCards = reviewCards;
      });
    }
    try {
      await Future.wait([
        widget.wordRecords.saveFavorites(updated),
        widget.wordRecords.saveReviewCards(reviewCards),
      ]);
    } catch (_) {
      if (mounted) {
        _showMessage('无法保存收藏。');
      }
    }
  }

  Future<void> _removeHistoryWords(Iterable<String> words) async {
    final updated = removeSavedWords(_history, words);
    _wordRecordsMutationGeneration++;
    if (mounted) {
      setState(() => _history = updated);
    }
    try {
      await widget.wordRecords.saveHistory(updated);
    } catch (_) {
      if (mounted) {
        _showMessage('无法保存历史记录的删除结果。');
      }
    }
  }

  Future<void> _removeFavoriteWords(Iterable<String> words) async {
    final updated = removeSavedWords(_favorites, words);
    final reviewCards = synchronizeReviewCards(
      updated,
      _reviewCards,
      now: DateTime.now(),
    );
    _wordRecordsMutationGeneration++;
    if (mounted) {
      setState(() {
        _favorites = updated;
        _reviewCards = reviewCards;
      });
    }
    try {
      await Future.wait([
        widget.wordRecords.saveFavorites(updated),
        widget.wordRecords.saveReviewCards(reviewCards),
      ]);
    } catch (_) {
      if (mounted) {
        _showMessage('无法保存收藏的删除结果。');
      }
    }
  }

  Future<void> _openRecordedWord(String word) async {
    Navigator.of(context).pop();
    _queryController.value = TextEditingValue(
      text: word,
      selection: TextSelection.collapsed(offset: word.length),
    );
    await _startNewLookup(word);
  }

  Future<void> _showWordRecords() async {
    var managingHistory = false;
    var managingFavorites = false;
    final selectedHistory = <String>{};
    final selectedFavorites = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => DefaultTabController(
          length: 2,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.history), text: '历史'),
                      Tab(icon: Icon(Icons.star_outline), text: '收藏'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildWordRecordsTab(
                          words: _history,
                          emptyMessage: '还没有查词历史。',
                          managing: managingHistory,
                          selectedWords: selectedHistory,
                          onToggleManaging: () {
                            setSheetState(() {
                              managingHistory = !managingHistory;
                              selectedHistory.clear();
                            });
                          },
                          onToggleSelected: (word) {
                            setSheetState(() {
                              if (!selectedHistory.add(word)) {
                                selectedHistory.remove(word);
                              }
                            });
                          },
                          onToggleSelectAll: () {
                            setSheetState(() {
                              if (selectedHistory.length == _history.length) {
                                selectedHistory.clear();
                              } else {
                                selectedHistory
                                  ..clear()
                                  ..addAll(_history);
                              }
                            });
                          },
                          onDeleteSelected: () async {
                            await _removeHistoryWords(selectedHistory);
                            if (context.mounted) {
                              setSheetState(() {
                                selectedHistory.clear();
                                if (_history.isEmpty) managingHistory = false;
                              });
                            }
                          },
                          onClearAll: () async {
                            if (!await _confirmClearWordList(
                              context,
                              title: '清空查词历史？',
                              message: '全部历史记录将被删除，此操作无法撤销。',
                            )) {
                              return;
                            }
                            await _removeHistoryWords(_history);
                            if (context.mounted) {
                              setSheetState(() {
                                selectedHistory.clear();
                                managingHistory = false;
                              });
                            }
                          },
                          trailingBuilder: (word) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: _isFavorite(word) ? '取消收藏' : '收藏',
                                icon: Icon(
                                  _isFavorite(word)
                                      ? Icons.star
                                      : Icons.star_outline,
                                ),
                                onPressed: () async {
                                  await _toggleFavorite(word);
                                  if (context.mounted) setSheetState(() {});
                                },
                              ),
                              IconButton(
                                tooltip: '删除这条历史',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await _removeHistoryWords([word]);
                                  if (context.mounted) setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                        _buildWordRecordsTab(
                          words: _favorites,
                          emptyMessage: '还没有收藏单词。',
                          managing: managingFavorites,
                          selectedWords: selectedFavorites,
                          onToggleManaging: () {
                            setSheetState(() {
                              managingFavorites = !managingFavorites;
                              selectedFavorites.clear();
                            });
                          },
                          onToggleSelected: (word) {
                            setSheetState(() {
                              if (!selectedFavorites.add(word)) {
                                selectedFavorites.remove(word);
                              }
                            });
                          },
                          onToggleSelectAll: () {
                            setSheetState(() {
                              if (selectedFavorites.length ==
                                  _favorites.length) {
                                selectedFavorites.clear();
                              } else {
                                selectedFavorites
                                  ..clear()
                                  ..addAll(_favorites);
                              }
                            });
                          },
                          onDeleteSelected: () async {
                            await _removeFavoriteWords(selectedFavorites);
                            if (context.mounted) {
                              setSheetState(() {
                                selectedFavorites.clear();
                                if (_favorites.isEmpty) {
                                  managingFavorites = false;
                                }
                              });
                            }
                          },
                          onClearAll: () async {
                            if (!await _confirmClearWordList(
                              context,
                              title: '清空全部收藏？',
                              message: '全部收藏单词将被删除，此操作无法撤销。',
                            )) {
                              return;
                            }
                            await _removeFavoriteWords(_favorites);
                            if (context.mounted) {
                              setSheetState(() {
                                selectedFavorites.clear();
                                managingFavorites = false;
                              });
                            }
                          },
                          trailingBuilder: (word) => IconButton(
                            tooltip: '从收藏中删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await _removeFavoriteWords([word]);
                              if (context.mounted) setSheetState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordRecordsTab({
    required List<String> words,
    required String emptyMessage,
    required bool managing,
    required Set<String> selectedWords,
    required VoidCallback onToggleManaging,
    required ValueChanged<String> onToggleSelected,
    required VoidCallback onToggleSelectAll,
    required Future<void> Function() onDeleteSelected,
    required Future<void> Function() onClearAll,
    required Widget Function(String word) trailingBuilder,
  }) {
    final allSelected =
        words.isNotEmpty && selectedWords.length == words.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(managing
                  ? '已选 ${selectedWords.length} 项'
                  : '共 ${words.length} 项'),
              const Spacer(),
              if (managing) ...[
                TextButton(
                  onPressed: words.isEmpty ? null : onToggleSelectAll,
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
                TextButton.icon(
                  onPressed: selectedWords.isEmpty ? null : onDeleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                TextButton(
                    onPressed: onToggleManaging, child: const Text('完成')),
              ] else ...[
                TextButton(
                  onPressed: words.isEmpty ? null : onToggleManaging,
                  child: const Text('管理'),
                ),
                TextButton(
                  onPressed: words.isEmpty ? null : onClearAll,
                  child: const Text('清空'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: words.isEmpty
              ? Center(child: Text(emptyMessage))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: words.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final word = words[index];
                    final selected = selectedWords.contains(word);
                    return ListTile(
                      leading: managing
                          ? Checkbox(
                              value: selected,
                              onChanged: (_) => onToggleSelected(word),
                            )
                          : const Icon(Icons.search),
                      title: Text(word),
                      selected: managing && selected,
                      trailing: managing ? null : trailingBuilder(word),
                      onTap: managing
                          ? () => onToggleSelected(word)
                          : () => _openRecordedWord(word),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<bool> _confirmClearWordList(
    BuildContext context, {
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清空'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _loadLibrary() async {
    try {
      if (_supportsDictionaryGroups) {
        _dictionaryGroupSnapshot = await widget.dictionaryGroups.load();
      }
      var entries = await widget.library.load();
      entries = await _refreshAndroidLibrarySources(entries);
      entries = await _refreshIosLibrarySources(entries);
      if (_supportsDictionaryGroups) {
        final knownGroupIds =
            _dictionaryGroupSnapshot.groups.map((group) => group.id).toSet();
        var repairedUnknownGroup = false;
        final repairedEntries = entries.map((entry) {
          if (entry.groupId == null || knownGroupIds.contains(entry.groupId)) {
            return entry;
          }
          repairedUnknownGroup = true;
          return entry.copyWith(clearGroupId: true);
        }).toList(growable: false);
        if (repairedUnknownGroup) {
          entries = await widget.library.replaceAll(repairedEntries);
        }
      }
      if (mounted) {
        setState(() => _libraryEntries = entries);
      }
      final scopedEnabledEntries = dictionaryEntriesForScope(
        entries.where((entry) => entry.isEnabled),
        _activeDictionaryScopeId,
      );
      final enabledEntries = <DictionaryLibraryEntry>[
        ...scopedEnabledEntries,
        ...entries.where(
          (entry) => entry.isEnabled && !scopedEnabledEntries.contains(entry),
        ),
      ];
      final available = <String>{};
      // Only the first usable dictionary is on the startup critical path.
      // Opening a large library sequentially used to keep the whole lookup UI
      // blocked even though the user needs just one dictionary to start.
      for (final entry in enabledEntries) {
        if (!mounted) {
          return;
        }
        if (await _prepareDictionary(entry)) {
          available.add(entry.mdxPath);
          // The normal app becomes interactive after restoring its first
          // dictionary, then warms the rest in the background. A PROCESS_TEXT
          // window is already committed to one selected word: rendering that
          // first dictionary as 1/1 and later rebuilding it as 1/N produces a
          // conspicuous second page load. Restore its complete enabled set
          // before the one aggregate lookup instead.
          if (!widget.processTextMode) break;
        }
      }
      if (mounted) {
        setState(() {
          _availableMdxPaths = available;
          _selectedMdxPath = scopedEnabledEntries
              .where((entry) => available.contains(entry.mdxPath))
              .map((entry) => entry.mdxPath)
              .firstOrNull;
          _isLibraryLoading = false;
        });
      }
      if (enabledEntries.isNotEmpty && available.isEmpty && mounted) {
        _showMessage('已保留词典库，但原文件授权已失效。请重新导入其中一本词典以恢复访问。');
      }
      if (available.isNotEmpty) {
        _scheduleIndexMigration(entries);
        _scheduleDictionaryWarmup(entries);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('无法读取本地词典库。');
      }
    } finally {
      if (mounted) {
        setState(() => _isLibraryLoading = false);
      }
    }
  }

  Future<List<DictionaryLibraryEntry>> _refreshIosLibrarySources(
    List<DictionaryLibraryEntry> entries, {
    Set<String>? changedPaths,
    Set<String>? unavailablePaths,
  }) async {
    if (!Platform.isIOS || entries.isEmpty) return entries;
    final refreshed = List<DictionaryLibraryEntry>.of(entries);
    final restoredAccessPaths = <String, Future<bool>>{};
    var changed = false;
    for (var index = 0; index < refreshed.length; index++) {
      final entry = refreshed[index];
      final restored = await restoredAccessPaths.putIfAbsent(
        entry.accessPath,
        () async {
          try {
            return await _fileAccess.restore(entry.accessPath);
          } catch (_) {
            return false;
          }
        },
      );
      if (!restored) {
        unavailablePaths?.add(entry.mdxPath);
        continue;
      }
      try {
        final currentVersion =
            await _fileAccess.sourceVersionForMdx(entry.mdxPath);
        if (currentVersion == null || currentVersion == entry.sourceVersion) {
          continue;
        }
        _fileAccess.invalidateMdxSource(entry.mdxPath);
        refreshed[index] = entry.copyWith(
          sourceVersion: currentVersion,
          contentFingerprint: entry.sourceVersion == null
              ? entry.contentFingerprint
              : await _fileAccess.fingerprintMdx(entry.mdxPath),
        );
        changedPaths?.add(entry.mdxPath);
        changed = true;
      } on FileSystemException {
        // Keep the row. The ordinary preparation pass below will mark the
        // source unavailable and lets the user restore or remove it.
        if (!await File(entry.mdxPath).exists()) {
          unavailablePaths?.add(entry.mdxPath);
        }
      }
    }
    if (!changed) return entries;
    return widget.library.replaceAll(refreshed);
  }

  Future<void> _refreshIosSourcesAfterForeground() async {
    if (!Platform.isIOS ||
        _isRefreshingIosSources ||
        _isLibraryLoading ||
        _isImporting) {
      return;
    }
    _isRefreshingIosSources = true;
    try {
      final changedPaths = <String>{};
      final unavailablePaths = <String>{};
      final refreshed = await _refreshIosLibrarySources(
        _libraryEntries,
        changedPaths: changedPaths,
        unavailablePaths: unavailablePaths,
      );
      if (!mounted) return;
      final affectedPaths = {...changedPaths, ...unavailablePaths};
      if (affectedPaths.isNotEmpty) {
        for (final path in affectedPaths) {
          _lookupResultCache.removeDictionary(path);
          _readerPositionCache.removeDictionary(path);
        }
        setState(() {
          _libraryEntries = refreshed;
          _availableMdxPaths = {..._availableMdxPaths}
            ..removeAll(unavailablePaths);
          _failedMdxPaths.addAll(unavailablePaths);
          _articlesByDictionary = {..._articlesByDictionary}
            ..removeWhere((path, _) => affectedPaths.contains(path));
          _retainedReaderPaths = _adoptRetainedReaderPaths(
            _retainedReaderPaths.where(
              (path) => !affectedPaths.contains(path),
            ),
          );
        });
      }

      await _scanIosDictionaryHome();
      if (!mounted || changedPaths.isEmpty) return;
      final currentQuery = _queryController.text.trim();
      if (currentQuery.isNotEmpty && _availableEntries.isNotEmpty) {
        await _lookup(
          currentQuery,
          preferredMdxPath: _selectedMdxPath,
        );
      }
    } finally {
      _isRefreshingIosSources = false;
    }
  }

  Future<List<DictionaryLibraryEntry>> _refreshAndroidLibrarySources(
    List<DictionaryLibraryEntry> entries,
  ) async {
    if (!Platform.isAndroid || entries.isEmpty) return entries;
    final refreshed = List<DictionaryLibraryEntry>.of(entries);
    var changed = false;
    final accessPaths = entries
        .map((entry) => entry.accessPath)
        .where((path) => path.startsWith('content://'))
        .toSet();
    for (final accessPath in accessPaths) {
      try {
        final sources = await _fileAccess.scanAndroidDictionaryFolder(
          accessPath,
          refresh: true,
        );
        final usedPaths = <String>{};
        for (var index = 0; index < refreshed.length; index++) {
          final entry = refreshed[index];
          if (entry.accessPath != accessPath) continue;
          AndroidDictionarySource? source = sources
              .where(
                (candidate) =>
                    candidate.mdxPath == entry.mdxPath &&
                    !usedPaths.contains(candidate.mdxPath),
              )
              .firstOrNull;
          source ??= sources
              .where(
                (candidate) =>
                    entry.sourceRelativePath != null &&
                    candidate.relativePath == entry.sourceRelativePath &&
                    !usedPaths.contains(candidate.mdxPath),
              )
              .firstOrNull;
          if (source == null && entry.sourceRelativePath == null) {
            final fileName = _sourceFileName(entry.mdxPath);
            final matches = sources
                .where(
                  (candidate) =>
                      _sourceFileName(candidate.relativePath) == fileName &&
                      !usedPaths.contains(candidate.mdxPath),
                )
                .toList(growable: false);
            if (matches.length == 1) source = matches.single;
          }
          if (source == null) {
            _fileAccess.discardUnavailableSource(entry.mdxPath);
            continue;
          }
          usedPaths.add(source.mdxPath);
          final sourceVersionChanged = entry.sourceVersion != null &&
              source.sourceVersion != null &&
              entry.sourceVersion != source.sourceVersion;
          final next = entry.copyWith(
            mdxPath: source.mdxPath,
            accessPath: accessPath,
            sourceRelativePath: source.relativePath,
            sourceVersion: source.sourceVersion,
            clearContentFingerprint: sourceVersionChanged,
            mddPaths: source.mddPaths,
            sidecarResources: source.sidecarResources,
          );
          if (!_sameDictionaryEntry(entry, next)) {
            refreshed[index] = next;
            changed = true;
            if (entry.mdxPath != next.mdxPath) {
              _fileAccess.unregisterSource(entry.mdxPath);
            } else if (sourceVersionChanged) {
              _fileAccess.invalidateMdxSource(entry.mdxPath);
            }
          }
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Unable to refresh Android dictionary folder $accessPath: '
          '$error\n$stackTrace',
        );
      }
    }
    if (!changed) return entries;
    return widget.library.replaceAll(refreshed);
  }

  String _sourceFileName(String value) {
    final slashName = value.split('/').last;
    final decoded = Uri.decodeComponent(slashName);
    final nestedSlash = decoded.lastIndexOf('/');
    return (nestedSlash < 0 ? decoded : decoded.substring(nestedSlash + 1))
        .toLowerCase();
  }

  bool get _hasPendingEnabledDictionary => _libraryEntries.any(
        (entry) =>
            entry.isEnabled &&
            _entryMatchesActiveDictionaryScope(entry) &&
            !_availableMdxPaths.contains(entry.mdxPath) &&
            !_failedMdxPaths.contains(entry.mdxPath),
      );

  Future<void> _prepareEnabledDictionariesForAggregateLookup() async {
    final pending = _libraryEntries
        .where(
          (entry) =>
              entry.isEnabled &&
              _entryMatchesActiveDictionaryScope(entry) &&
              !_availableMdxPaths.contains(entry.mdxPath) &&
              !_failedMdxPaths.contains(entry.mdxPath),
        )
        .toList(growable: false);
    if (pending.isEmpty) return;

    final restored = <String>{};
    // Match the existing warmup policy: opening large MDX sources in series
    // avoids a short burst of competing file-provider reads on mobile flash.
    for (final entry in pending) {
      if (!mounted) return;
      if (await _prepareDictionary(entry)) {
        restored.add(entry.mdxPath);
      }
    }
    if (!mounted || restored.isEmpty) return;
    setState(() {
      _availableMdxPaths = {..._availableMdxPaths, ...restored};
      _selectedMdxPath ??= restored.firstOrNull;
    });
  }

  Future<bool> _prepareDictionary(DictionaryLibraryEntry entry) {
    final existing = _dictionaryPreparations[entry.mdxPath];
    if (existing != null) return existing;
    final preparation = _prepareDictionaryOnce(entry);
    _dictionaryPreparations[entry.mdxPath] = preparation;
    unawaited(
      preparation.then<void>((_) {
        if (identical(_dictionaryPreparations[entry.mdxPath], preparation)) {
          _dictionaryPreparations.remove(entry.mdxPath);
        }
      }),
    );
    return preparation;
  }

  Future<bool> _prepareDictionaryOnce(DictionaryLibraryEntry entry) async {
    try {
      _fileAccess.registerSource(
        entry.mdxPath,
        entry.mddPaths,
        sidecarResources: entry.sidecarResources,
        accessPath: entry.accessPath,
      );
      if (!await _fileAccess.restore(entry.accessPath)) {
        throw StateError(
            'No reusable file-access grant exists for this dictionary.');
      }
      await widget.engine.importMdx(mdxPath: entry.mdxPath);
      _failedMdxPaths.remove(entry.mdxPath);
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Dictionary source preparation failed for ${entry.mdxPath}: '
        '$error\n$stackTrace',
      );
      _failedMdxPaths.add(entry.mdxPath);
      return false;
    }
  }

  void _scheduleDictionaryWarmup(
    List<DictionaryLibraryEntry> entries, {
    Duration delay = const Duration(seconds: 3),
  }) {
    _dictionaryWarmupDelay?.cancel();
    final generation = ++_dictionaryWarmupGeneration;
    final hasPendingDictionary = entries.any(
      (entry) =>
          entry.isEnabled &&
          !_availableMdxPaths.contains(entry.mdxPath) &&
          !_failedMdxPaths.contains(entry.mdxPath),
    );
    if (!mounted || !hasPendingDictionary) {
      _dictionaryWarmupDelay = null;
      return;
    }
    _dictionaryWarmupDelay = Timer(delay, () {
      _dictionaryWarmupDelay = null;
      unawaited(_warmRemainingDictionaries(entries, generation));
    });
  }

  Future<void> _warmRemainingDictionaries(
    List<DictionaryLibraryEntry> entries,
    int generation,
  ) async {
    for (final entry in entries) {
      if (!mounted || generation != _dictionaryWarmupGeneration) {
        return;
      }
      if (!entry.isEnabled ||
          _availableMdxPaths.contains(entry.mdxPath) ||
          _failedMdxPaths.contains(entry.mdxPath)) {
        continue;
      }
      if (_isSearching || _isImporting) {
        _scheduleDictionaryWarmup(
          entries,
          delay: const Duration(seconds: 4),
        );
        return;
      }

      final prepared = await _prepareDictionary(entry);
      if (!mounted || generation != _dictionaryWarmupGeneration) {
        return;
      }
      if (!prepared) {
        continue;
      }
      setState(() {
        _availableMdxPaths = {..._availableMdxPaths, entry.mdxPath};
      });

      // If a word is already open, quietly fill in the newly warmed
      // dictionary without restarting the visible lookup or moving selection.
      final query = _queryController.text.trim();
      final request = _lookupRequest;
      if (query.isEmpty) {
        continue;
      }
      try {
        final articles = await _resolveArticles(entry, query);
        if (!mounted ||
            generation != _dictionaryWarmupGeneration ||
            request != _lookupRequest ||
            query != _queryController.text.trim()) {
          return;
        }
        setState(() {
          _articlesByDictionary = {
            ..._articlesByDictionary,
            entry.mdxPath: articles,
          };
        });
        final selectedPath = _selectedMdxPath;
        if (selectedPath != null) {
          _preloadNextDictionaryReader(selectedPath);
        }
      } catch (_) {
        // The dictionary remains available; an individual lookup miss or
        // decode failure must not undo a successfully restored source.
      }
    }
    if (mounted && generation == _dictionaryWarmupGeneration) {
      _scheduleIndexMigration(entries);
    }
  }

  Future<void> _selectDictionary(DictionaryLibraryEntry entry) async {
    if (!_availableMdxPaths.contains(entry.mdxPath)) {
      setState(() => _isImporting = true);
      final prepared = await _prepareDictionary(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _isImporting = false;
        if (prepared) {
          _availableMdxPaths = {..._availableMdxPaths, entry.mdxPath};
        }
      });
      if (!prepared) {
        _showMessage('无法打开「${entry.title}」。文件可能已移动，或需要重新导入以授予访问权限。');
        return;
      }
    }

    _rememberCurrentReaderPosition();
    setState(() {
      final previous = _selectedMdxPath;
      _selectedMdxPath = entry.mdxPath;
      _retainedReaderPaths = _adoptRetainedReaderPaths(
        _retainReaderPath(
          _retainReaderPath(_retainedReaderPaths, previous),
          entry.mdxPath,
        ),
      );
      _articleAnchor = null;
      _articleScrollOffset = null;
    });
    if (_readerPlatformPolicy.aggregateDictionaryResults) {
      unawaited(_aggregateArticleController.showDictionary(entry.mdxPath));
    }
    final query = _queryController.text.trim();
    if (query.isNotEmpty && !_articlesByDictionary.containsKey(entry.mdxPath)) {
      await _lookup(query, preferredMdxPath: entry.mdxPath);
    }
  }

  Future<void> _remove(DictionaryLibraryEntry entry) async {
    _rememberCurrentReaderPosition();
    final entries = await widget.library.remove(entry.mdxPath);
    if (!mounted) {
      return;
    }
    final wasSelected = _selectedMdxPath == entry.mdxPath;
    setState(() {
      _libraryEntries = entries;
      _availableMdxPaths = {..._availableMdxPaths}..remove(entry.mdxPath);
      _failedMdxPaths.remove(entry.mdxPath);
      _articlesByDictionary = {..._articlesByDictionary}..remove(entry.mdxPath);
      if (wasSelected) {
        _selectedMdxPath = dictionaryEntriesForScope(
          entries.where(
            (candidate) =>
                candidate.isEnabled &&
                _availableMdxPaths.contains(candidate.mdxPath),
          ),
          _activeDictionaryScopeId,
        ).map((candidate) => candidate.mdxPath).firstOrNull;
        _articleAnchor = null;
        _articleScrollOffset = null;
      }
      var retained = _retainedReaderPaths
          .where((path) => path != entry.mdxPath)
          .toList(growable: false);
      if (_selectedMdxPath case final selectedPath?) {
        retained = _retainReaderPath(retained, selectedPath);
      }
      _retainedReaderPaths = _adoptRetainedReaderPaths(retained);
    });
    _readerPositionCache.removeDictionary(entry.mdxPath);
    if (_availableMdxPaths.isEmpty) {
      widget.engine.clearActiveDictionary();
    }
    try {
      _fileAccess.unregisterSource(entry.mdxPath);
      final folderIsStillUsed = entries.any(
        (candidate) => candidate.accessPath == entry.accessPath,
      );
      if (!folderIsStillUsed) {
        await _fileAccess.revoke(entry.accessPath);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('已移除词典库记录；撤销本机文件授权时出现问题。');
      }
    }
  }

  Future<bool> _renameDictionary(
    BuildContext dialogHostContext,
    DictionaryLibraryEntry entry,
  ) async {
    final submitted = await showDialog<String>(
      context: dialogHostContext,
      builder: (_) => _RenameDictionaryDialog(
        initialName: entry.title,
      ),
    );
    final title = submitted?.trim();
    if (title == null || title.isEmpty || title == entry.title) return false;
    try {
      final entries = await widget.library.upsert(entry.copyWith(title: title));
      if (!mounted) return false;
      setState(() => _libraryEntries = entries);
      _showMessage('词典显示名称已修改为“$title”。');
      return true;
    } catch (_) {
      if (mounted) _showMessage('无法保存词典显示名称。');
      return false;
    }
  }

  String _dictionaryScopeName(String scopeId) {
    if (scopeId == DictionaryGroupScope.all) return '全部词典';
    if (scopeId == DictionaryGroupScope.ungrouped) return '未分组';
    return _dictionaryGroupSnapshot.groups
            .where((group) => group.id == scopeId)
            .map((group) => group.name)
            .firstOrNull ??
        '全部词典';
  }

  String? _dictionaryGroupNameError(
    String rawName, {
    String? excludingGroupId,
  }) {
    final name = rawName.trim();
    if (name.isEmpty) return '分组名称不能为空';
    if (name.length > 30) return '分组名称不能超过 30 个字符';
    final normalized = name.toLowerCase();
    if (normalized == '全部词典' || normalized == '未分组') {
      return '这是系统保留名称';
    }
    final duplicate = _dictionaryGroupSnapshot.groups.any(
      (group) =>
          group.id != excludingGroupId &&
          group.name.trim().toLowerCase() == normalized,
    );
    return duplicate ? '已经存在同名分组' : null;
  }

  String _newDictionaryGroupId() {
    final existing =
        _dictionaryGroupSnapshot.groups.map((group) => group.id).toSet();
    final seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var suffix = 0;
    var candidate = 'group-$seed';
    while (existing.contains(candidate)) {
      suffix++;
      candidate = 'group-$seed-$suffix';
    }
    return candidate;
  }

  Future<void> _showCreateDictionaryGroup() async {
    if (!_supportsDictionaryGroups) return;
    final nameController = TextEditingController();
    var step = 1;
    String? errorText;
    var selectedColorIndex = _dictionaryGroupSnapshot.groups.length %
        DictionaryGroup.colorChoiceCount;
    final selectedPaths = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedCount = selectedPaths.length;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SafeArea(
              top: false,
              child: FractionallySizedBox(
                heightFactor: 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              step == 1 ? '新建分组' : '选择要移入的词典',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text('$step / 2'),
                        ],
                      ),
                    ),
                    if (step == 1)
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                          children: [
                            TextField(
                              controller: nameController,
                              autofocus: true,
                              maxLength: 30,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: '分组名称',
                                hintText: '例如：英语、汉英、日语',
                                errorText: errorText,
                                helperText: '只用于整理词典，不会修改词典文件。',
                              ),
                              onSubmitted: (_) {
                                final error = _dictionaryGroupNameError(
                                  nameController.text,
                                );
                                setSheetState(() {
                                  errorText = error;
                                  if (error == null) step = 2;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '文件夹颜色',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var colorIndex = 0;
                                    colorIndex <
                                        DictionaryGroup.colorChoiceCount;
                                    colorIndex++)
                                  ChoiceChip(
                                    selected: selectedColorIndex == colorIndex,
                                    avatar: Icon(
                                      Icons.folder_rounded,
                                      size: 18,
                                      color: _dictionaryGroupColors[colorIndex],
                                    ),
                                    label: Text(
                                      _dictionaryGroupColorNames[colorIndex],
                                    ),
                                    onSelected: (_) => setSheetState(
                                      () => selectedColorIndex = colorIndex,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: _libraryEntries.isEmpty
                            ? const Center(child: Text('当前没有可加入分组的词典。'))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                itemCount: _libraryEntries.length,
                                itemBuilder: (context, index) {
                                  final entry = _libraryEntries[index];
                                  final checked =
                                      selectedPaths.contains(entry.mdxPath);
                                  final currentGroup = entry.groupId == null
                                      ? '未分组'
                                      : _dictionaryScopeName(entry.groupId!);
                                  return CheckboxListTile(
                                    value: checked,
                                    title: Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text('当前：$currentGroup'),
                                    onChanged: (selected) {
                                      setSheetState(() {
                                        if (selected ?? false) {
                                          selectedPaths.add(entry.mdxPath);
                                        } else {
                                          selectedPaths.remove(entry.mdxPath);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              if (step == 1) {
                                Navigator.of(sheetContext).pop();
                              } else {
                                setSheetState(() => step = 1);
                              }
                            },
                            child: Text(step == 1 ? '取消' : '上一步'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              if (step == 1) {
                                final error = _dictionaryGroupNameError(
                                  nameController.text,
                                );
                                setSheetState(() {
                                  errorText = error;
                                  if (error == null) step = 2;
                                });
                                return;
                              }
                              final created = await _createDictionaryGroup(
                                nameController.text.trim(),
                                selectedPaths,
                                colorIndex: selectedColorIndex,
                              );
                              if (created && sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                            child: Text(
                              step == 1
                                  ? '下一步'
                                  : selectedCount == 0
                                      ? '创建空分组'
                                      : '创建并移动 $selectedCount 本',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    nameController.dispose();
  }

  Future<bool> _createDictionaryGroup(
    String name,
    Set<String> selectedPaths, {
    required int colorIndex,
  }) async {
    if (_dictionaryGroupNameError(name) != null) return false;
    final previousSnapshot = _dictionaryGroupSnapshot;
    final previousEntries = List<DictionaryLibraryEntry>.of(_libraryEntries);
    final nextOrder = previousSnapshot.groups.isEmpty
        ? 0
        : previousSnapshot.groups
                .map((group) => group.sortOrder)
                .reduce((left, right) => left > right ? left : right) +
            1;
    final group = DictionaryGroup(
      id: _newDictionaryGroupId(),
      name: name.trim(),
      sortOrder: nextOrder,
      colorIndex: colorIndex,
    );
    final nextSnapshot = previousSnapshot.copyWith(
      groups: [...previousSnapshot.groups, group],
    );
    final nextEntries = previousEntries
        .map(
          (entry) => selectedPaths.contains(entry.mdxPath)
              ? entry.copyWith(groupId: group.id)
              : entry,
        )
        .toList(growable: false);
    try {
      await widget.dictionaryGroups.save(nextSnapshot);
      try {
        await widget.library.replaceAll(nextEntries);
      } catch (_) {
        await widget.dictionaryGroups.save(previousSnapshot);
        rethrow;
      }
      if (!mounted) return true;
      setState(() {
        _dictionaryGroupSnapshot = nextSnapshot;
        _libraryEntries = nextEntries;
      });
      await _reconcileLookupAfterGroupingChange();
      if (mounted) {
        _showMessage(
          selectedPaths.isEmpty
              ? '已创建分组“${group.name}”。'
              : '已创建分组“${group.name}”，并移入 ${selectedPaths.length} 本词典。',
        );
      }
      return true;
    } catch (_) {
      if (mounted) _showMessage('无法保存新分组。');
      return false;
    }
  }

  Future<void> _renameDictionaryGroup(DictionaryGroup group) async {
    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => _DictionaryGroupNameDialog(
        title: '重命名分组',
        initialName: group.name,
        validator: (value) => _dictionaryGroupNameError(
          value,
          excludingGroupId: group.id,
        ),
      ),
    );
    final name = submitted?.trim();
    if (name == null || name == group.name) return;
    final next = _dictionaryGroupSnapshot.copyWith(
      groups: _dictionaryGroupSnapshot.groups
          .map((candidate) => candidate.id == group.id
              ? candidate.copyWith(name: name)
              : candidate)
          .toList(growable: false),
    );
    try {
      await widget.dictionaryGroups.save(next);
      if (!mounted) return;
      setState(() => _dictionaryGroupSnapshot = next);
      _showMessage('分组已重命名为“$name”。');
    } catch (_) {
      if (mounted) _showMessage('无法保存分组名称。');
    }
  }

  Color _dictionaryGroupColor(DictionaryGroup group) =>
      _dictionaryGroupColors[group.colorIndex.clamp(
        0,
        DictionaryGroup.colorChoiceCount - 1,
      )];

  Future<void> _changeDictionaryGroupColor(DictionaryGroup group) async {
    final selectedColorIndex = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('“${group.name}”的文件夹颜色'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0;
                index < DictionaryGroup.colorChoiceCount;
                index++)
              ChoiceChip(
                selected: group.colorIndex == index,
                avatar: Icon(
                  Icons.folder_rounded,
                  size: 18,
                  color: _dictionaryGroupColors[index],
                ),
                label: Text(_dictionaryGroupColorNames[index]),
                onSelected: (_) => Navigator.of(dialogContext).pop(index),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selectedColorIndex == null || selectedColorIndex == group.colorIndex) {
      return;
    }
    final next = _dictionaryGroupSnapshot.copyWith(
      groups: _dictionaryGroupSnapshot.groups
          .map(
            (candidate) => candidate.id == group.id
                ? candidate.copyWith(colorIndex: selectedColorIndex)
                : candidate,
          )
          .toList(growable: false),
    );
    try {
      await widget.dictionaryGroups.save(next);
      if (!mounted) return;
      setState(() => _dictionaryGroupSnapshot = next);
    } catch (_) {
      if (mounted) _showMessage('无法保存分组颜色。');
    }
  }

  Future<void> _deleteDictionaryGroup(DictionaryGroup group) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('删除“${group.name}”？'),
            content: const Text('分组中的词典会移到“未分组”，词典文件和查词记录都不会删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除分组'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final previousEntries = List<DictionaryLibraryEntry>.of(_libraryEntries);
    final previousSnapshot = _dictionaryGroupSnapshot;
    final nextEntries = previousEntries
        .map((entry) => entry.groupId == group.id
            ? entry.copyWith(clearGroupId: true)
            : entry)
        .toList(growable: false);
    final nextSnapshot = DictionaryGroupSnapshot(
      groups: previousSnapshot.groups
          .where((candidate) => candidate.id != group.id)
          .toList(growable: false),
      activeScopeId: previousSnapshot.activeScopeId == group.id
          ? DictionaryGroupScope.all
          : previousSnapshot.activeScopeId,
    );
    try {
      await widget.library.replaceAll(nextEntries);
      try {
        await widget.dictionaryGroups.save(nextSnapshot);
      } catch (_) {
        await widget.library.replaceAll(previousEntries);
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _libraryEntries = nextEntries;
        _dictionaryGroupSnapshot = nextSnapshot;
      });
      await _reconcileLookupAfterGroupingChange();
      if (mounted) _showMessage('分组已删除，原有词典已移到“未分组”。');
    } catch (_) {
      if (mounted) _showMessage('无法删除分组。');
    }
  }

  Future<void> _showMoveDictionaryToGroup(
    DictionaryLibraryEntry entry,
  ) async {
    final targetGroupId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
              child: Text(
                '移动“${entry.title}”',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未分组'),
              trailing: entry.groupId == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(sheetContext)
                  .pop(DictionaryGroupScope.ungrouped),
            ),
            for (final group in _dictionaryGroupSnapshot.groups)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(group.name),
                trailing: entry.groupId == group.id
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(group.id),
              ),
          ],
        ),
      ),
    );
    if (targetGroupId == null) return;
    final nextEntry = targetGroupId == DictionaryGroupScope.ungrouped
        ? entry.copyWith(clearGroupId: true)
        : entry.copyWith(groupId: targetGroupId);
    if (nextEntry.groupId == entry.groupId) return;
    try {
      final entries = await widget.library.upsert(nextEntry);
      if (!mounted) return;
      setState(() => _libraryEntries = entries);
      await _reconcileLookupAfterGroupingChange();
      if (mounted) {
        _showMessage(
            '“${entry.title}”已移到${_dictionaryScopeName(targetGroupId)}。');
      }
    } catch (_) {
      if (mounted) _showMessage('无法移动词典。');
    }
  }

  Future<void> _reconcileLookupAfterGroupingChange() async {
    if (_activeDictionaryScopeId == DictionaryGroupScope.all) return;
    final entries = _availableEntries;
    final selectedStillVisible =
        entries.any((entry) => entry.mdxPath == _selectedMdxPath);
    final nextSelected = selectedStillVisible
        ? _selectedMdxPath
        : entries
                .where((entry) =>
                    _articlesByDictionary[entry.mdxPath]?.isNotEmpty ?? false)
                .map((entry) => entry.mdxPath)
                .firstOrNull ??
            entries.map((entry) => entry.mdxPath).firstOrNull;
    if (mounted) {
      setState(() {
        _selectedMdxPath = nextSelected;
        if (nextSelected == null) _articlesByDictionary = const {};
      });
    }
    final query = _queryController.text.trim();
    if (query.isNotEmpty && entries.isNotEmpty) {
      await _lookup(query, preferredMdxPath: nextSelected);
    }
  }

  Future<void> _selectDictionaryScope(String scopeId) async {
    if (!_supportsDictionaryGroups || scopeId == _activeDictionaryScopeId) {
      return;
    }
    final valid = DictionaryGroupScope.isSystem(scopeId) ||
        _dictionaryGroupSnapshot.groups.any((group) => group.id == scopeId);
    if (!valid) return;
    final nextSnapshot = _dictionaryGroupSnapshot.copyWith(
      activeScopeId: scopeId,
    );
    try {
      await widget.dictionaryGroups.save(nextSnapshot);
    } catch (_) {
      if (mounted) _showMessage('无法保存当前查词分组。');
      return;
    }
    if (!mounted) return;
    _rememberCurrentReaderPosition();
    setState(() {
      _dictionaryGroupSnapshot = nextSnapshot;
      _suggestions = const [];
      _selectedSuggestionIndex = -1;
    });

    var entries = _availableEntries;
    if (entries.isEmpty) {
      final firstCandidate = dictionaryEntriesForScope(
        _libraryEntries.where((entry) => entry.isEnabled),
        scopeId,
      ).firstOrNull;
      if (firstCandidate != null && await _prepareDictionary(firstCandidate)) {
        if (!mounted) return;
        setState(() {
          _availableMdxPaths = {..._availableMdxPaths, firstCandidate.mdxPath};
        });
        entries = _availableEntries;
      }
    }
    final nextSelected = entries
            .where((entry) =>
                _articlesByDictionary[entry.mdxPath]?.isNotEmpty ?? false)
            .map((entry) => entry.mdxPath)
            .firstOrNull ??
        entries.map((entry) => entry.mdxPath).firstOrNull;
    setState(() {
      _selectedMdxPath = nextSelected;
      _articleAnchor = null;
      _articleScrollOffset = null;
      if (entries.isEmpty) _articlesByDictionary = const {};
    });
    final query = _queryController.text.trim();
    if (query.isNotEmpty && entries.isNotEmpty) {
      await _lookup(query, preferredMdxPath: nextSelected);
    }
  }

  Future<void> _showLibrary() async {
    var entries = _libraryEntries;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SizedBox(
              height: 440,
              child: entries.isEmpty
                  ? const Center(child: Text('词典库为空。请先导入一个 MDX 文件。'))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isActive = entry.mdxPath == _selectedMdxPath;
                        final isAvailable =
                            _availableMdxPaths.contains(entry.mdxPath);
                        return ListTile(
                          key: ValueKey(entry.mdxPath),
                          leading: Icon(
                            isActive
                                ? Icons.check_circle
                                : Icons.menu_book_outlined,
                          ),
                          title: Text(entry.title),
                          subtitle: Text(
                            '${entry.mdxPath}\n${entry.isEnabled ? '参与查询' : '已停用'}${isAvailable ? '' : ' · 文件暂时无法访问'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _isImporting || !entry.isEnabled
                              ? null
                              : () {
                                  Navigator.of(sheetContext).pop();
                                  _selectDictionary(entry);
                                },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: entry.isEnabled ? '停止参与查询' : '参与查询',
                                child: Switch(
                                  value: entry.isEnabled,
                                  onChanged: _isImporting
                                      ? null
                                      : (enabled) async {
                                          await _setDictionaryEnabled(
                                            entry,
                                            enabled,
                                          );
                                          entries = _libraryEntries;
                                          if (sheetContext.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '更多词典操作',
                                icon: const Icon(Icons.more_vert),
                                onSelected: (action) async {
                                  if (action == 'rename') {
                                    await _renameDictionary(
                                      sheetContext,
                                      entry,
                                    );
                                  } else if (action == 'remove') {
                                    await _remove(entry);
                                  }
                                  entries = _libraryEntries;
                                  if (sheetContext.mounted) {
                                    setSheetState(() {});
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('修改显示名称'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('从词典库移除'),
                                    ),
                                  ),
                                ],
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      onReorderItem: (oldIndex, newIndex) async {
                        final reordered = List.of(entries);
                        final moved = reordered.removeAt(oldIndex);
                        reordered.insert(newIndex, moved);
                        entries = reordered;
                        setSheetState(() {});
                        if (mounted) {
                          setState(() => _libraryEntries = reordered);
                        }
                        try {
                          final saved = await widget.library.reorder(
                            reordered.map((entry) => entry.mdxPath).toList(),
                          );
                          entries = saved;
                          if (mounted) {
                            setState(() => _libraryEntries = saved);
                          }
                        } catch (_) {
                          if (mounted) {
                            _showMessage('无法保存词典顺序。');
                          }
                        }
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAppDiagnostics() async {
    await showAppDiagnosticsSheet(
      context,
      loadReport: () => _appDiagnostics.collect(
        dictionaryCount: _libraryEntries.length,
        enabledDictionaryCount:
            _libraryEntries.where((entry) => entry.isEnabled).length,
        availableDictionaryCount: _availableMdxPaths.length,
        historyCount: _history.length,
        favoriteCount: _favorites.length,
        reviewCardCount: _reviewCards.length,
      ),
      saveDiagnostics: _saveDiagnosticsReport,
      clearDiagnostics: _appDiagnostics.clearReaderEvents,
      exportLearningData: _exportLearningData,
      importLearningData: _importLearningData,
    );
  }

  Future<void> _saveDiagnosticsReport(AppDiagnosticsReport report) async {
    final stamp = report.generatedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final saved = await FilePicker.saveFile(
      dialogTitle: '保存 LumaLex 诊断报告',
      fileName: 'LumaLex-diagnostics-$stamp.txt',
      bytes: Uint8List.fromList(utf8.encode(report.toText())),
      mimeType: 'text/plain',
    );
    if (saved != null && mounted) {
      _showMessage('诊断报告已保存。');
    }
  }

  Future<void> _exportLearningData() async {
    final backup = LearningDataBackup(
      exportedAt: DateTime.now(),
      history: _history,
      favorites: _favorites,
      reviewCards: _reviewCards,
      textScale: _textScale,
    );
    final day = DateTime.now().toIso8601String().split('T').first;
    final saved = await FilePicker.saveFile(
      dialogTitle: '导出 LumaLex 学习数据',
      fileName: 'LumaLex-learning-data-$day.json',
      bytes: Uint8List.fromList(utf8.encode(backup.encode())),
      mimeType: 'application/json',
    );
    if (saved != null && mounted) {
      _showMessage('学习数据已导出；文件中不包含词典内容。');
    }
  }

  Future<void> _importLearningData() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择 LumaLex 学习数据',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) return;
    try {
      final backup = LearningDataBackup.decode(
        utf8.decode(await picked.readAsBytes()),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('恢复学习数据？'),
              content: Text(
                '将用备份中的 ${backup.history.length} 条历史、'
                '${backup.favorites.length} 个收藏和 '
                '${backup.reviewCards.length} 张复习卡片替换当前学习记录。'
                '词典文件和词典库不会改变。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('恢复'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      final cards = synchronizeReviewCards(
        backup.favorites,
        backup.reviewCards,
        now: DateTime.now(),
      );
      await Future.wait([
        widget.wordRecords.saveHistory(backup.history),
        widget.wordRecords.saveFavorites(backup.favorites),
        widget.wordRecords.saveReviewCards(cards),
        widget.wordRecords.saveTextScale(backup.textScale),
      ]);
      if (!mounted) return;
      _wordRecordsMutationGeneration++;
      _readerPositionCache.clear();
      setState(() {
        _history = backup.history;
        _favorites = backup.favorites;
        _reviewCards = cards;
        _textScale = backup.textScale;
        _reviewAnswerVisible = false;
      });
      _showMessage('学习数据已恢复。');
    } on FormatException catch (error) {
      if (mounted) _showMessage('无法恢复学习数据：${error.message}');
    } catch (error) {
      debugPrint('Learning data import failed: $error');
      if (mounted) _showMessage('无法读取或保存这份学习数据。');
    }
  }

  Future<void> _setDictionaryEnabled(
    DictionaryLibraryEntry entry,
    bool enabled,
  ) async {
    if (enabled && !_availableMdxPaths.contains(entry.mdxPath)) {
      setState(() => _isImporting = true);
      final prepared = await _prepareDictionary(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _isImporting = false;
        if (prepared) {
          _availableMdxPaths = {..._availableMdxPaths, entry.mdxPath};
        }
      });
      if (!prepared) {
        _showMessage('无法打开「${entry.title}」。请重新导入以恢复文件访问。');
        return;
      }
    }
    final entries = await widget.library.upsert(
      entry.copyWith(isEnabled: enabled),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _libraryEntries = entries;
      if (enabled) {
        if (_entryMatchesActiveDictionaryScope(entry)) {
          _selectedMdxPath ??= entry.mdxPath;
        }
      } else if (_selectedMdxPath == entry.mdxPath) {
        _selectedMdxPath = dictionaryEntriesForScope(
          entries.where(
            (candidate) =>
                candidate.isEnabled &&
                _availableMdxPaths.contains(candidate.mdxPath),
          ),
          _activeDictionaryScopeId,
        ).map((candidate) => candidate.mdxPath).firstOrNull;
        _articleAnchor = null;
        _articleScrollOffset = null;
      }
    });
    final query = _queryController.text.trim();
    if (query.isNotEmpty && _availableEntries.isNotEmpty) {
      await _lookup(query, preferredMdxPath: _selectedMdxPath);
    } else if (_availableEntries.isEmpty && mounted) {
      setState(() => _articlesByDictionary = const {});
    }
  }

  double get _currentTextScale => _textScale;

  void _setCurrentTextScale(double scale) {
    final updated = scale.clamp(0.6, 2.0).toDouble();
    if (updated != _textScale) {
      // Pixel offsets are not stable across a full-document text reflow.
      // Retained WKWebViews preserve their own live positions; discard only
      // the offsets for readers that were already evicted.
      _readerPositionCache.clear();
    }
    setState(() => _textScale = updated);
    if (_showReaderTextControls) {
      _scheduleReaderTextControlsHide();
    }
    widget.wordRecords.saveTextScale(updated).catchError((Object _) {
      if (mounted) {
        _showMessage('字号已调整，但无法保存全局字号设置。');
      }
    });
  }

  void _focusSearchField() {
    _searchFocusNode.requestFocus();
    _queryController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _queryController.text.length,
    );
  }

  void _toggleFavoriteShortcut() {
    final query = _queryController.text.trim();
    if (query.isNotEmpty) {
      unawaited(_toggleFavorite(query));
    }
  }

  void _goBackShortcut() {
    if (_lookupNavigation.canGoBack && !_isSearching) {
      unawaited(_goBack());
    }
  }

  void _goForwardShortcut() {
    if (_lookupNavigation.canGoForward && !_isSearching) {
      unawaited(_goForward());
    }
  }

  void _escapeShortcut() {
    if (_suggestions.isNotEmpty) {
      setState(() {
        _suggestions = const [];
        _selectedSuggestionIndex = -1;
      });
      return;
    }
    _searchFocusNode.unfocus();
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedSuggestionIndex =
            (_selectedSuggestionIndex + 1) % _suggestions.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedSuggestionIndex =
            (_selectedSuggestionIndex - 1 + _suggestions.length) %
                _suggestions.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final index =
          _selectedSuggestionIndex.clamp(0, _suggestions.length - 1).toInt();
      _activateSuggestion(_suggestions[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activateSuggestion(String suggestion) {
    _queryController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    unawaited(_startNewLookup(suggestion));
  }

  void _selectDestination(_AppDestination destination) {
    if (_destination != destination) {
      setState(() => _destination = destination);
    }
  }

  bool get _hasVisibleReaderArticle {
    final selectedPath = _selectedMdxPath;
    if (selectedPath == null) {
      return false;
    }
    return _articlesByDictionary[selectedPath]?.isNotEmpty ?? false;
  }

  void _clearLookup() {
    _readerControlsTimer?.cancel();
    _searchFocusNode.unfocus();
    _queryController.clear();
    setState(() {
      _lookupNavigation.clear();
      _showReaderTextControls = false;
    });
    _suggest('');
    unawaited(_lookup(''));
  }

  void _toggleReaderTextControls() {
    if (!_hasVisibleReaderArticle) return;
    _readerControlsTimer?.cancel();
    _searchFocusNode.unfocus();
    final show = !_showReaderTextControls;
    setState(() {
      _showReaderTextControls = show;
      if (widget.processTextMode) {
        _suggestions = const [];
        _selectedSuggestionIndex = -1;
      }
    });
    if (show) {
      _scheduleReaderTextControlsHide();
    }
  }

  void _scheduleReaderTextControlsHide() {
    _readerControlsTimer?.cancel();
    _readerControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showReaderTextControls) {
        setState(() => _showReaderTextControls = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.processTextMode) {
      return _buildProcessTextShell();
    }
    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final useSideRail = constraints.maxWidth >= 600;
        final expandSideRail = constraints.maxWidth >= 1080;
        final railColorScheme = Theme.of(context).colorScheme;
        final expandedRailLabelStyle = TextStyle(
          fontSize: 17,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: railColorScheme.onSurfaceVariant,
        );
        // Foldable cover displays are often as narrow as a phone but notably
        // shorter. Keep their secondary pages content-first without changing
        // the normal phone or tablet layouts.
        final useShortMobileLayout =
            !useSideRail && constraints.maxHeight < 640;
        final compactReader = !useSideRail &&
            _destination == _AppDestination.lookup &&
            _hasVisibleReaderArticle;
        final content = _buildDestinationPages(
          compact: !useSideRail,
          shortMobile: useShortMobileLayout,
        );
        return Scaffold(
          // Lookup is a reader, not a conventional app page. Its own compact
          // search header replaces the generic title bar on phones so the
          // dictionary entry gets the screen first.
          appBar: useSideRail || _destination == _AppDestination.lookup
              ? null
              : _buildCompactAppBar(shortMobile: useShortMobileLayout),
          body: useSideRail
              ? Row(
                  children: [
                    SafeArea(
                      right: false,
                      child: NavigationRail(
                        extended: expandSideRail,
                        minExtendedWidth: expandSideRail ? 244 : 220,
                        selectedIconTheme: expandSideRail
                            ? IconThemeData(
                                size: 32,
                                color: railColorScheme.primary,
                              )
                            : null,
                        unselectedIconTheme: expandSideRail
                            ? IconThemeData(
                                size: 30,
                                color: railColorScheme.onSurfaceVariant,
                              )
                            : null,
                        selectedLabelTextStyle: expandSideRail
                            ? expandedRailLabelStyle.copyWith(
                                fontWeight: FontWeight.w700,
                                color: railColorScheme.onSurface,
                              )
                            : null,
                        unselectedLabelTextStyle:
                            expandSideRail ? expandedRailLabelStyle : null,
                        selectedIndex: _destination.index,
                        onDestinationSelected: (index) =>
                            _selectDestination(_AppDestination.values[index]),
                        leading: Padding(
                          padding: EdgeInsets.fromLTRB(
                            expandSideRail ? 16 : 12,
                            12,
                            expandSideRail ? 16 : 12,
                            expandSideRail ? 30 : 26,
                          ),
                          child: _buildRailBrand(expanded: expandSideRail),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.search_rounded),
                            selectedIcon: Icon(Icons.search_rounded),
                            label: Text('查词'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.auto_stories_outlined),
                            selectedIcon: Icon(Icons.auto_stories_rounded),
                            label: Text('词汇本'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.library_books_outlined),
                            selectedIcon: Icon(Icons.library_books_rounded),
                            label: Text('词典'),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: SafeArea(child: content)),
                  ],
                )
              : SafeArea(top: false, child: content),
          // Keep the app destinations available when searching or managing
          // the library. Once an article is open, this is a focused reading
          // view; the back affordance beside the search field restores it.
          bottomNavigationBar: useSideRail || compactReader
              ? null
              : NavigationBar(
                  selectedIndex: _destination.index,
                  onDestinationSelected: (index) =>
                      _selectDestination(_AppDestination.values[index]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.search_outlined),
                      selectedIcon: Icon(Icons.search_rounded),
                      label: '查词',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_stories_outlined),
                      selectedIcon: Icon(Icons.auto_stories_rounded),
                      label: '词汇本',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_books_outlined),
                      selectedIcon: Icon(Icons.library_books_rounded),
                      label: '词典',
                    ),
                  ],
                ),
        );
      },
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
            _focusSearchField,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            _focusSearchField,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            _toggleFavoriteShortcut,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            _toggleFavoriteShortcut,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
            _goBackShortcut,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            _goBackShortcut,
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
            _goForwardShortcut,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            _goForwardShortcut,
        const SingleActivator(LogicalKeyboardKey.escape): _escapeShortcut,
      },
      child: Focus(autofocus: true, child: shell),
    );
  }

  Widget _buildProcessTextShell() {
    final colors = Theme.of(context).colorScheme;
    final shell = Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Scaffold(
            backgroundColor: colors.surface,
            body: Column(
              children: [
                _buildProcessTextTitleBar(),
                Divider(height: 1, color: colors.outlineVariant),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildLookupPage(compact: true),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _buildProcessTextResizeHandle(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          unawaited(AndroidProcessTextWindow.close());
        },
      },
      child: Focus(autofocus: true, child: shell),
    );
  }

  Widget _buildProcessTextTitleBar() {
    final colors = Theme.of(context).colorScheme;
    final favorite = _isFavorite(_queryController.text);
    final hasArticle = _hasVisibleReaderArticle;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/branding/lumalex-icon-ui.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'LumaLex',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
            ),
          ),
          IconButton(
            tooltip: _showReaderTextControls ? '收起字号调整' : '调整字号',
            onPressed: hasArticle ? _toggleReaderTextControls : null,
            icon: Text(
              'Aa',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _showReaderTextControls
                        ? colors.primary
                        : hasArticle
                            ? colors.onSurfaceVariant
                            : colors.onSurface.withValues(alpha: 0.38),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          IconButton(
            tooltip: favorite ? '取消收藏' : '收藏单词',
            onPressed: hasArticle
                ? () => _toggleFavorite(_queryController.text)
                : null,
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 21,
              color: favorite ? const Color(0xFFF2A51A) : null,
            ),
          ),
          IconButton(
            tooltip: '最大化或恢复窗口',
            onPressed: () {
              unawaited(AndroidProcessTextWindow.toggleMaximized());
            },
            icon: const Icon(Icons.open_in_full_rounded, size: 19),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _buildProcessTextResizeHandle() => Semantics(
        label: '调整查词窗口尺寸',
        hint: '拖动以改变宽度和高度',
        child: const SizedBox.square(
          dimension: 42,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(7),
              child: Icon(Icons.drag_handle_rounded, size: 22),
            ),
          ),
        ),
      );

  PreferredSizeWidget _buildCompactAppBar({required bool shortMobile}) =>
      AppBar(
        toolbarHeight: shortMobile ? 52 : 56,
        titleSpacing: 16,
        title: Text(
          switch (_destination) {
            _AppDestination.lookup => 'LumaLex',
            _AppDestination.wordbook => '词汇本',
            _AppDestination.dictionaries => '词典',
          },
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (shortMobile && _destination == _AppDestination.wordbook)
            IconButton(
              tooltip: '管理历史',
              onPressed: _showWordRecords,
              icon: const Icon(Icons.history_rounded),
            ),
          if (shortMobile && _destination == _AppDestination.dictionaries)
            if (_supportsDictionaryGroups) ...[
              IconButton(
                tooltip: '新建分组',
                onPressed: _showCreateDictionaryGroup,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              if (Platform.isIOS)
                _buildIosDictionaryImportMenu()
              else
                IconButton(
                  tooltip: '导入词典',
                  onPressed: _isImporting ? null : _pickAndImport,
                  icon: const Icon(Icons.add_rounded),
                ),
            ] else if (Platform.isIOS)
              _buildIosDictionaryImportMenu()
            else
              IconButton(
                tooltip: '导入词典',
                onPressed: _isImporting ? null : _pickAndImport,
                icon: const Icon(Icons.add_rounded),
              ),
          if (Platform.isAndroid &&
              _destination == _AppDestination.dictionaries)
            IconButton(
              tooltip: '关于与诊断',
              onPressed: _showAppDiagnostics,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          if (shortMobile) const SizedBox(width: 4),
        ],
      );

  Widget _buildIosDictionaryImportMenu() => PopupMenuButton<String>(
        tooltip: '添加词典',
        enabled: !_isImporting,
        icon: const Icon(Icons.add_rounded),
        onSelected: (action) {
          if (action == 'scan') {
            unawaited(_pickAndImport());
          } else if (action == 'external') {
            unawaited(_pickExternalAndImport());
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'scan',
            child: Row(
              children: [
                Icon(Icons.refresh_rounded),
                SizedBox(width: 12),
                Text('扫描 LumaLex 文件夹'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'external',
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded),
                SizedBox(width: 12),
                Text('从其他位置添加'),
              ],
            ),
          ),
        ],
      );

  Widget _buildRailBrand({required bool expanded}) {
    final icon = Container(
      width: expanded ? 48 : 42,
      height: expanded ? 48 : 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(expanded ? 15 : 13),
      ),
      child: Image.asset(
        'assets/branding/lumalex-icon-ui.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
    if (!expanded) return icon;
    // NavigationRail measures its leading widget with unconstrained width.
    // Give the expanded brand an explicit width before using Expanded for the
    // label so it remains visible and overflow-free in debug and release.
    return SizedBox(
      width: 212,
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'LumaLex',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps each navigation destination mounted while another tab is visible.
  ///
  /// In particular, the lookup destination owns a WebView. Rebuilding it on
  /// every tab switch makes the current article reload and loses its native
  /// rendering state. [IndexedStack] changes only which child is painted,
  /// while preserving all three page states and their scroll positions.
  Widget _buildDestinationPages({
    required bool compact,
    required bool shortMobile,
  }) =>
      IndexedStack(
        index: _destination.index,
        children: [
          KeyedSubtree(
            key: const PageStorageKey<String>('lookup-destination'),
            child: _buildLookupPage(compact: compact),
          ),
          KeyedSubtree(
            key: const PageStorageKey<String>('wordbook-destination'),
            child: _buildWordbookPage(
              compact: compact,
              shortMobile: shortMobile,
            ),
          ),
          KeyedSubtree(
            key: const PageStorageKey<String>('dictionaries-destination'),
            child: _buildDictionariesPage(
              compact: compact,
              shortMobile: shortMobile,
            ),
          ),
        ],
      );

  Widget _buildLookupPage({required bool compact}) {
    final readerOpen = _hasVisibleReaderArticle;
    return SafeArea(
      // The mobile lookup header is responsible for its own safe-area inset
      // because the generic AppBar is intentionally absent on this page.
      top: compact,
      bottom: compact && readerOpen,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.processTextMode ? 10 : (compact ? 12 : 24),
              widget.processTextMode ? 6 : (compact ? 8 : 18),
              widget.processTextMode ? 10 : (compact ? 12 : 24),
              widget.processTextMode ? 6 : (compact ? 8 : 20),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    if (widget.processTextMode)
                      if (_showReaderTextControls && readerOpen)
                        _buildProcessTextScaleControls()
                      else
                        _buildProcessTextSearchNavigation()
                    else
                      _buildLookupHeader(
                        readerOpen: readerOpen,
                      ),
                    if (!widget.processTextMode &&
                        readerOpen &&
                        (_lookupNavigation.canGoBack ||
                            _lookupNavigation.canGoForward)) ...[
                      const SizedBox(height: 4),
                      _buildArticleNavigationControls(),
                    ],
                    if (_allAvailableEntries.isNotEmpty &&
                        _queryController.text.trim().isNotEmpty) ...[
                      SizedBox(height: widget.processTextMode ? 4 : 6),
                      _buildDictionaryScopeSelector(compact: compact),
                    ],
                    if (_lookupCorrection case final correction?) ...[
                      const SizedBox(height: 6),
                      _buildCorrectionBanner(correction),
                    ],
                    SizedBox(height: widget.processTextMode ? 4 : 8),
                    Expanded(child: _buildReaderPageBody(compact: compact)),
                  ],
                ),
                if (_suggestions.isNotEmpty)
                  Positioned(
                    top: widget.processTextMode ? 48 : 64,
                    left: 0,
                    right: 0,
                    child: _buildSuggestions(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLookupHeader({required bool readerOpen}) => LayoutBuilder(
        builder: (context, constraints) {
          final useIconOnlyHomeButton = constraints.maxWidth < 520;
          return Row(
            children: [
              if (readerOpen && !widget.processTextMode) ...[
                LookupHomeButton(
                  iconOnly: useIconOnlyHomeButton,
                  onPressed: _isSearching ? null : _clearLookup,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(child: _buildSearchField()),
              if (readerOpen) ...[
                const SizedBox(width: 4),
                ReaderTextScaleToggleButton(
                  key: const ValueKey('reader-text-scale-toggle'),
                  expanded: _showReaderTextControls,
                  onPressed: _toggleReaderTextControls,
                ),
              ],
            ],
          );
        },
      );

  Widget _buildProcessTextSearchNavigation() => SizedBox(
        height: 44,
        child: Row(
          key: const ValueKey('process-text-search-navigation'),
          children: [
            if (_lookupNavigation.canGoBack)
              _buildProcessTextNavigationButton(
                tooltip: '上一个词条',
                icon: Icons.chevron_left_rounded,
                onPressed: _isSearching ? null : () => unawaited(_goBack()),
              ),
            Expanded(child: _buildSearchField(processTextCompact: true)),
            if (_lookupNavigation.canGoForward)
              _buildProcessTextNavigationButton(
                tooltip: '下一个词条',
                icon: Icons.chevron_right_rounded,
                onPressed: _isSearching ? null : () => unawaited(_goForward()),
              ),
          ],
        ),
      );

  Widget _buildProcessTextNavigationButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) =>
      SizedBox.square(
        dimension: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
        ),
      );

  Widget _buildProcessTextScaleControls() {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Material(
        key: const ValueKey('process-text-scale-controls'),
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            _buildProcessTextNavigationButton(
              tooltip: '缩小字号',
              icon: Icons.remove_rounded,
              onPressed: _currentTextScale <= 0.6
                  ? null
                  : () => _setCurrentTextScale(_currentTextScale - 0.1),
            ),
            Expanded(
              child: Text(
                '字号 ${(_currentTextScale * 100).round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            _buildProcessTextNavigationButton(
              tooltip: '放大字号',
              icon: Icons.add_rounded,
              onPressed: _currentTextScale >= 2
                  ? null
                  : () => _setCurrentTextScale(_currentTextScale + 0.1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleNavigationControls() => Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          children: [
            if (_lookupNavigation.canGoBack)
              OutlinedButton.icon(
                onPressed: _isSearching ? null : () => unawaited(_goBack()),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('上一个词条'),
              ),
            if (_lookupNavigation.canGoForward)
              OutlinedButton.icon(
                onPressed: _isSearching ? null : () => unawaited(_goForward()),
                icon: const Icon(Icons.redo_rounded, size: 18),
                label: const Text('下一个词条'),
              ),
          ],
        ),
      );

  Widget _buildWordbookPage({
    required bool compact,
    required bool shortMobile,
  }) =>
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 28,
              shortMobile ? 4 : (compact ? 12 : 24),
              compact ? 16 : 28,
              shortMobile ? 6 : (compact ? 12 : 20),
            ),
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!shortMobile) ...[
                    Row(
                      children: [
                        if (!compact)
                          Expanded(
                            child: Text(
                              '词汇本',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          )
                        else
                          const Spacer(),
                        TextButton.icon(
                          onPressed: _showWordRecords,
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: const Text('管理历史'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '收藏词汇会保存在这里，并自动加入闪卡复习计划。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TabBar(
                    tabs: shortMobile
                        ? const [
                            Tab(text: '收藏'),
                            Tab(text: '复习'),
                          ]
                        : const [
                            Tab(
                              icon: Icon(Icons.star_outline),
                              text: '收藏',
                            ),
                            Tab(
                              icon: Icon(Icons.style_outlined),
                              text: '复习',
                            ),
                          ],
                  ),
                  SizedBox(height: shortMobile ? 4 : 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildFavoriteWordbook(),
                        _buildReviewPlaceholder(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildFavoriteWordbook() {
    final colors = Theme.of(context).colorScheme;
    if (_favorites.isEmpty) {
      return _buildSectionEmptyState(
        icon: Icons.star_outline_rounded,
        title: '还没有收藏词汇',
        message: '在查词结果页点击星标，即可把单词加入词汇本。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _favorites.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('共 ${_favorites.length} 个收藏'),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    if (await _confirmClearWordList(
                      context,
                      title: '清空全部收藏？',
                      message: '全部收藏单词将被删除，此操作无法撤销。',
                    )) {
                      await _removeFavoriteWords(_favorites);
                    }
                  },
                  child: const Text('清空'),
                ),
              ],
            ),
          );
        }
        final word = _favorites[index - 1];
        return ListTile(
          leading: Icon(Icons.star_rounded, color: colors.tertiary),
          title:
              Text(word, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('点击查看词条'),
          trailing: IconButton(
            tooltip: '从收藏中删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _removeFavoriteWords([word]),
          ),
          onTap: () => unawaited(_openWordInLookup(word)),
        );
      },
    );
  }

  Widget _buildReviewPlaceholder() {
    if (_favorites.isEmpty) {
      return _buildSectionEmptyState(
        icon: Icons.style_outlined,
        title: '还没有可复习的词汇',
        message: '先在查词结果页收藏单词，它们会自动加入今天的复习队列。',
      );
    }

    final now = DateTime.now();
    final dueCards = dueReviewCards(_reviewCards, now: now);
    if (dueCards.isEmpty) {
      final nextCard = List<ReviewCard>.of(_reviewCards)
        ..sort((left, right) => left.dueAt.compareTo(right.dueAt));
      final nextDue =
          nextCard.isEmpty ? null : _reviewDueLabel(nextCard.first.dueAt, now);
      return _buildSectionEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: '今天的复习完成了',
        message: nextDue == null ? '继续收藏需要学习的词汇吧。' : '下次复习：$nextDue。',
      );
    }

    final card = dueCards.first;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.style_rounded, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '待复习 ${dueCards.length} 张',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '已收藏 ${_favorites.length} 个',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Material(
                  color: _reviewAnswerVisible
                      ? colors.surfaceContainerLow
                      : colors.primaryContainer.withValues(alpha: 0.48),
                  elevation: 1,
                  shadowColor: const Color(0x1A000000),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      if (!_reviewAnswerVisible) {
                        setState(() => _reviewAnswerVisible = true);
                      }
                    },
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _reviewAnswerVisible ? '词典摘要' : '词汇卡',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            SelectableText(
                              card.word,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            if (!_reviewAnswerVisible) ...[
                              const SizedBox(height: 28),
                              Text(
                                '先回想释义，再轻触卡片显示答案。',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _reviewAnswerVisible = true),
                                icon: const Icon(Icons.visibility_rounded),
                                label: const Text('显示释义'),
                              ),
                            ] else ...[
                              const SizedBox(height: 22),
                              Divider(color: colors.outlineVariant),
                              const SizedBox(height: 14),
                              Text(
                                card.gloss ?? '这个收藏来自旧版本，尚未保存词典摘要。可打开完整词条查看释义。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(height: 1.55),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      unawaited(_openWordInLookup(card.word)),
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text('打开完整词条'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_reviewAnswerVisible) ...[
                  const SizedBox(height: 16),
                  Text(
                    '这张词记得如何？',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildReviewRatingButton(
                        card,
                        ReviewRating.again,
                        label: '再来一次',
                        detail: '10 分钟',
                      ),
                      _buildReviewRatingButton(
                        card,
                        ReviewRating.hard,
                        label: '有点模糊',
                        detail: '1 天',
                      ),
                      _buildReviewRatingButton(
                        card,
                        ReviewRating.good,
                        label: '认识',
                        detail: _reviewIntervalLabel(card, ReviewRating.good),
                        emphasized: true,
                      ),
                      _buildReviewRatingButton(
                        card,
                        ReviewRating.easy,
                        label: '很熟',
                        detail: _reviewIntervalLabel(card, ReviewRating.easy),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewRatingButton(
    ReviewCard card,
    ReviewRating rating, {
    required String label,
    required String detail,
    bool emphasized = false,
  }) =>
      emphasized
          ? FilledButton(
              onPressed: () => _rateReviewCard(card, rating),
              child: _reviewRatingLabel(label, detail),
            )
          : OutlinedButton(
              onPressed: () => _rateReviewCard(card, rating),
              child: _reviewRatingLabel(label, detail),
            );

  Widget _reviewRatingLabel(String label, String detail) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          Text(
            detail,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      );

  String _reviewIntervalLabel(ReviewCard card, ReviewRating rating) {
    final scheduled = scheduleReview(card, rating, now: DateTime.now());
    return '${scheduled.intervalDays} 天';
  }

  String _reviewDueLabel(DateTime dueAt, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final difference = dueDay.difference(today).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '明天';
    return '$difference 天后';
  }

  Future<void> _rateReviewCard(
    ReviewCard card,
    ReviewRating rating,
  ) async {
    final scheduled = scheduleReview(card, rating, now: DateTime.now());
    final updated = _reviewCards
        .map(
          (candidate) => candidate.word.toLowerCase() == card.word.toLowerCase()
              ? scheduled
              : candidate,
        )
        .toList(growable: false);
    _wordRecordsMutationGeneration++;
    setState(() {
      _reviewCards = updated;
      _reviewAnswerVisible = false;
    });
    try {
      await widget.wordRecords.saveReviewCards(updated);
    } catch (_) {
      if (mounted) {
        _showMessage('复习进度已更新，但暂时无法保存。');
      }
    }
  }

  Widget _buildDictionariesPage({
    required bool compact,
    required bool shortMobile,
  }) {
    if (_isLibraryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 28,
            shortMobile ? 4 : (compact ? 12 : 24),
            compact ? 16 : 28,
            shortMobile ? 6 : (compact ? 12 : 20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!shortMobile) ...[
                Row(
                  children: [
                    if (!compact)
                      Expanded(
                        child: Text(
                          '词典',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (_supportsDictionaryGroups) ...[
                      OutlinedButton.icon(
                        onPressed: _showCreateDictionaryGroup,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('新建分组'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (Platform.isIOS) ...[
                      OutlinedButton.icon(
                        onPressed: _isImporting ? null : _pickExternalAndImport,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('其他位置'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _isImporting ? null : _pickAndImport,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('扫描文件夹'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: _isImporting ? null : _pickAndImport,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('导入'),
                      ),
                    if (Platform.isAndroid && !compact) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: '关于与诊断',
                        onPressed: _showAppDiagnostics,
                        icon: const Icon(Icons.info_outline_rounded),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  Platform.isIOS
                      ? '默认目录：${IosDictionaryHome.displayPath}。启用的词典会参与查词。'
                      : '管理本地 MDX/MDD 文件，启用的词典会参与查词。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: _libraryEntries.isEmpty
                    ? _buildSectionEmptyState(
                        icon: Icons.library_add_outlined,
                        title:
                            Platform.isIOS ? '把词典放入 LumaLex 文件夹' : '建立你的本地词典库',
                        message: Platform.isIOS
                            ? '在“文件”App 中打开 ${IosDictionaryHome.displayPath}，放入包含 MDX 与 MDD 的词典文件夹。'
                            : '导入一个包含 MDX 与 MDD 文件的文件夹后，即可离线查词。',
                        actionLabel: Platform.isIOS ? '扫描词典文件夹' : '导入词典',
                        actionIcon:
                            Platform.isIOS ? Icons.refresh_rounded : null,
                        onAction: _isImporting ? null : _pickAndImport,
                        secondaryActionLabel: Platform.isIOS ? '从其他位置添加' : null,
                        onSecondaryAction: Platform.isIOS && !_isImporting
                            ? _pickExternalAndImport
                            : null,
                      )
                    : _supportsDictionaryGroups
                        ? _buildGroupedDictionaryLibrary()
                        : _buildDictionaryLibraryList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDictionaryLibraryList() => ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        buildDefaultDragHandles: false,
        itemCount: _libraryEntries.length,
        itemBuilder: (context, index) {
          final entry = _libraryEntries[index];
          final isAvailable = _availableMdxPaths.contains(entry.mdxPath);
          return Card(
            key: ValueKey(entry.mdxPath),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(entry.title),
              subtitle: Text(
                !entry.isEnabled
                    ? '已停用'
                    : isAvailable
                        ? '参与查询'
                        : _failedMdxPaths.contains(entry.mdxPath)
                            ? '文件暂时无法访问'
                            : '正在后台准备',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: entry.isEnabled,
                    onChanged: _isImporting
                        ? null
                        : (enabled) => _setDictionaryEnabled(entry, enabled),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多词典操作',
                    onSelected: (action) async {
                      if (action == 'rename') {
                        await _renameDictionary(context, entry);
                      } else if (action == 'remove') {
                        await _remove(entry);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('修改显示名称')),
                      PopupMenuItem(value: 'remove', child: Text('从词典库移除')),
                    ],
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        onReorderItem: _reorderDictionaryLibrary,
      );

  Widget _buildGroupedDictionaryLibrary() {
    final groups = _dictionaryGroupSnapshot.groups;
    return CustomScrollView(
      slivers: [
        for (final group in groups)
          ..._buildDictionaryGroupSlivers(
            groupId: group.id,
            title: group.name,
            group: group,
          ),
        ..._buildDictionaryGroupSlivers(
          groupId: DictionaryGroupScope.ungrouped,
          title: '未分组',
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _buildDictionaryGroupSlivers({
    required String groupId,
    required String title,
    DictionaryGroup? group,
  }) {
    final entries = dictionaryEntriesForScope(_libraryEntries, groupId);
    final queryableCount = entries
        .where(
          (entry) =>
              entry.isEnabled && _availableMdxPaths.contains(entry.mdxPath),
        )
        .length;
    final expanded = _expandedDictionaryGroupIds.contains(groupId);
    final groupColor = group == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : _dictionaryGroupColor(group);
    return [
      SliverToBoxAdapter(
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedDictionaryGroupIds.remove(groupId);
                } else {
                  _expandedDictionaryGroupIds.add(groupId);
                }
              });
            },
            leading: Icon(
              group == null ? Icons.inbox_outlined : Icons.folder_rounded,
              color: groupColor,
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('$queryableCount 本可查询 · 共 ${entries.length} 本'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                if (group != null)
                  PopupMenuButton<String>(
                    tooltip: '更多分组操作',
                    onSelected: (action) {
                      if (action == 'rename') {
                        unawaited(_renameDictionaryGroup(group));
                      } else if (action == 'color') {
                        unawaited(_changeDictionaryGroupColor(group));
                      } else if (action == 'delete') {
                        unawaited(_deleteDictionaryGroup(group));
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('重命名分组'),
                      ),
                      PopupMenuItem(value: 'color', child: Text('更改文件夹颜色')),
                      PopupMenuItem(value: 'delete', child: Text('删除分组')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      if (expanded && entries.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Text(
              '此分组暂无词典。可从其他分组的词典菜单中移动到这里。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      if (expanded && entries.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.only(top: 8),
          sliver: SliverReorderableList(
            key: ValueKey('dictionary-reorder-$groupId'),
            itemCount: entries.length,
            itemBuilder: (context, index) => _buildGroupedDictionaryTile(
              entries[index],
              index,
              entries,
            ),
            onReorderItem: (oldIndex, newIndex) =>
                _reorderDictionaryGroup(entries, oldIndex, newIndex),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
    ];
  }

  Widget _buildGroupedDictionaryTile(
    DictionaryLibraryEntry entry,
    int index,
    List<DictionaryLibraryEntry> groupEntries,
  ) {
    final isAvailable = _availableMdxPaths.contains(entry.mdxPath);
    return Card(
      key: ValueKey('grouped-${entry.mdxPath}'),
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 5, 4, 5),
        leading: const Icon(Icons.menu_book_outlined),
        title: Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          !entry.isEnabled
              ? '已停用'
              : isAvailable
                  ? '参与查询'
                  : _failedMdxPaths.contains(entry.mdxPath)
                      ? '文件暂时无法访问'
                      : '正在后台准备',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: entry.isEnabled,
              onChanged: _isImporting
                  ? null
                  : (enabled) => _setDictionaryEnabled(entry, enabled),
            ),
            PopupMenuButton<String>(
              tooltip: '更多词典操作',
              onSelected: (action) async {
                if (action == 'rename') {
                  await _renameDictionary(context, entry);
                } else if (action == 'move') {
                  await _showMoveDictionaryToGroup(entry);
                } else if (action == 'up' && index > 0) {
                  await _reorderDictionaryGroup(
                    groupEntries,
                    index,
                    index - 1,
                  );
                } else if (action == 'down' &&
                    index < groupEntries.length - 1) {
                  await _reorderDictionaryGroup(
                    groupEntries,
                    index,
                    index + 1,
                  );
                } else if (action == 'remove') {
                  await _remove(entry);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('修改显示名称'),
                ),
                const PopupMenuItem(value: 'move', child: Text('移动到分组')),
                if (index > 0)
                  const PopupMenuItem(value: 'up', child: Text('上移')),
                if (index < groupEntries.length - 1)
                  const PopupMenuItem(value: 'down', child: Text('下移')),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('从词典库移除'),
                ),
              ],
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reorderDictionaryGroup(
    List<DictionaryLibraryEntry> groupEntries,
    int oldIndex,
    int newIndex,
  ) async {
    final previousLibrary = List<DictionaryLibraryEntry>.of(_libraryEntries);
    final reorderedGroup = List<DictionaryLibraryEntry>.of(groupEntries);
    final moved = reorderedGroup.removeAt(oldIndex);
    reorderedGroup.insert(newIndex, moved);
    final groupPaths = groupEntries.map((entry) => entry.mdxPath).toSet();
    var replacementIndex = 0;
    final reorderedLibrary = _libraryEntries.map((entry) {
      if (!groupPaths.contains(entry.mdxPath)) return entry;
      return reorderedGroup[replacementIndex++];
    }).toList(growable: false);
    setState(() => _libraryEntries = reorderedLibrary);
    try {
      final saved = await widget.library.reorder(
        reorderedLibrary.map((entry) => entry.mdxPath).toList(growable: false),
      );
      if (mounted) setState(() => _libraryEntries = saved);
    } catch (_) {
      if (mounted) {
        setState(() => _libraryEntries = previousLibrary);
        _showMessage('无法保存词典顺序。');
      }
    }
  }

  Widget _buildSectionEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) =>
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 42, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon ?? Icons.add_rounded),
                    label: Text(actionLabel),
                  ),
                ],
                if (secondaryActionLabel != null &&
                    onSecondaryAction != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onSecondaryAction,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(secondaryActionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Future<void> _openWordInLookup(String word) async {
    _selectDestination(_AppDestination.lookup);
    _queryController.value = TextEditingValue(
      text: word,
      selection: TextSelection.collapsed(offset: word.length),
    );
    await _startNewLookup(word);
  }

  Future<void> _reorderDictionaryLibrary(int oldIndex, int newIndex) async {
    final reordered = List.of(_libraryEntries);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() => _libraryEntries = reordered);
    try {
      final saved = await widget.library.reorder(
        reordered.map((entry) => entry.mdxPath).toList(growable: false),
      );
      if (mounted) setState(() => _libraryEntries = saved);
    } catch (_) {
      if (mounted) _showMessage('无法保存词典顺序。');
    }
  }

  Widget _buildSearchField({bool processTextCompact = false}) {
    final colors = Theme.of(context).colorScheme;
    final hasText = _queryController.text.isNotEmpty;
    return SearchBar(
      controller: _queryController,
      focusNode: _searchFocusNode,
      hintText: '搜索单词、短语或词条',
      leading: Padding(
        padding: EdgeInsets.only(left: processTextCompact ? 0 : 4),
        child: Icon(
          Icons.search_rounded,
          color: colors.primary,
          size: processTextCompact ? 21 : 25,
        ),
      ),
      trailing: [
        if (_isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colors.primary,
              ),
            ),
          )
        else if (hasText)
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.close_rounded, size: 20),
            constraints: processTextCompact
                ? const BoxConstraints.tightFor(width: 40, height: 40)
                : null,
            padding: processTextCompact ? EdgeInsets.zero : null,
            onPressed: () {
              _queryController.clear();
              _suggest('');
              _lookup('');
              setState(() {});
            },
          ),
      ],
      constraints: BoxConstraints(
        minHeight: processTextCompact ? 44 : 58,
        maxHeight: processTextCompact ? 44 : 58,
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: processTextCompact ? 10 : 16),
      ),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(
        BorderSide(color: colors.outlineVariant),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(processTextCompact ? 14 : 18),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        (processTextCompact
                ? Theme.of(context).textTheme.bodyLarge
                : Theme.of(context).textTheme.titleMedium)
            ?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      hintStyle: WidgetStatePropertyAll(
        (processTextCompact
                ? Theme.of(context).textTheme.bodyLarge
                : Theme.of(context).textTheme.titleMedium)
            ?.copyWith(
          color: colors.onSurfaceVariant.withValues(alpha: 0.72),
          fontWeight: FontWeight.w400,
        ),
      ),
      onSubmitted: _startNewLookup,
      onChanged: (value) {
        setState(() => _lookupCorrection = null);
        _suggest(value);
      },
    );
  }

  Widget _buildSuggestions() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 224),
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140E3538),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          return ListTile(
            dense: true,
            selected: index == _selectedSuggestionIndex,
            selectedTileColor: colors.primaryContainer.withValues(alpha: 0.45),
            leading: Icon(
              Icons.manage_search_rounded,
              size: 20,
              color: colors.primary,
            ),
            title: Text(
              suggestion,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: Icon(
              Icons.north_west_rounded,
              size: 17,
              color: colors.outline,
            ),
            onTap: () => _activateSuggestion(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildBody({required bool compact}) {
    if (_isLibraryLoading) {
      return _buildEmptyState(
        icon: Icons.auto_stories_rounded,
        title: '正在打开词典库',
        message: '词典索引准备完成后即可开始查词。',
        loading: true,
      );
    }
    if (_availableEntries.isEmpty) {
      final hasAccessibleDictionary = _libraryEntries.any(
        (entry) => _availableMdxPaths.contains(entry.mdxPath),
      );
      return _buildEmptyState(
        icon: _libraryEntries.isEmpty
            ? Icons.library_add_rounded
            : Icons.library_books_rounded,
        title: _libraryEntries.isEmpty ? '建立你的离线词典库' : '当前没有可用词典',
        message: _libraryEntries.isEmpty
            ? Platform.isIOS
                ? '将 MDX/MDD 词典放入 ${IosDictionaryHome.displayPath}，然后扫描导入。'
                : '导入 MDX 与 MDD 词典，所有内容都保留在本地。'
            : hasAccessibleDictionary
                ? '请在词典库中启用至少一本参与查询的词典。'
                : '词典文件暂时无法访问，请打开词典库恢复访问。',
        actionLabel: _libraryEntries.isEmpty
            ? Platform.isIOS
                ? '扫描词典文件夹'
                : '导入第一本词典'
            : '打开词典库',
        onAction: _libraryEntries.isEmpty ? _pickAndImport : _showLibrary,
      );
    }
    if (_queryController.text.trim().isEmpty) {
      if (_history.isNotEmpty) {
        return _buildRecentSearches();
      }
      return _buildEmptyState(
        icon: Icons.travel_explore_rounded,
        title: '想查哪个词？',
        message: '在上方输入单词或短语，LumaLex 会同时检索已启用的词典。',
      );
    }
    final selectedPath = _selectedMdxPath;
    if (selectedPath == null) {
      return _buildEmptyState(
        icon: Icons.menu_book_rounded,
        title: '没有可显示的内容',
        message: '请尝试切换词典或重新查询。',
      );
    }
    final entries = _availableEntries;
    return _buildAllDictionariesView(entries, compact: compact);
  }

  Widget _buildReaderPageBody({required bool compact}) {
    final body = _buildBody(compact: compact);
    if (!_readerPlatformPolicy.switchDictionaryOnReaderSwipe ||
        !_hasVisibleReaderArticle) {
      return body;
    }

    // Listening to raw pointers leaves the WebView's native scrolling and
    // text-selection gestures in control of the touch sequence.
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _readerPageSwipe.pointerDown(
            pointer: event.pointer,
            x: event.localPosition.dx,
            y: event.localPosition.dy,
            width: constraints.maxWidth,
          );
        },
        onPointerMove: (event) {
          _readerPageSwipe.pointerMove(
            pointer: event.pointer,
            x: event.localPosition.dx,
            y: event.localPosition.dy,
          );
        },
        onPointerCancel: (event) {
          _readerPageSwipe.pointerCancel(event.pointer);
        },
        onPointerUp: (event) {
          final forward = _readerPageSwipe.pointerUp(
            pointer: event.pointer,
            x: event.localPosition.dx,
            y: event.localPosition.dy,
          );
          if (forward != null) {
            _switchDictionaryResult(forward: forward);
          }
        },
        child: body,
      ),
    );
  }

  Widget _buildRecentSearches() {
    final colors = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(top: 2, bottom: 20),
      itemCount: _history.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 8),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  '最近搜索',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    if (await _confirmClearWordList(
                      context,
                      title: '清空查词历史？',
                      message: '全部历史记录将被删除，此操作无法撤销。',
                    )) {
                      await _removeHistoryWords(_history);
                    }
                  },
                  child: const Text('清空'),
                ),
              ],
            ),
          );
        }
        final word = _history[index - 1];
        return ListTile(
          leading: const Icon(Icons.history_rounded),
          title:
              Text(word, style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: IconButton(
            tooltip: '删除这条历史',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _removeHistoryWords([word]),
          ),
          onTap: () => unawaited(_openWordInLookup(word)),
        );
      },
    );
  }

  Widget _buildCorrectionBanner(
    ({String original, String replacement}) correction,
  ) =>
      LookupCorrectionBanner(
        original: correction.original,
        replacement: correction.replacement,
        onDismiss: () {
          if (!mounted || _lookupCorrection != correction) return;
          setState(() => _lookupCorrection = null);
        },
      );

  Widget _buildAllDictionariesView(
    List<DictionaryLibraryEntry> entries, {
    required bool compact,
  }) {
    final selected = entries
            .where((entry) => entry.mdxPath == _selectedMdxPath)
            .firstOrNull ??
        entries.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_readerPlatformPolicy.showWideDictionaryJumpRail &&
            constraints.maxWidth >= 980) {
          final articleView = _buildDictionaryArticleView(
            entries,
            selected,
            compact: false,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: articleView),
              const SizedBox(width: 14),
              SizedBox(
                width: 248,
                child: _buildDictionaryJumpRail(entries),
              ),
            ],
          );
        }
        // Small screens deliberately show one document at a time. The
        // dictionary selector lives above the reader and opens a sheet, which
        // avoids reserving a whole horizontal row for every installed title.
        return _buildDictionaryArticleView(
          entries,
          selected,
          compact: compact,
        );
      },
    );
  }

  Widget _buildDictionaryArticleView(
    List<DictionaryLibraryEntry> entries,
    DictionaryLibraryEntry selected, {
    required bool compact,
  }) {
    if (_readerPlatformPolicy.aggregateDictionaryResults) {
      if (_isSearching) {
        return _buildEmptyState(
          icon: Icons.hourglass_top_rounded,
          title: '正在准备全部词典内容',
          message: '完成后可在词典之间即时切换。',
          loading: true,
        );
      }
      final sections = <AggregateArticleSection>[
        for (final entry in entries)
          if (_articlesByDictionary[entry.mdxPath]?.firstOrNull
              case final article?)
            AggregateArticleSection(
              title: entry.title,
              article: article,
              textScale: _textScale,
            ),
      ];
      if (sections.isNotEmpty &&
          (_articlesByDictionary[selected.mdxPath]?.isNotEmpty ?? false)) {
        return _buildAndroidAggregateDictionaryReader(
          entries,
          sections,
          selected,
          compact: compact,
        );
      }
    }
    return _buildRetainedDictionaryReaders(
      entries,
      selected,
      compact: compact,
    );
  }

  Widget _buildAndroidAggregateDictionaryReader(
    List<DictionaryLibraryEntry> entries,
    List<AggregateArticleSection> sections,
    DictionaryLibraryEntry selected, {
    required bool compact,
  }) {
    final reader = AggregateArticlePage(
      key: ValueKey('android-aggregate-reader-$_readerQuery'),
      sections: sections,
      engine: widget.engine,
      controller: _aggregateArticleController,
      presentation: AggregateArticlePresentation.selectedDictionary,
      initialMdxPath: selected.mdxPath,
      initialAnchor: _articleAnchor,
      initialScrollOffset: _articleScrollOffset,
      onActiveDictionaryChanged: _handleAggregateActiveDictionaryChanged,
      onOpenHeadword: (mdxPath, headword, anchor, sourceScrollOffset) {
        final source =
            entries.where((entry) => entry.mdxPath == mdxPath).firstOrNull;
        if (source == null) return Future.value();
        return _openLinkedHeadword(
          source,
          headword,
          anchor,
          sourceScrollOffset,
        );
      },
    );
    final articleSurface = compact
        ? reader
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: reader,
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        articleSurface,
        _buildReaderQuickActions(),
      ],
    );
  }

  void _handleAggregateActiveDictionaryChanged(String mdxPath) {
    if (!mounted || _selectedMdxPath == mdxPath) return;
    if (!_availableEntries.any((entry) => entry.mdxPath == mdxPath)) return;
    setState(() {
      _selectedMdxPath = mdxPath;
      _articleAnchor = null;
      _articleScrollOffset = null;
    });
  }

  Widget _buildRetainedDictionaryReaders(
    List<DictionaryLibraryEntry> entries,
    DictionaryLibraryEntry selected, {
    required bool compact,
  }) {
    if (_readerPlatformPolicy.reuseRetainedReaderSlots) {
      return _buildReusableRetainedReaderSlots(
        entries,
        selected,
        compact: compact,
      );
    }
    final byPath = {for (final entry in entries) entry.mdxPath: entry};
    // LRU order decides which readers survive, but rendering in that order
    // moved Android platform views every time the selected dictionary changed.
    // Keep children in immutable library order so a tab switch changes only
    // IndexedStack.index and the native WebViews stay attached.
    final paths = retainedReaderDisplayOrder(
      libraryPaths: entries.map((entry) => entry.mdxPath),
      retainedLruPaths: _retainedReaderPaths.where(byPath.containsKey),
      selectedPath: selected.mdxPath,
    );
    return IndexedStack(
      index: paths.indexOf(selected.mdxPath),
      sizing: StackFit.expand,
      children: [
        for (final path in paths)
          _buildSelectedDictionaryArticle(
            byPath[path]!,
            _articlesByDictionary[path],
            compact: compact,
          ),
      ],
    );
  }

  Widget _buildReusableRetainedReaderSlots(
    List<DictionaryLibraryEntry> entries,
    DictionaryLibraryEntry selected, {
    required bool compact,
  }) {
    final byPath = {for (final entry in entries) entry.mdxPath: entry};
    final selectedSlot = _retainedReaderSlots.indexOf(selected.mdxPath);
    final fallbackSlot = _retainedReaderSlots.indexWhere(
      (path) => path != null && byPath.containsKey(path),
    );
    return IndexedStack(
      index: selectedSlot >= 0
          ? selectedSlot
          : fallbackSlot >= 0
              ? fallbackSlot
              : 0,
      sizing: StackFit.expand,
      children: [
        for (var index = 0; index < _retainedReaderSlots.length; index++)
          if (_retainedReaderSlots[index] case final path?
              when byPath[path] != null)
            _buildSelectedDictionaryArticle(
              byPath[path]!,
              _articlesByDictionary[path],
              compact: compact,
              readerKey: ValueKey('reusable-dictionary-reader-$index'),
            )
          else
            SizedBox.expand(
              key: ValueKey('empty-dictionary-reader-slot-$index'),
            ),
      ],
    );
  }

  Widget _buildSelectedDictionaryArticle(
      DictionaryLibraryEntry entry, List<Article>? articles,
      {required bool compact, Key? readerKey}) {
    if (articles == null) {
      return _buildEmptyState(
        icon: Icons.hourglass_top_rounded,
        title: '正在查询「${entry.title}」',
        message: '当前词典优先显示，其他词典仍会在后台继续查询。',
        loading: true,
      );
    }
    if (articles.isEmpty) {
      final hasResult =
          _articlesByDictionary.values.any((candidate) => candidate.isNotEmpty);
      return _buildEmptyState(
        icon: hasResult ? Icons.menu_book_outlined : Icons.search_off_rounded,
        title: hasResult ? '「${entry.title}」未收录该词' : '没有找到该词',
        message: hasResult ? '可在上方快速切换到已有结果的词典。' : '可以检查拼写，或尝试更短的词形。',
      );
    }
    final savedScrollOffset = _readerPositionCache.get(
      entry.mdxPath,
      _readerQuery,
    );
    final reader = ArticlePage(
      key: readerKey ?? ValueKey('dictionary-reader-${entry.mdxPath}'),
      article: articles.first,
      engine: widget.engine,
      localScriptCompatibilityEnabled: true,
      embedded: true,
      controller: _articleControllers.putIfAbsent(
        entry.mdxPath,
        ArticlePageController.new,
      ),
      initialAnchor: entry.mdxPath == _selectedMdxPath ? _articleAnchor : null,
      initialScrollOffset: entry.mdxPath == _selectedMdxPath
          ? _articleScrollOffset ?? savedScrollOffset
          : savedScrollOffset,
      textScale: _textScale,
      onDocumentRendered: () => _preloadNextDictionaryReader(entry.mdxPath),
      onOpenHeadword: (headword, anchor, sourceScrollOffset) =>
          _openLinkedHeadword(
        entry,
        headword,
        anchor,
        sourceScrollOffset,
      ),
    );
    // A phone reader is intentionally edge-to-edge: dictionary CSS gets the
    // available width instead of being nested in another rounded card.
    final articleSurface = compact
        ? reader
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: reader,
          );
    // Attach floating reading actions to the actual article rather than the
    // whole destination. On wide layouts this keeps them in the lower-right
    // of the text, not over the dictionary-result rail.
    return Stack(
      fit: StackFit.expand,
      children: [
        articleSurface,
        _buildReaderQuickActions(),
      ],
    );
  }

  List<String> _adoptRetainedReaderPaths(Iterable<String> paths) {
    final retained = List<String>.unmodifiable(paths);
    if (_readerPlatformPolicy.reuseRetainedReaderSlots) {
      _retainedReaderSlots = assignRetainedReaderSlots(
        currentSlots: _retainedReaderSlots,
        retainedLruPaths: retained,
        slotCount: _readerPlatformPolicy.maximumRetainedReaders,
      );
    }
    return retained;
  }

  void _rememberCurrentReaderPosition() {
    if (!_readerPlatformPolicy.reuseRetainedReaderSlots) return;
    final query = _readerQuery.trim();
    final path = _selectedMdxPath;
    if (query.isEmpty || path == null) return;
    final offset = _articleControllers[path]?.lastKnownScrollOffset ?? 0;
    _readerPositionCache.put(path, query, offset);
  }

  List<String> _retainReaderPath(List<String> current, String? path) {
    if (path == null) return current;
    final next = List<String>.of(current)
      ..remove(path)
      ..add(path);
    while (next.length > _maximumRetainedReaders) {
      next.removeAt(0);
    }
    return next;
  }

  void _preloadNextDictionaryReader(String renderedPath) {
    _readerPreloadDelay?.cancel();
    if (!_readerPlatformPolicy.preloadAdjacentDictionaryReader) return;
    final query = _readerQuery;
    _readerPreloadDelay = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || query != _queryController.text.trim()) return;
      if (!_retainedReaderPaths.contains(renderedPath) ||
          _retainedReaderPaths.length >= _maximumRetainedReaders) {
        return;
      }
      final nextPath = _availableEntries
          .map((entry) => entry.mdxPath)
          .where((path) => !_retainedReaderPaths.contains(path))
          .where((path) => _articlesByDictionary[path]?.isNotEmpty ?? false)
          .firstOrNull;
      if (nextPath == null) return;
      setState(() {
        _retainedReaderPaths = _adoptRetainedReaderPaths(
          _retainReaderPath(
            _retainedReaderPaths,
            nextPath,
          ),
        );
      });
    });
  }

  Widget _buildDictionaryJumpRail(List<DictionaryLibraryEntry> entries) {
    final colors = Theme.of(context).colorScheme;
    final foundCount = entries
        .where((entry) =>
            _articlesByDictionary[entry.mdxPath]?.isNotEmpty ?? false)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '在以下词典中找到',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 10),
            child: Text(
              _isSearching ? '正在查询…' : '$foundCount 本词典',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 3),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = entry.mdxPath == _selectedMdxPath;
                final pending = _articlesByDictionary[entry.mdxPath] == null;
                return Material(
                  color: selected
                      ? colors.primaryContainer.withValues(alpha: 0.72)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _selectDictionaryResult(entry),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 18,
                            color: selected ? colors.primary : colors.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message: entry.title,
                              child: Text(
                                entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          if (pending)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: SizedBox.square(
                                dimension: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDictionaryScopeSelector({required bool compact}) {
    final colors = Theme.of(context).colorScheme;
    final entries = _availableEntries;
    final activeGroup = _dictionaryGroupSnapshot.groups
        .where((group) => group.id == _activeDictionaryScopeId)
        .firstOrNull;
    final selected =
        entries.where((entry) => entry.mdxPath == _selectedMdxPath).firstOrNull;
    final positionLabel = dictionaryResultPositionLabel(
      entries.map((entry) => entry.mdxPath),
      _selectedMdxPath,
    );
    final scopeName = _dictionaryScopeName(_activeDictionaryScopeId);
    final dictionaryName = selected?.title;
    final label = _supportsDictionaryGroups
        ? dictionaryName == null
            ? scopeName
            : '$scopeName · $dictionaryName'
        : dictionaryName ?? '全部词典';
    final selectorChip = ExcludeSemantics(
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _allAvailableEntries.isEmpty
              ? null
              : _showDictionaryScopeSheet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  activeGroup == null
                      ? Icons.menu_book_rounded
                      : Icons.folder_rounded,
                  size: 18,
                  color: activeGroup == null
                      ? colors.primary
                      : _dictionaryGroupColor(activeGroup),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    positionLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 19, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 0),
      child: Semantics(
        button: true,
        label: '当前词典 $label，$positionLabel',
        hint: _readerPlatformPolicy.switchDictionaryOnReaderSwipe
            ? '点按打开词典列表；在词典正文左右滑动可切换词典'
            : '点按打开词典列表，向左滑切换下一本有结果的词典，向右滑切换上一本',
        onTap: _allAvailableEntries.isEmpty ? null : _showDictionaryScopeSheet,
        onIncrease: () => _switchDictionaryResult(forward: true),
        onDecrease: () => _switchDictionaryResult(forward: false),
        child: _readerPlatformPolicy.switchDictionaryOnReaderSwipe
            ? Align(alignment: Alignment.centerLeft, child: selectorChip)
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  _dictionarySelectorDragDistance = 0;
                },
                onHorizontalDragUpdate: (details) {
                  _dictionarySelectorDragDistance += details.delta.dx;
                },
                onHorizontalDragCancel: () {
                  _dictionarySelectorDragDistance = 0;
                },
                onHorizontalDragEnd: _finishDictionarySelectorDrag,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: selectorChip,
                        ),
                      ),
                      ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Icon(
                            Icons.swipe_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant
                                .withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _showDictionaryScopeSheet() async {
    if (_allAvailableEntries.isEmpty) return;
    var visibleScopeId = _activeDictionaryScopeId;
    var switchingScope = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final entries = dictionaryEntriesForScope(
            _allAvailableEntries,
            visibleScopeId,
          );
          final scopeChoices =
              <({String id, String name, int count, Color? color})>[
            (
              id: DictionaryGroupScope.all,
              name: '全部',
              count: _allAvailableEntries.length,
              color: null,
            ),
            for (final group in _dictionaryGroupSnapshot.groups)
              (
                id: group.id,
                name: group.name,
                count: dictionaryEntriesForScope(
                  _allAvailableEntries,
                  group.id,
                ).length,
                color: _dictionaryGroupColor(group),
              ),
            (
              id: DictionaryGroupScope.ungrouped,
              name: '未分组',
              count: dictionaryEntriesForScope(
                _allAvailableEntries,
                DictionaryGroupScope.ungrouped,
              ).length,
              color: null,
            ),
          ];
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '词典结果',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (switchingScope)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  if (_supportsDictionaryGroups)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          for (final scope in scopeChoices)
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                selected: visibleScopeId == scope.id,
                                avatar: Icon(
                                  scope.id == DictionaryGroupScope.all
                                      ? Icons.layers_outlined
                                      : scope.id ==
                                              DictionaryGroupScope.ungrouped
                                          ? Icons.inbox_outlined
                                          : Icons.folder_rounded,
                                  size: 18,
                                  color: scope.color ??
                                      Theme.of(sheetContext)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                                label: Text('${scope.name} ${scope.count}'),
                                onSelected: switchingScope
                                    ? null
                                    : (selected) async {
                                        if (!selected ||
                                            visibleScopeId == scope.id) {
                                          return;
                                        }
                                        setSheetState(() {
                                          visibleScopeId = scope.id;
                                          switchingScope = true;
                                        });
                                        await _selectDictionaryScope(scope.id);
                                        if (sheetContext.mounted) {
                                          setSheetState(
                                              () => switchingScope = false);
                                        }
                                      },
                              ),
                            ),
                        ],
                      ),
                    ),
                  Flexible(
                    child: entries.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                '这个分组里暂时没有已启用且可访问的词典。',
                                textAlign: TextAlign.center,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(sheetContext)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final selected =
                                  entry.mdxPath == _selectedMdxPath;
                              final articles =
                                  _articlesByDictionary[entry.mdxPath];
                              final pending = articles == null;
                              final found = articles?.isNotEmpty ?? false;
                              return ListTile(
                                leading: Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.menu_book_outlined,
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                                title: Text(
                                  entry.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  pending
                                      ? '正在查询…'
                                      : found
                                          ? '已找到词条'
                                          : '未收录该词',
                                ),
                                trailing: pending
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                                onTap: switchingScope
                                    ? null
                                    : () {
                                        Navigator.of(sheetContext).pop();
                                        _selectDictionaryResult(entry);
                                      },
                              );
                            },
                          ),
                  ),
                  if (_supportsDictionaryGroups && !widget.processTextMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _selectDestination(_AppDestination.dictionaries);
                          },
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('管理分组'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderQuickActions() {
    // The selected-text window owns persistent reading actions in its title
    // bar. Never overlay them on its deliberately small article viewport.
    if (widget.processTextMode) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final favorite = _isFavorite(_queryController.text);
    return Positioned(
      right: 4,
      bottom: 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showReaderTextControls) ...[
            Material(
              color: colors.surfaceContainerLowest,
              elevation: 4,
              shadowColor: const Color(0x33000000),
              borderRadius: BorderRadius.circular(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '放大字号',
                    onPressed: _currentTextScale >= 2
                        ? null
                        : () => _setCurrentTextScale(_currentTextScale + 0.1),
                    icon: const Icon(Icons.add_rounded),
                  ),
                  Text(
                    '${(_currentTextScale * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  IconButton(
                    tooltip: '缩小字号',
                    onPressed: _currentTextScale <= 0.6
                        ? null
                        : () => _setCurrentTextScale(_currentTextScale - 0.1),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          ReaderFavoriteButton(
            favorite: favorite,
            onPressed: () => _toggleFavorite(_queryController.text),
          ),
        ],
      ),
    );
  }

  void _selectDictionaryResult(DictionaryLibraryEntry entry) {
    // Keep recent same-word readers in the IndexedStack. A result-tab switch
    // then exposes its existing WebView instead of disposing it and parsing
    // the entry again on a later return.
    if (_selectedMdxPath == entry.mdxPath) {
      return;
    }
    _rememberCurrentReaderPosition();
    setState(() {
      final previous = _selectedMdxPath;
      _selectedMdxPath = entry.mdxPath;
      _retainedReaderPaths = _adoptRetainedReaderPaths(
        _retainReaderPath(
          _retainReaderPath(_retainedReaderPaths, previous),
          entry.mdxPath,
        ),
      );
      _articleAnchor = null;
      _articleScrollOffset = null;
    });
    if (_readerPlatformPolicy.aggregateDictionaryResults) {
      unawaited(_aggregateArticleController.showDictionary(entry.mdxPath));
    }
  }

  void _finishDictionarySelectorDrag(DragEndDetails details) {
    final distance = _dictionarySelectorDragDistance;
    final velocity = details.primaryVelocity ?? 0;
    _dictionarySelectorDragDistance = 0;
    final direction = distance.abs() >= 32
        ? distance
        : velocity.abs() >= 280
            ? velocity
            : 0;
    if (direction == 0) return;
    _switchDictionaryResult(forward: direction < 0);
  }

  void _switchDictionaryResult({required bool forward}) {
    final entries = _availableEntries;
    final resultPaths = entries
        .map((entry) => entry.mdxPath)
        .where((path) => _articlesByDictionary[path]?.isNotEmpty ?? false)
        .toSet();
    final targetPath = adjacentDictionaryResultPath(
      orderedMdxPaths: entries.map((entry) => entry.mdxPath),
      resultMdxPaths: resultPaths,
      selectedMdxPath: _selectedMdxPath,
      forward: forward,
    );
    if (targetPath == null) return;
    final target = entries.firstWhere((entry) => entry.mdxPath == targetPath);
    unawaited(HapticFeedback.selectionClick());
    _selectDictionaryResult(target);
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool loading = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 42, vertical: 38),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.primaryContainer,
                            colors.secondaryContainer,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: loading
                          ? Padding(
                              padding: const EdgeInsets.all(23),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.primary,
                              ),
                            )
                          : Icon(icon, size: 34, color: colors.primary),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.55,
                          ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: onAction,
                        icon: Icon(
                          _libraryEntries.isEmpty
                              ? Icons.add_rounded
                              : Icons.settings_rounded,
                        ),
                        label: Text(actionLabel),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _supportsDictionaryGroups =>
      _readerPlatformPolicy.supportsDictionaryGroups;

  String get _activeDictionaryScopeId => _supportsDictionaryGroups
      ? _dictionaryGroupSnapshot.activeScopeId
      : DictionaryGroupScope.all;

  bool _entryMatchesActiveDictionaryScope(DictionaryLibraryEntry entry) =>
      dictionaryEntriesForScope([entry], _activeDictionaryScopeId).isNotEmpty;

  List<DictionaryLibraryEntry> get _allAvailableEntries => _libraryEntries
      .where(
        (entry) =>
            entry.isEnabled && _availableMdxPaths.contains(entry.mdxPath),
      )
      .toList(growable: false);

  List<DictionaryLibraryEntry> get _availableEntries =>
      dictionaryEntriesForScope(_allAvailableEntries, _activeDictionaryScopeId);
}

class LookupCorrectionBanner extends StatefulWidget {
  const LookupCorrectionBanner({
    super.key,
    required this.original,
    required this.replacement,
    required this.onDismiss,
    this.autoDismissAfter = const Duration(seconds: 5),
  });

  final String original;
  final String replacement;
  final VoidCallback onDismiss;
  final Duration autoDismissAfter;

  @override
  State<LookupCorrectionBanner> createState() => _LookupCorrectionBannerState();
}

class _LookupCorrectionBannerState extends State<LookupCorrectionBanner> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _scheduleAutoDismiss();
  }

  @override
  void didUpdateWidget(covariant LookupCorrectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.original != widget.original ||
        oldWidget.replacement != widget.replacement ||
        oldWidget.autoDismissAfter != widget.autoDismissAfter) {
      _scheduleAutoDismiss();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(widget.autoDismissAfter, () {
      if (mounted) widget.onDismiss();
    });
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 5, 5, 5),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.secondary.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.spellcheck_rounded, size: 19, color: colors.secondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '未找到“${widget.original}”，已显示“${widget.replacement}”。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            key: const ValueKey('lookup-correction-dismiss'),
            tooltip: '关闭提示',
            onPressed: _dismiss,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _RenameDictionaryDialog extends StatefulWidget {
  const _RenameDictionaryDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDictionaryDialog> createState() =>
      _RenameDictionaryDialogState();
}

class _RenameDictionaryDialogState extends State<_RenameDictionaryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialName.length,
      );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_nameController.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('修改词典显示名称'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _nameController,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '显示名称',
              helperText: '只修改 LumaLex 中的名称，不会更改词典文件。',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '显示名称不能为空' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('保存'),
          ),
        ],
      );
}

class _DictionaryGroupNameDialog extends StatefulWidget {
  const _DictionaryGroupNameDialog({
    required this.title,
    required this.initialName,
    required this.validator,
  });

  final String title;
  final String initialName;
  final String? Function(String value) validator;

  @override
  State<_DictionaryGroupNameDialog> createState() =>
      _DictionaryGroupNameDialogState();
}

class _DictionaryGroupNameDialogState
    extends State<_DictionaryGroupNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialName.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: '分组名称',
              helperText: '只修改 LumaLex 中的分组，不会更改词典文件。',
            ),
            validator: (value) => widget.validator(value ?? ''),
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: _submit, child: const Text('保存')),
        ],
      );
}
