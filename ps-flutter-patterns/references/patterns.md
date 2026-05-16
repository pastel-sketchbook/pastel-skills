# Flutter App Patterns — Reference

Battle-tested patterns for Pastel Sketchbook Flutter apps — copy, adapt, do **not** reinvent.

## 1. Project structure

Separate layers cleanly. Each layer has a single responsibility.

```
lib/
  main.dart              # Thin entry: WidgetsFlutterBinding, ProviderScope, run
  app.dart               # Root MaterialApp, theming, routing
  models/                # Immutable data classes with fromJson/toJson/copyWith
  services/              # Low-level I/O: HTTP clients, file ops, audio, PDF
  repositories/          # Coordinate services; expose clean domain methods
  state/                 # Riverpod providers and notifiers
  ui/
    screens/             # Full-page views
    widgets/             # Reusable composable widgets
    overlays/            # Modals, dialogs, toasts
  utils/                 # Misc helpers (formatters, extensions)
test/
  widget_test.dart       # Widget tests
  unit/                  # Pure logic tests
```

Keep `main.dart` minimal — just wiring:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}
```

## 2. Models

Immutable data classes with hand-written `copyWith`. Use `factory` constructors for JSON deserialization. Prefer `final` fields exclusively.

```dart
class Slide {
  const Slide({
    required this.id,
    required this.index,
    required this.imageFileName,
    this.notes = '',
    this.status = SlideStatus.idle,
    this.audioFileName,
  });

  factory Slide.fromJson(Map<String, dynamic> json) => Slide(
    id: json['id'] as String,
    index: json['index'] as int,
    imageFileName: json['imageFileName'] as String,
    notes: (json['notes'] as String?) ?? '',
    status: SlideStatus.values.byName(
      (json['status'] as String?) ?? SlideStatus.idle.name,
    ),
    audioFileName: json['audioFileName'] as String?,
  );

  final String id;
  final int index;
  final String imageFileName;
  final String notes;
  final SlideStatus status;
  final String? audioFileName;

  Slide copyWith({
    String? notes,
    SlideStatus? status,
    String? audioFileName,
    bool clearAudio = false,
  }) => Slide(
    id: id,
    index: index,
    imageFileName: imageFileName,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    audioFileName: clearAudio
        ? null
        : (audioFileName ?? this.audioFileName),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'index': index,
    'imageFileName': imageFileName,
    'notes': notes,
    'status': status.name,
    if (audioFileName != null) 'audioFileName': audioFileName,
  };
}
```

**Rules:**
- All fields `final`.
- `const` constructor when possible.
- `copyWith` returns a new instance; never mutate.
- Enums use `values.byName()` for deserialization with a fallback default.
- Use Dart 3 records for lightweight return types: `({String name, int count})`.
- Only use `freezed` if the model has deeply nested unions or >8 fields where manual `copyWith` becomes error-prone.

## 3. Enums with metadata

Attach labels and descriptions directly to enum values:

```dart
enum VoiceName {
  zephyr('Zephyr', 'Warm & Natural'),
  puck('Puck', 'Energetic'),
  charon('Charon', 'Authoritative');

  const VoiceName(this.label, this.description);

  final String label;
  final String description;

  static VoiceName fromLabel(String label) =>
      VoiceName.values.firstWhere(
        (v) => v.label == label,
        orElse: () => VoiceName.zephyr,
      );
}
```

## 4. Services

Thin, focused classes that handle a single external concern. Each exposed via a `@Riverpod(keepAlive: true)` provider.

### HTTP client (Dio)

```dart
import 'package:dio/dio.dart';
import 'package:my_app/services/error_handling_interceptor.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_provider.g.dart';

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  dio.interceptors.addAll([
    ErrorHandlingInterceptor(),
    PrettyDioLogger(requestHeader: true, requestBody: true),
  ]);

  ref.onDispose(dio.close);
  return dio;
}
```

### Dio error handling

Install one error interceptor before loggers so UI code never displays raw
`DioException` diagnostics. Keep the normalized exception small and
user-facing; preserve status codes only for diagnostics/tests.

```dart
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _connectionFailedMessage = 'Unable to reach the service. Check your '
    'internet connection and try again.';

