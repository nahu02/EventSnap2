import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/ai_provider.dart';
import '../models/extraction.dart';
import '../models/settings.dart';
import '../models/shared_content.dart';
import '../navigation/app_router.dart';
import '../providers/app_state_provider.dart';
import '../services/ai/ai_cancellation_token.dart';
import '../services/ai/ai_exceptions.dart';
import '../services/ai/ai_service_factory.dart';
import '../services/platform/image_input_service.dart';
import '../services/platform/shared_content_source.dart';
import '../ui/error_presentation.dart';
import '../ui/inline_banner.dart';
import '../ui/layout.dart';
import '../widgets/home/composer_card.dart';
import '../widgets/home/example_suggestions.dart';
import '../widgets/home/home_action_bar.dart';
import '../widgets/home/model_status_chip.dart';
import '../widgets/home/setup_card.dart';

/// The home screen is the composer (docs/v3_plan.md §6.F): type, paste or
/// share text and images, tap "Find events", review the result.
///
/// - Until an API key is set up a setup card links to settings.
/// - While extracting, inputs are disabled and the bottom bar shows the stage
///   and a Cancel button.
/// - 0 events → inline hint; ≥ 1 → review screen; after a successful export
///   the composer is cleared.
/// - AI errors are shown inline with a next step (see `ui/error_presentation`).
/// - Content shared into the app replaces the composer and, if
///   `Settings.autoProcessShared` and the app is configured, is processed
///   right away — but only once settings have loaded and the home screen is
///   visible again.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Maximum number of attached images.
  static const int maxImages = 4;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

typedef _ComposerSnapshot = ({String text, List<InputImage> images});

class _HomeScreenState extends State<HomeScreen> {
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<InputImage> _images = [];
  String _lastText = '';

  late final AppStateProvider _appState;
  StreamSubscription<SharedContent>? _sharedSubscription;
  Settings? _knownSettings;

  /// Token of the running extraction; null when idle. Results of runs whose
  /// token is no longer active (cancelled / superseded) are ignored.
  AiCancellationToken? _activeToken;
  ExtractionInput? _processingInput;
  AiException? _error;
  bool _noEventsFound = false;

  /// A finished extraction waiting for Home to become the current route again
  /// (it finished while another route, e.g. Settings, was on top).
  ({ExtractionResult result, ExtractionInput input})? _pendingReview;

  /// Set when content was shared in; consumed by [_maybeAutoProcess] once
  /// settings are loaded and this screen is the current route.
  bool _autoProcessPending = false;

  (AiProvider, String, String)? _visionCheckKey;
  bool _modelLacksVision = false;

  bool get _isProcessing => _activeToken != null;
  bool get _hasText => _textController.text.trim().isNotEmpty;
  bool get _hasContent => _hasText || _images.isNotEmpty;

  ExtractionInput get _composerInput => ExtractionInput(
    text: _textController.text.trim(),
    images: List.unmodifiable(_images),
  );

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppStateProvider>();
    _appState.addListener(_onAppStateChanged);
    if (_appState.isInitialized) _knownSettings = _appState.settings;
    _textController.addListener(_onTextChanged);

