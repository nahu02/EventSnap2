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
import '../services/platform/snap_file_store.dart';
import '../services/platform/snap_service.dart';
import '../ui/error_presentation.dart';
import '../ui/inline_banner.dart';
import '../ui/layout.dart';
import '../widgets/home/composer_card.dart';
import '../widgets/home/example_suggestions.dart';
import '../widgets/home/home_action_bar.dart';
import '../widgets/home/model_status_chip.dart';
import '../widgets/home/setup_card.dart';
import 'crop_screen.dart';

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
/// - Screen snaps (`SharedContent.isSnap`, docs/v3_plan.md §9) put an
///   ephemeral screenshot into the composer; it is processed right away only
///   with `Settings.autoProcessSnaps`. "Snap & crop" first shows the crop
///   screen and then always starts extraction. Ephemeral images are deleted
///   when they are no longer needed (see [SnapFileStore]).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Maximum number of attached images.
  static const int maxImages = 4;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// What to do once a snap/share may be processed (see `_maybeAutoProcess`).
enum _AutoRun { none, shared, snap, always }

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
  _AutoRun _autoRun = _AutoRun.none;

  /// Why the last snap shortcut produced no screenshot (shown as a banner).
  SnapError? _snapProblem;
  bool _cropping = false;

  /// Input of the review screen that is open; its ephemeral images must
  /// survive until it closes (as must those of [_pendingReview]).
  ExtractionInput? _openReviewInput;

  SnapFileStore get _store => context.read<SnapFileStore>();

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
    final store = _store;
    try {
      final content = await source.takeInitialSharedContent();
      // App start: drop snaps of earlier sessions, but not the one that
      // launched the app.
      unawaited(store.deleteLeftovers(keep: content?.images ?? const []));
      if (content != null) _onSharedContent(content);
    } catch (e) {
      debugPrint('HomeScreen: could not read shared content: $e');
    }
  }

  void _onSharedContent(SharedContent content) {
    if (!mounted) return;
    if (content.isSnap) {
      unawaited(_onSnap(content));
      return;
    }
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
    _autoRun = _AutoRun.shared;
    _maybeAutoProcess();
  }

  /// A screenshot from a "Snap screen" / "Snap & crop" shortcut, or the
  /// reason there is none.
  Future<void> _onSnap(SharedContent content) async {
    final error = content.snapError;
    if (error != null) {
      setState(() => _snapProblem = error);
      _scrollToTop();
      return;
    }
    final image = content.images.firstOrNull;
    if (image == null) return;
    if (_cropping) {
      // A second snap while the crop screen is open would only show that
      // screen: drop it.
      unawaited(_store.delete(content.images));
      _showSnackBar('Finish cropping first');
      return;
    }
    if (_snapProblem != null) setState(() => _snapProblem = null);
    if (content.crop) {
      await _cropSnap(image);
      return;
    }
    _addSnapImage(image);
    _autoRun = _AutoRun.snap;
    _maybeAutoProcess();
  }

  Future<void> _cropSnap(InputImage image) async {
    _cropping = true;
    InputImage? cropped;
    try {
      cropped = await Navigator.of(context).push<InputImage>(
        MaterialPageRoute<InputImage>(
          fullscreenDialog: true,
          builder: (_) => CropScreen(image: image),
        ),
      );
    } finally {
      _cropping = false;
    }
    // Cancelled (or back): the full screenshot is not needed. After "Use
    // selection" the crop screen already deleted it.
    if (cropped == null) await _store.delete([image]);
    if (cropped == null || !mounted) {
      if (cropped != null) unawaited(_store.delete([cropped]));
      return;
    }
    _addSnapImage(cropped);
    // The user confirmed the selection: start right away.
    _autoRun = _AutoRun.always;
    _maybeAutoProcess();
  }

  /// Adds a snap to the composer (text and other images stay); the oldest
  /// image makes room when the limit is reached.
  void _addSnapImage(InputImage image) {
    _cancelProcessing();
    final images = [..._images, image];
    while (images.length > HomeScreen.maxImages) {
      images.removeAt(0);
    }
    _setComposer(text: _textController.text, images: images);
    _showSnackBar('Screenshot added');
  }

  /// Starts extraction for shared content / snaps when allowed. Waits (keeps
  /// the request pending) while settings are loading or another route is on
  /// top.
  void _maybeAutoProcess() {
    if (_autoRun == _AutoRun.none || !mounted || !_appState.isInitialized) {
      return;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final run = _autoRun;
    _autoRun = _AutoRun.none;
    final settings = _appState.settings;
    final allowed = switch (run) {
      _AutoRun.shared => settings.autoProcessShared,
      _AutoRun.snap => settings.autoProcessSnaps,
      _AutoRun.always => true,
      _AutoRun.none => false,
    };
    if (allowed && settings.isConfigured && _hasContent && !_isProcessing) {
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
      _discardEphemeral(input.images);
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
    _openReviewInput = input;
    final ReviewOutcome? outcome;
    try {
      outcome = await AppRouter.openReview(context, result);
    } finally {
      _openReviewInput = null;
    }
    if (!mounted) {
      unawaited(_store.delete(input.images));
      return;
    }
    if (outcome == ReviewOutcome.exported) {
      // Keep content that was shared in while the review screen was open.
      if (_composerInput == input) {
        _setComposer(text: '', images: const []);
      }
      _showSnackBar('Sent to your calendar app');
    }
    // The review is closed: its screenshots are no longer needed (a no-op
    // for those the cleared composer already deleted).
    _discardEphemeral(input.images, notify: false);
    _afterNavigation();
  }

  void _finishWithError(AiCancellationToken token, AiException error) {
    if (!mounted || !identical(_activeToken, token)) return;
    final input = _processingInput;
    setState(() {
      _activeToken = null;
      _processingInput = null;
      if (error.kind != AiErrorKind.cancelled) _error = error;
    });
    if (_error != null) _scrollToTop();
    if (input != null) _discardEphemeral(input.images);
  }

  /// The user cancels the running extraction: its screenshots go too.
  void _cancelByUser() {
    final images = _processingInput?.images;
    _cancelProcessing();
    if (images != null) _discardEphemeral(images);
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
    _autoRun = _AutoRun.none;
    // Snaps are deleted when they leave the composer: nothing to restore.
    _setComposer(
      text: snapshot.text,
      images: snapshot.images.where((i) => !i.isEphemeral).toList(),
    );
  }

  void _setComposer({required String text, required List<InputImage> images}) {
    // Screenshots that leave the composer are deleted (unless a review that
    // is still open needs them: it deletes them when it closes).
    final removed = _images.where((i) => !images.contains(i)).toList();
    unawaited(_store.delete(removed.where((i) => !_isProtected(i))));
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

  /// True while a review (open or waiting for Home) still shows [image].
  bool _isProtected(InputImage image) =>
      (_openReviewInput?.images.contains(image) ?? false) ||
      (_pendingReview?.input.images.contains(image) ?? false);

  /// Deletes the ephemeral [images] and takes them out of the composer. Used
  /// when they are no longer needed (extraction ended without a review, the
  /// review closed).
  void _discardEphemeral(Iterable<InputImage> images, {bool notify = true}) {
    final doomed = images
        .where((i) => i.isEphemeral && !_isProtected(i))
        .toList();
    if (doomed.isEmpty || !mounted) return;
    unawaited(_store.delete(doomed));
    setState(() => _images.removeWhere(doomed.contains));
    if (notify) {
      _showSnackBar(
        doomed.length == 1 ? 'Screenshot deleted' : 'Screenshots deleted',
      );
    }
  }

  void _removeImage(int index) {
    final removed = _images[index];
    if (removed.isEphemeral && !_isProtected(removed)) {
      unawaited(_store.delete([removed]));
    }
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
  // Snap problems

  Widget _buildSnapProblemBanner(SnapError error) {
    final (title, message) = switch (error) {
      SnapError.serviceDisabled => (
        'Turn on screen snaps',
        'Snap screen needs the EventSnap accessibility service. It only '
            'captures the screen when you trigger a Snap shortcut.',
      ),
      SnapError.unsupported => (
        'Screen snaps need Android 11 or newer',
        "This Android version can't take screenshots for EventSnap. You can "
            'still share a screenshot to EventSnap.',
      ),
      SnapError.secure => (
        "Couldn't capture this screen",
        'Some screens (banking apps, private content) block screenshots.',
      ),
      SnapError.failed => (
        'Screenshot failed',
        'Please try the shortcut again in a moment.',
      ),
    };
    return InlineBanner(
      key: const Key('snap_problem_banner'),
      tone: error == SnapError.failed || error == SnapError.secure
          ? BannerTone.error
          : BannerTone.warning,
      icon: Icons.screenshot_outlined,
      title: title,
      message: message,
      onDismiss: () => setState(() => _snapProblem = null),
      actions: [
        if (error == SnapError.serviceDisabled)
          TextButton(
            key: const Key('open_accessibility_settings_button'),
            onPressed: () => unawaited(
              context.read<SnapService>().openAccessibilitySettings(),
            ),
            child: const Text('Open accessibility settings'),
          ),
      ],
    );
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
      if (_snapProblem != null) ...[
        _buildSnapProblemBanner(_snapProblem!),
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
        if (!didPop) _cancelByUser();
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
          onCancel: _cancelByUser,
          stageText: _stageText,
          detailText: isProcessing ? statusLabel : null,
        ),
      ),
    );
  }
}