class NetworkRequestException implements Exception {
  const NetworkRequestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ErrorHandlingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.reject(err.copyWith(error: normalizeDioError(err)));
  }
}

NetworkRequestException normalizeDioError(DioException error) {
  final statusCode = error.response?.statusCode;
  final apiMessage = _apiErrorMessage(error.response?.data);
  final fallback = switch (error.type) {
    DioExceptionType.connectionTimeout =>
      'The request timed out while connecting. Try again.',
    DioExceptionType.sendTimeout =>
      'The request timed out while sending data. Try again.',
    DioExceptionType.receiveTimeout =>
      'The request timed out while waiting for a response. Try again.',
    DioExceptionType.badCertificate =>
      'The secure connection could not be verified.',
    DioExceptionType.badResponse => _badResponseMessage(statusCode),
    DioExceptionType.cancel => 'The request was cancelled.',
    DioExceptionType.connectionError => _connectionFailedMessage,
    DioExceptionType.unknown => _unknownMessage(error.error),
  };

  return NetworkRequestException(
    apiMessage ?? fallback,
    statusCode: statusCode,
  );
}

String readableError(Object error) {
  if (error is DioException) {
    final normalized = error.error;
    if (normalized is NetworkRequestException) return normalized.message;
    return normalizeDioError(error).message;
  }
  if (error is NetworkRequestException) return error.message;
  if (error is TimeoutException) return 'The operation timed out. Try again.';
  if (error is SocketException) return _connectionFailedMessage;

  if (kDebugMode) return error.toString();
  return 'Something went wrong. Please try again.';
}

String? _apiErrorMessage(Object? data) {
  if (data is! Map<String, dynamic>) return null;
  final error = data['error'];
  if (error is Map<String, dynamic>) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
  }
  return null;
}

String _badResponseMessage(int? statusCode) => switch (statusCode) {
  400 => 'The service rejected the request. Check your input and try again.',
  401 => 'The API key was not accepted. Check it and try again.',
  403 => 'The API key does not have permission for this request.',
  429 => 'The service is rate limited. Wait a moment, then try again.',
  final int code when code >= 500 && code < 600 =>
    'The service is temporarily unavailable. Try again in a moment.',
  _ => 'The service could not complete the request. Try again.',
};

String _unknownMessage(Object? error) {
  if (error is SocketException) return _connectionFailedMessage;
  if (error is TimeoutException) return 'The operation timed out. Try again.';
  return 'The request failed unexpectedly. Try again.';
}
```

UI catch blocks should format caught errors instead of interpolating them:

```dart
try {
  await ref.read(itemsProvider.notifier).loadRemoteItems();
} on Object catch (error) {
  showError('Load failed: ${readableError(error)}');
}
```

**Rules:**
- Add `ErrorHandlingInterceptor()` before `PrettyDioLogger`.
- Prefer remote API error messages when the response includes a concise
  `error.message` field.
- Never display raw `DioException.toString()` in production UI.
- Unit test 400/401/429/5xx, timeout, and connection-error mappings.

### API client

Inject the shared `Dio` instance. Never construct `Dio` inline. Parse responses defensively.

```dart
@Riverpod(keepAlive: true)
MyApiService myApiService(Ref ref) =>
    MyApiService(ref.watch(dioProvider));

class MyApiService {
  MyApiService(this._dio);
  final Dio _dio;

  Future<String> fetchData({
    required String apiKey,
    required String input,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/endpoint',
      queryParameters: <String, dynamic>{'key': apiKey},
      data: <String, dynamic>{'input': input},
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    return _parseResponse(response.data);
  }

  String _parseResponse(Map<String, dynamic>? body) {
    // Defensive parsing — never trust external shapes
    final result = body?['result'] as String?;
    return result ?? 'No result';
  }
}
```

### Storage service

File-based persistence with `path_provider`. Serialize to JSON.

```dart
@Riverpod(keepAlive: true)
StorageService storageService(Ref ref) => StorageService();

class StorageService {
  Future<Directory> _projectDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/myapp');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> saveItems(List<Item> items) async {
    final path = '${(await _projectDir()).path}/data.json';
    final body = jsonEncode(items.map((i) => i.toJson()).toList());
    await File(path).writeAsString(body, flush: true);
  }