    final source = context.read<SharedContentSource>();
    _sharedSubscription = source.sharedContentStream.listen(
      _onSharedContent,
      onError: (Object e) => debugPrint('HomeScreen: share stream error: $e'),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _takeInitialSharedContent(source),
    );
  }

  @override
  void dispose() {
    _activeToken?.cancel();
    _sharedSubscription?.cancel();
    _appState.removeListener(_onAppStateChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Listeners

  void _onTextChanged() {
    final text = _textController.text;
    if (text == _lastText) return; // selection-only change
    final hadText = _lastText.trim().isNotEmpty;
    _lastText = text;
    if (text.trim().isNotEmpty != hadText || _error != null || _noEventsFound) {
      setState(() {
        _error = null;
        _noEventsFound = false;
      });
    }
  }

  void _onAppStateChanged() {
    if (!mounted || !_appState.isInitialized) return;
    final settings = _appState.settings;
    if (settings != _knownSettings) {
      final hadSettings = _knownSettings != null;
      _knownSettings = settings;
      // An error like "API key rejected" is stale once settings changed.
      if (hadSettings && _error != null) setState(() => _error = null);
      _checkVisionSupport();
    }
    _maybeAutoProcess();
  }

  // ---------------------------------------------------------------------------
  // Sharing

  Future<void> _takeInitialSharedContent(SharedContentSource source) async {
    try {
      final content = await source.takeInitialSharedContent();
      if (content != null) _onSharedContent(content);
    } catch (e) {
      debugPrint('HomeScreen: could not read shared content: $e');
    }
  }

  void _onSharedContent(SharedContent content) {
    if (!mounted) return;
    final failed = content.failedImageCount;
    final failedMessage = failed > 0
        ? "Couldn't read $failed shared ${failed == 1 ? 'image' : 'images'}"
        : null;
    if (content.isEmpty) {
      if (failedMessage != null) _showSnackBar(failedMessage, floating: true);
      return;
    }
    final previous = _snapshot();
    _cancelProcessing();
    _setComposer(
      text: content.text?.trim() ?? '',
      images: content.images.take(HomeScreen.maxImages).toList(),
    );
    final hadContent =
        previous.text.trim().isNotEmpty || previous.images.isNotEmpty;
    _showSnackBar(
      failedMessage == null
          ? 'Shared content added'
          : 'Shared content added. $failedMessage',
      floating: failedMessage != null,
      onUndo: hadContent ? () => _restoreSnapshot(previous) : null,
    );
    _autoProcessPending = true;
    _maybeAutoProcess();
  }

  /// Starts extraction for shared content when allowed. Waits (keeps the
  /// request pending) while settings are loading or another route is on top.
  void _maybeAutoProcess() {
    if (!_autoProcessPending || !mounted || !_appState.isInitialized) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _autoProcessPending = false;
    final settings = _appState.settings;
    if (settings.autoProcessShared &&
        settings.isConfigured &&
        _hasContent &&
        !_isProcessing) {
      unawaited(_findEvents());
    }
  }

  // ---------------------------------------------------------------------------
  // Extraction

  Future<void> _findEvents() async {
    if (_isProcessing ||
        !_hasContent ||
        !_appState.isInitialized ||
        !_appState.isConfigured) {
      return;
    }
    final settings = _appState.settings;
    final input = _composerInput;
    final token = AiCancellationToken();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activeToken = token;
      _processingInput = input;
      _error = null;
      _noEventsFound = false;
    });

    final ExtractionResult result;
    try {
      final interpreter = context.read<AiServiceFactory>().createInterpreter(
        settings,
      );
      result = await interpreter.extractEvents(input, cancellationToken: token);
    } on AiException catch (e) {
      _finishWithError(token, e);
      return;
    } catch (e) {
      debugPrint('HomeScreen: unexpected extraction error: $e');
      _finishWithError(token, AiException(AiErrorKind.unknown, '$e', cause: e));
      return;
    }
    if (!mounted || !identical(_activeToken, token)) return;

    setState(() {
      _activeToken = null;
      _processingInput = null;
      _noEventsFound = result.events.isEmpty;
    });
    if (result.events.isEmpty) {
      _scrollToTop();
      return;
    }

    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      // Don't push Review on top of another route (e.g. Settings).
      _pendingReview = (result: result, input: input);
      _showSnackBar(
        'Events found — tap to review',
        actionLabel: 'Review',
        onAction: _openPendingReview,
      );
      return;
    }
    await _openReview(result, input);
  }

  Future<void> _openPendingReview() async {
    final pending = _pendingReview;
    if (pending == null || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _pendingReview = null;
    await _openReview(pending.result, pending.input);
  }

  Future<void> _openReview(
    ExtractionResult result,
    ExtractionInput input,
  ) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final outcome = await AppRouter.openReview(context, result);
    if (!mounted) return;
    if (outcome == ReviewOutcome.exported) {
      // Keep content that was shared in while the review screen was open.
      if (_composerInput == input) {
        _setComposer(text: '', images: const []);
      }
      _showSnackBar('Sent to your calendar app');
    }
    _afterNavigation();
  }

  void _finishWithError(AiCancellationToken token, AiException error) {
    if (!mounted || !identical(_activeToken, token)) return;
    setState(() {
      _activeToken = null;
      _processingInput = null;
      if (error.kind != AiErrorKind.cancelled) _error = error;
    });
    if (_error != null) _scrollToTop();
  }

  void _cancelProcessing() {
    final token = _activeToken;
    if (token == null) return;
    token.cancel();
    setState(() {
      _activeToken = null;
      _processingInput = null;
    });
  }

  String get _stageText {
    final imageCount = _processingInput?.images.length ?? 0;
    if (imageCount > 1) return 'Looking at your images…';
    if (imageCount == 1) return 'Looking at your image…';
    return 'Reading your text…';
  }

  // ---------------------------------------------------------------------------
  // Navigation

  Future<void> _openSettingsForLostKey() async {
    await _openSettings();
    if (mounted && _appState.isConfigured) {
      _appState.dismissApiKeyLostNotice();
    }
  }

  Future<void> _openSettings() async {
    await AppRouter.openSettings(context);
    if (!mounted) return;
    _afterNavigation();
  }

  /// Called when this screen is visible again after a pushed route closed.
  void _afterNavigation() {
    _checkVisionSupport();
    if (_pendingReview != null) {
      unawaited(_openPendingReview());
      return;
    }
    _maybeAutoProcess();
  }

  void _onErrorAction(ErrorAction action) {
    if (action.opensSettings) {
      unawaited(_openSettings());
    } else {
      unawaited(_findEvents());
    }
  }

  // ---------------------------------------------------------------------------
  // Composer actions

  _ComposerSnapshot _snapshot() =>
      (text: _textController.text, images: List.of(_images));

  void _restoreSnapshot(_ComposerSnapshot snapshot) {
    if (!mounted) return;
    _cancelProcessing();
    _autoProcessPending = false;
    _setComposer(text: snapshot.text, images: snapshot.images);
  }

  void _setComposer({required String text, required List<InputImage> images}) {
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _images
        ..clear()
        ..addAll(images);
      _error = null;
      _noEventsFound = false;
    });
    _checkVisionSupport();
  }

  void _useExample(String example) =>
      _setComposer(text: example, images: List.of(_images));

  void _clear() {
    final snapshot = _snapshot();
    _setComposer(text: '', images: const []);
    _showSnackBar('Cleared', onUndo: () => _restoreSnapshot(snapshot));
  }

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      debugPrint('HomeScreen: clipboard unavailable: $e');
    }
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      _showSnackBar('Nothing to paste');
      return;
    }
    final value = _textController.value;
    final selection = value.selection;
    final String newText;
    final int caret;
    if (selection.isValid && selection.end <= value.text.length) {
      newText = value.text.replaceRange(selection.start, selection.end, text);
      caret = selection.start + text.length;
    } else {
      final separator = value.text.isEmpty || value.text.endsWith('\n')
          ? ''
          : '\n';
      newText = '${value.text}$separator$text';
      caret = newText.length;
    }
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  Future<void> _addImage({required bool fromCamera}) async {
    if (_isProcessing || _images.length >= HomeScreen.maxImages) return;
    final service = context.read<ImageInputService>();
    final InputImage? image;
    try {
      image = fromCamera
          ? await service.captureWithCamera()
          : await service.pickFromGallery();
    } on ImageInputException catch (e) {
      // Pickers throw on failure (and return null on cancel); keep the
      // composer as it is and explain briefly.
      debugPrint('HomeScreen: could not add image: ${e.cause ?? e.message}');
      if (mounted) _showSnackBar(e.message);
      return;
    } catch (e) {
      debugPrint('HomeScreen: could not add image: $e');
      if (mounted) _showSnackBar("Couldn't load that image");
      return;
    }
    if (image == null ||
        !mounted ||
        _isProcessing ||
        _images.length >= HomeScreen.maxImages) {
      return;
    }
    setState(() {
      _images.add(image!);
      _error = null;
      _noEventsFound = false;
    });
    _checkVisionSupport();
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      _error = null;
      _noEventsFound = false;
    });
  }

  /// Looks up whether the active model can read images (once per
  /// provider/model/key) while images are attached.
  void _checkVisionSupport() {
    if (_images.isEmpty ||
        !_appState.isInitialized ||
        !_appState.isConfigured) {
      return;
    }
    final settings = _appState.settings;
    final key = (
      settings.provider,
      settings.activeModel,
      settings.activeApiKey,
    );
    if (key == _visionCheckKey) return;
    _visionCheckKey = key;
    if (_modelLacksVision) setState(() => _modelLacksVision = false);
    final catalog = context.read<AiServiceFactory>().modelCatalog;
    Future.sync(
      () => catalog.findModel(
        settings.provider,
        settings.activeModel,
        apiKey: settings.activeApiKey,
      ),
    ).then(
      (info) {
        if (!mounted || _visionCheckKey != key) return;
        final lacksVision = info?.supportsVision == false;
        if (lacksVision != _modelLacksVision) {
          setState(() => _modelLacksVision = lacksVision);
        }
      },
      onError: (Object e) {
        debugPrint('HomeScreen: model lookup failed: $e');
        if (_visionCheckKey == key) _visionCheckKey = null; // retry later
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Feedback helpers

  void _showSnackBar(
    String message, {
    VoidCallback? onUndo,
    String? actionLabel,
    VoidCallback? onAction,
    bool floating = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          persist: false,
          behavior: floating ? SnackBarBehavior.floating : null,
          action: onAction != null
              ? SnackBarAction(
                  label: actionLabel ?? 'Open',
                  onPressed: onAction,
                )
              : onUndo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final settings = appState.settings;
    final isReady = appState.isInitialized;
    final isConfigured = isReady && appState.isConfigured;
    final isProcessing = _isProcessing;
    final cameraSupported = context.read<ImageInputService>().isCameraSupported;
    final error = _error;
    final settingsError = appState.errorMessage;
    final statusLabel = ModelStatusChip.labelFor(
      settings.provider.displayName,
      settings.activeModel,
    );

    const gap = SizedBox(height: AppSpacing.l);
    final children = <Widget>[
      if (settingsError != null) ...[
        InlineBanner(
          key: const Key('settings_error_banner'),
          tone: BannerTone.error,
          icon: Icons.error_outline,
          title: 'Settings problem',
          message: settingsError,
          onDismiss: appState.clearError,
          actions: [
            TextButton(
              onPressed: () {
                appState.clearError();
                unawaited(appState.initialize());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
        gap,
      ],
      if (appState.showApiKeyLostNotice) ...[
        InlineBanner(
          key: const Key('api_key_lost_banner'),
          tone: BannerTone.warning,
          icon: Icons.key_off_outlined,
          title: 'Please re-enter your API key',
          message:
              "EventSnap's secure storage was upgraded and your saved key "
              "couldn't be carried over. Your other settings were kept.",
          onDismiss: appState.dismissApiKeyLostNotice,
          actions: [
            TextButton(
              onPressed: _openSettingsForLostKey,
              child: const Text('Open settings'),
            ),
          ],
        ),
        gap,
      ],
      if (isReady && !appState.isConfigured) ...[
        SetupCard(
          providerName: settings.provider.displayName,
          onOpenSettings: _openSettings,
        ),
        gap,
      ],
      if (error != null) ...[
        ErrorBanner(
          key: const Key('home_error_banner'),
          presentation: ErrorPresentation.forKind(error.kind),
          onAction: _onErrorAction,
          onDismiss: () => setState(() => _error = null),
        ),
        gap,
      ],
      if (_noEventsFound) ...[
        InlineBanner(
          key: const Key('no_events_banner'),
          icon: Icons.event_busy_outlined,
          title: 'No events found',
          message: _images.isEmpty
              ? 'Try adding a date or time.'
              : 'Try adding a date or time, or use a sharper photo.',
          onDismiss: () => setState(() => _noEventsFound = false),
        ),
        gap,
      ],
      if (isConfigured) ...[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ModelStatusChip(
            key: const Key('model_status_chip'),
            providerName: settings.provider.displayName,
            model: settings.activeModel,
            onPressed: isProcessing ? null : _openSettings,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
      ],
      ComposerCard(
        controller: _textController,
        focusNode: _textFocusNode,
        images: _images,
        enabled: !isProcessing,
        canAddImages: _images.length < HomeScreen.maxImages,
        onPaste: _paste,
        onPickFromGallery: () => _addImage(fromCamera: false),
        onCaptureWithCamera: cameraSupported
            ? () => _addImage(fromCamera: true)
            : null,
        onRemoveImage: _removeImage,
        onClear: _hasContent ? _clear : null,
      ),
      if (_images.isNotEmpty && _modelLacksVision) ...[
        const SizedBox(height: AppSpacing.m),
        InlineBanner(
          key: const Key('vision_warning_banner'),
          tone: BannerTone.warning,
          icon: Icons.hide_image_outlined,
          title: "This model can't read images",
          message:
              '${settings.activeModel} only understands text. Choose a model '
              'with vision to find events in photos.',
          actions: [
            TextButton(
              onPressed: isProcessing ? null : _openSettings,
              child: const Text('Change model'),
            ),
          ],
        ),
      ],
      if (!_hasContent && !isProcessing) ...[
        const SizedBox(height: AppSpacing.xl),
        ExampleSuggestions(onSelected: _useExample),
      ],
    ];

    return PopScope(
      canPop: !isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelProcessing();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('EventSnap'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: isProcessing ? null : _openSettings,
            ),
          ],
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.s,
            AppSpacing.page,
            AppSpacing.xl,
          ),
          child: ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        bottomNavigationBar: HomeActionBar(
          isProcessing: isProcessing,
          onFindEvents: isConfigured && _hasContent && !isProcessing
              ? _findEvents
              : null,
          onCancel: _cancelProcessing,
          stageText: _stageText,
          detailText: isProcessing ? statusLabel : null,
        ),
      ),
    );
  }
}