  Future<List<Item>> loadItems() async {
    final path = '${(await _projectDir()).path}/data.json';
    final file = File(path);
    if (!file.existsSync()) return const [];
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((j) => Item.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> clear() async {
    final dir = await _projectDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
```

**Rules:**
- One service per external concern (HTTP, storage, audio, PDF).
- Services are stateless — inject dependencies through constructor.
- Always `flush: true` on file writes.
- Return typed data, not raw JSON.
- `ref.onDispose` for cleanup (close connections, dispose players).

## 5. Repository pattern

Repositories sit between state and services. They coordinate multi-service operations and provide pure data-mapping helpers.

```dart
@Riverpod(keepAlive: true)
SlideRepository slideRepository(Ref ref) => SlideRepository(
      storage: ref.watch(storageServiceProvider),
      api: ref.watch(myApiServiceProvider),
    );

class SlideRepository {
  SlideRepository({
    required StorageService storage,
    required MyApiService api,
  })  : _storage = storage,
        _api = api;

  final StorageService _storage;
  final MyApiService _api;

  // Persistence delegation
  Future<List<Slide>> loadSlides() => _storage.loadSlides();
  Future<void> saveSlides(List<Slide> slides) =>
      _storage.saveSlides(slides);

  // Multi-service coordination
  Future<String> extractNotes({
    required Slide slide,
    required String apiKey,
  }) async {
    final path = await _storage.imageFilePath(slide.imageFileName);
    final bytes = await File(path).readAsBytes();
    return _api.extractNotes(bytes: bytes, apiKey: apiKey);
  }

  // Pure data-mapping helpers (no I/O)
  List<Slide> applyNotesUpdate(
    List<Slide> slides,
    String slideId,
    String notes,
  ) => <Slide>[
    for (final s in slides)
      if (s.id == slideId)
        s.copyWith(notes: notes, status: SlideStatus.idle, clearAudio: true)
      else
        s,
  ];
}
```

**Rules:**
- UI never imports services directly — only repositories and state providers.
- Pure helpers (list transforms) belong in the repository, not the notifier.
- Keep repositories testable: constructor injection, no global state.

## 6. Riverpod state management

Use annotation-based codegen. Every provider uses `@Riverpod` and a `part '*.g.dart'` directive.

### Async notifier (primary state holder)

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'slides_provider.g.dart';

@Riverpod(keepAlive: true)
class Slides extends _$Slides {
  @override
  Future<List<Slide>> build() =>
      ref.read(slideRepositoryProvider).loadSlides();

  Future<void> _persist(List<Slide> slides) async {
    state = AsyncData<List<Slide>>(slides);
    await ref.read(slideRepositoryProvider).saveSlides(slides);
  }

  Future<void> addItem(Slide slide) async {
    final current = state.value ?? const [];
    await _persist([...current, slide]);
  }

  Future<void> clear() async {
    await ref.read(slideRepositoryProvider).clearProject();
    state = const AsyncData<List<Slide>>([]);
  }
}
```

### Sync notifier (simple values)

```dart
@Riverpod(keepAlive: true)
class CurrentIndex extends _$CurrentIndex {
  @override
  int build() => 0;
  void set(int index) => state = index;
}
```

### Preferences-backed notifier

```dart
@Riverpod(keepAlive: true)
Future<SharedPreferences> sharedPreferences(Ref ref) =>
    SharedPreferences.getInstance();

@Riverpod(keepAlive: true)
class ThemeChoice extends _$ThemeChoice {
  @override
  AppTheme build() {
    final prefs = ref.watch(sharedPreferencesProvider).value;
    final id = prefs?.getString('theme_id');
    return themes.firstWhere(
      (t) => t.id == id,
      orElse: () => themes.first,
    );
  }

  Future<void> select(AppTheme theme) async {
    state = theme;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString('theme_id', theme.id);
  }
}
```

**Rules:**
- `keepAlive: true` for all long-lived state (slides, services, preferences, indices).
- Access state with `.value` (nullable) or `.requireValue` (throws).
- Use `AsyncData<T>` explicitly when setting state to avoid type inference issues.
- Read other providers with `ref.read()` in methods; `ref.watch()` only in `build()`.
- Wrap typed parameters in collection-for-in: `for (final Slide s in slides)` to help type inference.
- Run `dart run build_runner build` after adding/changing providers.

## 7. App shell and theming

Dynamic theming driven by a preference provider:

```dart
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTheme = ref.watch(themeChoiceProvider);
    final colorScheme = appTheme.colorScheme;

    return MaterialApp(
      title: 'My App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
```

### Theme model

```dart
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.seed,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color seed;

  ColorScheme get colorScheme => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
}

const List<AppTheme> kAppThemes = [
  AppTheme(id: 'pastel', name: 'Atelier Pastel', brightness: Brightness.light, seed: Color(0xFFD88C8C)),
  AppTheme(id: 'slate', name: 'Deep Slate', brightness: Brightness.dark, seed: Color(0xFF4F46E5)),
  AppTheme(id: 'meadow', name: 'Meadow Amber', brightness: Brightness.light, seed: Color(0xFFD97706)),
  AppTheme(id: 'cyber', name: 'Cybernetic Shell', brightness: Brightness.dark, seed: Color(0xFF00F3FF)),
];
```

## 8. Responsive layouts

Use width breakpoints to switch between narrow (mobile) and wide (desktop/tablet) layouts.

```dart
class EditorScreen extends StatelessWidget {
  const EditorScreen({required this.slides, super.key});
  final List<Slide> slides;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        return isWide
            ? Row(
                children: [
                  Expanded(flex: 2, child: SlideViewer()),
                  Expanded(child: NotesPanel()),
                ],
              )
            : Column(
                children: [
                  Expanded(child: SlideViewer()),
                  Expanded(child: NotesPanel()),
                ],
              );
      },
    );
  }
}
```

**Rules:**
- `LayoutBuilder` for parent-relative breakpoints; `MediaQuery.sizeOf` for screen-relative.
- 800px is the standard wide/narrow threshold.
- Use `Expanded` with `flex` for proportional splits.
- Stack vertically on narrow; side-by-side on wide.
- Test both layouts.

## 9. Overlay and dialog patterns

### Full-screen blocking overlay

```dart
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.scrim.withValues(alpha: 0.7),
      alignment: Alignment.center,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Auto-dismissing error toast

```dart
class ErrorToast extends StatelessWidget {
  const ErrorToast({
    required this.message,
    required this.onDismiss,
    super.key,
  });
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Flexible(child: Text(message)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Stack overlays with `Positioned.fill` inside a `Stack`:

```dart
Stack(
  children: [
    // Main content
    Column(children: [NavBar(), Expanded(child: content)]),
    // Conditionally shown overlays
    if (isLoading) const Positioned.fill(child: LoadingOverlay(message: 'Working...')),
    if (error != null)
      Positioned(
        top: 16, left: 0, right: 0,
        child: ErrorToast(message: error!, onDismiss: dismissError),
      ),
  ],
)
```

## 10. File picking

Use `file_picker` for cross-platform file selection:

```dart
Future<void> pickFiles(WidgetRef ref) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    allowMultiple: true,
  );
  if (result == null || result.files.isEmpty) return;

  for (final file in result.files) {
    final bytes = file.bytes ??
        (file.path != null
            ? await File(file.path!).readAsBytes()
            : null);
    if (bytes == null) continue;

    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'pdf') {
      await ref.read(slidesProvider.notifier).importPdf(bytes);
    } else {
      await ref.read(slidesProvider.notifier).importImage(bytes);
    }
  }
}
```

**Rules:**
- `file.bytes` is populated on web; `file.path` on desktop/mobile.
- Handle both with a fallback chain.
- Validate extension before processing.

## 11. Heavy computation

Push CPU-intensive work off the main isolate:

```dart
/// Rasterise PDF pages with progress and cancellation support.
Future<List<Uint8List>> rasterisePdfToJpegs(
  Uint8List pdfBytes, {
  void Function(int current, int total)? onProgress,
  bool Function()? cancel,
}) async {
  final document = await PdfDocument.openData(pdfBytes);
  final pages = <Uint8List>[];

  try {
    final total = document.pagesCount;
    onProgress?.call(0, total);

    for (var i = 1; i <= total; i++) {
      if (cancel?.call() ?? false) break;
      final page = await document.getPage(i);
      try {
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          quality: 80,
        );
        if (image?.bytes != null) pages.add(image!.bytes);
      } finally {
        await page.close();
      }
      onProgress?.call(i, total);
      // Yield to event loop so UI can repaint
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    await document.close();
  }
  return pages;
}
```

For pure CPU work (image encoding, PCM processing), use `Isolate.run`:

```dart
final result = await Isolate.run(() => encodeJpegFitted(bytes));
```

**Rules:**
- Yield between iterations with `await Future.delayed(Duration.zero)`.
- Support cancellation via a callback predicate.
- Report progress via callbacks for UI overlays.
- `Isolate.run` for synchronous heavy functions; keep async I/O on the main isolate.

## 12. Testing

### Widget test with Riverpod overrides

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders app shell', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp()),
    );

    expect(find.text('My App'), findsOneWidget);
  });

  testWidgets('shows slides when loaded', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slidesProvider.overrideWith(() => MockSlides()),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(SlideViewer), findsOneWidget);
  });
}
```

### Unit test for repository

```dart
void main() {
  test('applyNotesUpdate clears stale audio', () {
    final slides = [
      Slide(id: '1', index: 0, imageFileName: 'a.jpg',
            audioFileName: 'a.wav'),
    ];
    final repo = SlideRepository(
      storage: MockStorage(),
      api: MockApi(),
    );

    final updated = repo.applyNotesUpdate(slides, '1', 'new notes');

    expect(updated.first.notes, 'new notes');
    expect(updated.first.audioFileName, isNull);
    expect(updated.first.status, SlideStatus.idle);
  });
}
```

**Rules:**
- Widget tests use `ProviderScope` with overrides for dependency injection.
- Test pure helpers (list transforms, data mapping) as plain unit tests.
- Use `pumpAndSettle` for async provider resolution.
- Integration tests use a real `ProviderScope` without overrides.

## 13. Code quality checklist

Review items specific to Pastel Flutter apps. These complement the general Dart rules.

### State management
- All providers use `@Riverpod` annotation with codegen — no hand-written `StateNotifierProvider`.
- `keepAlive: true` on singletons (services, repositories, core state).
- No business logic in widgets — delegate to notifier methods.
- `ref.watch()` only in `build()` methods; `ref.read()` in callbacks and notifier methods.
- `state.value` (not `valueOrNull`) on `AsyncValue` — handle null explicitly.
- `AsyncData<T>(value)` with explicit type parameter when setting state.

### Models
- All fields `final`. `const` constructors where possible.
- `copyWith` returns new instance — never mutate fields.
- JSON serialization with `fromJson` factory + `toJson` method.
- Enums with `values.byName()` for deserialization; provide a default fallback.

### Services
- One service per concern. Inject via constructor, not via global access.
- `ref.onDispose` for resource cleanup (Dio, AudioPlayer, streams).
- `flush: true` on all file writes.
- Defensive response parsing — never trust external API shapes.
- Timeouts on all network calls.

### UI
- Responsive layouts with breakpoint at 800px.
- `Theme.of(context).colorScheme` for all colors — never hardcode.
- Overlays stacked via `Positioned.fill` in a `Stack`.
- `Semantics` and labels on interactive widgets for accessibility.
- Trailing commas on all argument lists for clean diffs.

### Async
- No blocking I/O on the main isolate. Use `Isolate.run` for heavy CPU work.
- Cancellation support on long-running operations (PDF conversion, batch AI calls).
- Progress callbacks for operations >1 second.
- Dispose subscriptions and controllers in `dispose()` or `ref.onDispose`.

### Security
- No hardcoded API keys. Supply via `--dart-define` or env loader.
- `.env` in `.gitignore`.
- API keys held in memory only — never persisted to disk.

### Formatting and analysis
- `dart format` with two-space indent, trailing commas.
- `flutter analyze` with `very_good_analysis` — zero errors, zero warnings.
- Generated files (`*.g.dart`, `*.freezed.dart`) excluded from analysis.
- Absolute package imports — never relative.

## pubspec.yaml essentials

```yaml
environment:
  sdk: ^3.11.0

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.3.0
  riverpod_annotation: ^4.0.0
  dio: ^5.9.0
  pretty_dio_logger: ^1.4.0
  path_provider: ^2.1.0
  shared_preferences: ^2.5.0
  file_picker: ^11.0.0
  uuid: ^4.5.0
  image: ^4.8.0          # When image processing needed
  just_audio: ^0.10.0    # When audio playback needed
  pdfx: ^2.9.0           # When PDF rendering needed

dev_dependencies:
  build_runner: ^2.15.0
  riverpod_generator: ^4.0.0
  very_good_analysis: ^10.2.0
  flutter_test:
    sdk: flutter
```

## 14. Typography — dual-font system

Pastel apps use a dual-font system: a **serif** face for headings and large numeric values, and a **sans-serif** face for body text, labels, and UI controls. Use `google_fonts` to load both families and wire them into `ThemeData.textTheme`.

### TextTheme setup

Build the Material `TextTheme` with the sans font as the base layer, then override `display*` and `headline*` roles with the serif font:

```dart
import 'package:google_fonts/google_fonts.dart';

static TextTheme textTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? ThemeData.dark().textTheme
      : ThemeData.light().textTheme;

  final sansTheme = GoogleFonts.instrumentSansTextTheme(base);

  return sansTheme.copyWith(
    // Serif for display/headline
    displayLarge: GoogleFonts.newsreader(
      textStyle: sansTheme.displayLarge,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.5,
      height: 0.92,
    ),
    headlineLarge: GoogleFonts.newsreader(
      textStyle: sansTheme.headlineLarge,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      height: 1.1,
    ),
    // Title stays sans but tightened
    titleLarge: sansTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    // Body stays sans with generous line height
    bodyLarge: sansTheme.bodyLarge?.copyWith(
      height: 1.65,
      letterSpacing: 0,
    ),
    // Labels: bold, tracked, for uppercase micro-labels
    labelMedium: sansTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      fontSize: 11,
    ),
  );
}
```

Wire into `ThemeData`:

```dart
ThemeData(
  colorScheme: colorScheme,
  textTheme: SvTypography.textTheme(colorScheme.brightness),
  useMaterial3: true,
)
```

### Semantic style helper class

For fine-grained control beyond the Material `TextTheme` roles, create a static helper class with named methods per visual context. Each method takes `BuildContext` to resolve theme colors and responsive breakpoints.

```dart
class AppTypography {
  AppTypography._();

  /// Hero headline: large serif, tight leading.
  static TextStyle heroHeadline(BuildContext context) =>
      GoogleFonts.newsreader(
        fontSize: _isWide(context) ? 56 : 40,
        fontWeight: FontWeight.w700,
        letterSpacing: _isWide(context) ? -2.8 : -2.0,
        height: 0.92,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Brand title: app name in serif.
  static TextStyle brandTitle(BuildContext context) =>
      GoogleFonts.newsreader(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Brand subtitle: uppercase tracked sans.
  static TextStyle brandSubtitle(BuildContext context) =>
      GoogleFonts.instrumentSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  /// Section header: tiny uppercase tracked label.
  static TextStyle sectionHeader(BuildContext context) =>
      GoogleFonts.instrumentSans(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  /// Badge/pill text: small uppercase with wide tracking.
  static TextStyle badgePill(BuildContext context) =>
      GoogleFonts.instrumentSans(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 3.1,
      );

  /// Stat card value: large serif number.
  static TextStyle statValue(BuildContext context) =>
      GoogleFonts.newsreader(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Monospace input (API keys, code).
  static TextStyle monoInput(BuildContext context) =>
      GoogleFonts.jetBrainsMono(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static bool _isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 800;
}
```

**Rules:**
- Serif for headings and large numbers; sans for everything else.
- Tight negative letter-spacing on headings (`-0.3em` to `-0.05em`).
- Generous line height on body text (`1.5` – `1.75`).
- Wide positive letter-spacing on uppercase labels (`1.2` – `3.5`).
- All colors from `Theme.of(context).colorScheme` — never hardcode.
- Responsive font sizes via `_isWide(context)` helper (800px breakpoint).
- Keep all font definitions in one file (`lib/ui/typography.dart`).
- Add `google_fonts` to `pubspec.yaml` dependencies.

## analysis_options.yaml

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    public_member_api_docs: false
```
