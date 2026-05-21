# Swift/SwiftUI App Patterns — Reference

Battle-tested patterns for Pastel Sketchbook Swift apps — copy, adapt, do **not** reinvent.

## 1. Project structure

SwiftPM executable target. Thin `App.swift` entry wires DI. Logic lives in layers.

```
Sources/
  MyApp/
    App.swift              # @main App entrypoint, DI wiring
    Models/                # Codable value types
    Adapters/              # Protocol definitions (ports)
    Services/              # Concrete adapter implementations
    Repositories/          # Coordinate services, pure transforms
    State/                 # @Observable view models (@MainActor)
    UI/                    # SwiftUI views, screens, theming
    Utils/                 # Misc helpers
    Resources/             # Bundled assets
    Info.plist             # Excluded from target, used by run script
Tests/
  MyAppTests/
Package.swift
Taskfile.yml
VERSION
scripts/
```

Keep `App.swift` minimal — just DI wiring:

```swift
import SwiftUI

@main
struct MyApp: App {
  // Concrete services (adapters)
  private let storageService = StorageService()
  private let apiService = APIService()

  // Repository wired with adapters
  private let repository: AppRepository

  // View models
  @State private var mainVM: MainViewModel

  init() {
    let repo = AppRepository(storage: storageService, api: apiService)
    repository = repo
    _mainVM = State(wrappedValue: MainViewModel(repository: repo))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(mainVM)
        .frame(minWidth: 900, minHeight: 600)
        .task { await mainVM.load() }
    }
    #if os(macOS)
    .defaultSize(width: 1200, height: 800)
    #endif
  }
}
```

## 2. Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .executable(name: "MyApp", targets: ["MyApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            path: "Sources/MyApp",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MyAppTests",
            dependencies: ["MyApp"],
            path: "Tests/MyAppTests"
        ),
    ]
)
```

## 3. Models — immutable structs with copyWith

Use value types. Implement `copyWith` using double-optional (`T??`) for nullable fields so callers can explicitly set `nil`.

```swift
import Foundation

public struct Item: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let index: Int
    public var title: String
    public var status: ItemStatus
    public var metadata: String?

    public init(
        id: String,
        index: Int,
        title: String,
        status: ItemStatus = .idle,
        metadata: String? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.status = status
        self.metadata = metadata
    }

    /// Double-optional allows distinguishing "not provided" from "set to nil".
    public func copyWith(
        title: String? = nil,
        status: ItemStatus? = nil,
        metadata: String?? = nil  // T?? pattern
    ) -> Item {
        Item(
            id: id,
            index: index,
            title: title ?? self.title,
            status: status ?? self.status,
            metadata: metadata ?? self.metadata
        )
    }
}

public enum ItemStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case processing
    case ready
    case error
}
```

### Custom Codable for resilient decoding

```swift
public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    index = try c.decode(Int.self, forKey: .index)
    title = (try? c.decode(String.self, forKey: .title)) ?? ""
    let statusName = (try? c.decode(String.self, forKey: .status)) ?? ItemStatus.idle.rawValue
    status = ItemStatus(rawValue: statusName) ?? .idle
    metadata = try? c.decode(String.self, forKey: .metadata)
}
```

## 4. Adapters — protocol-based ports

Define protocols for each external boundary. Services implement them. Repository depends only on protocols.

```swift
import Foundation

/// Storage port — file system operations.
public protocol StorageAdapter: Sendable {
    func loadItems() async throws -> [Item]
    func saveItems(_ items: [Item]) async throws
    func writeFile(_ name: String, bytes: Data) async throws
    func deleteFile(at path: String) async throws
    func filePath(_ name: String) async throws -> String
    func clear() async throws
}

/// External API port.
public protocol APIAdapter: Sendable {
    func fetchData(input: Data, apiKey: String) async throws -> String
    func generateAudio(text: String, apiKey: String) async throws -> Data
}
```

## 5. Services — concrete implementations

Mark `@unchecked Sendable` when internal state is thread-safe (e.g. URLSession).

```swift
import Foundation

public final class APIService: APIAdapter, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchData(input: Data, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "contents": [["parts": [["data": input.base64EncodedString()]]]]
        ]
        let data = try await post(path: "models/gemini:generateContent", apiKey: apiKey, body: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return extractText(json) ?? ""
    }

    private func post(path: String, apiKey: String, body: [String: Any]) async throws -> Data {
        var components = URLComponents(string: "https://api.example.com/v1/\(path)")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.httpError(statusCode: http.statusCode)
        }
        return data
    }
}

/// Typed error enum for the service.
public enum ServiceError: Error, LocalizedError {
    case httpError(statusCode: Int)
    case noData
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .httpError(let code): return "API error: \(code)"
        case .noData: return "No data returned."
        case .emptyInput: return "Input is empty."
        }
    }
}
```

## 6. Repository — coordination and pure transforms

The repository coordinates services and provides pure list-transform functions for state updates.

```swift
import Foundation

public final class AppRepository: @unchecked Sendable {
    private let storage: StorageAdapter
    private let api: APIAdapter

    public init(storage: StorageAdapter, api: APIAdapter) {
        self.storage = storage
        self.api = api
    }

    // MARK: - Persistence delegation

    public func loadItems() async throws -> [Item] {
        try await storage.loadItems()
    }

    public func saveItems(_ items: [Item]) async throws {
        try await storage.saveItems(items)
    }

    // MARK: - Orchestrated operations

    public func processItem(_ item: Item, apiKey: String) async throws -> String {
        let path = try await storage.filePath(item.title)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        return try await api.fetchData(input: bytes, apiKey: apiKey)
    }

    // MARK: - Pure list transforms (no side effects)

    public func applyStatus(_ items: [Item], itemId: String, status: ItemStatus) -> [Item] {
        items.map { i in
            guard i.id == itemId else { return i }
            return i.copyWith(status: status)
        }
    }

    public func applyUpdate(_ items: [Item], itemId: String, title: String) -> [Item] {
        items.map { i in
            guard i.id == itemId else { return i }
            return i.copyWith(title: title, status: .idle, metadata: .some(nil))
        }
    }
}
```

## 7. View Models — @Observable + @MainActor

Single source of truth for UI state. All mutations go through the view model. Use `public private(set)` for read-only published state.

```swift
import Foundation
import SwiftUI

@MainActor
@Observable
public final class MainViewModel {
    // MARK: - Published State
    public private(set) var items: [Item] = []
    public private(set) var isLoading = false
    public private(set) var error: String?
    public var apiKey: String = ""
    public var currentIndex: Int = 0 {
        didSet { navigationForward = currentIndex >= oldValue }
    }
    public private(set) var navigationForward: Bool = true

    // MARK: - Dependencies
    public let repository: AppRepository
    private var importTask: Task<Void, Never>?

    public init(repository: AppRepository) {
        self.repository = repository
    }

    // MARK: - Lifecycle

    public func load() async {
        do {
            var loaded = try await repository.loadItems()
            // Sanitize stale processing states from interrupted sessions
            loaded = loaded.map { item in
                guard item.status == .processing else { return item }
                return item.copyWith(status: .idle)
            }
            items = loaded
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Operations

    public func processItem(itemId: String) async {
        guard !apiKey.isEmpty else {
            error = "API key required."
            return
        }
        guard let item = items.first(where: { $0.id == itemId }) else { return }

        items = repository.applyStatus(items, itemId: itemId, status: .processing)
        do {
            let result = try await repository.processItem(item, apiKey: apiKey)
            items = items.map { i in
                guard i.id == itemId else { return i }
                return i.copyWith(title: result, status: .ready)
            }
            try await repository.saveItems(items)
        } catch {
            items = repository.applyStatus(items, itemId: itemId, status: .error)
            self.error = error.localizedDescription
        }
    }

    // MARK: - Cancellable import

    public func importData(_ data: Data) {
        importTask?.cancel()
        importTask = Task {
            isLoading = true
            do {
                // ... heavy work with Task.isCancelled checks
                try await repository.saveItems(items)
            } catch is CancellationError {
                // user cancelled — no error
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    public func cancelImport() {
        importTask?.cancel()
        importTask = nil
    }

    public func dismissError() {
        error = nil
    }
}
```

## 8. Environment-based Dependency Injection

Pass view models via SwiftUI Environment. No singletons, no global state.

```swift
// At root:
ContentView()
    .environment(mainVM)
    .environment(preferences)

// In child views:
struct ChildView: View {
    @Environment(MainViewModel.self) private var mainVM

    var body: some View {
        let items = mainVM.items
        // ...
    }
}
```

### Custom Environment keys for non-class values

```swift
struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = defaultTheme
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
    }
}
```

## 9. SwiftUI transitions and animations

Use `.id()` to trigger view identity changes, `.transition()` for the effect, and `withAnimation` at the call site.

```swift
// Call site — wrap index change with animation:
Button("Next") {
    withAnimation(.easeInOut(duration: 0.42)) {
        viewModel.currentIndex += 1
    }
}

// View — apply transition based on type:
Group {
    Image(nsImage: image)
        .resizable()
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
}
.id(currentItem.id)  // identity change triggers transition
.transition(transitionForType(currentItem.transition))
.animation(.easeInOut(duration: 0.42), value: currentItem.id)
```

### Custom transitions

```swift
func transitionForType(_ type: TransitionType, forward: Bool) -> AnyTransition {
    switch type {
    case .none:   return .identity
    case .fade:   return .opacity
    case .slide:
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        )
    case .wipe:
        return .asymmetric(
            insertion: .modifier(
                active: WipeModifier(progress: 0, fromLeading: forward),
                identity: WipeModifier(progress: 1, fromLeading: forward)
            ),
            removal: .opacity
        )
    case .zoom:
        return .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 1.04).combined(with: .opacity)
        )
    }
}

/// Wipe: animatable clip from one edge.
struct WipeModifier: ViewModifier {
    let progress: CGFloat
    let fromLeading: Bool
    func body(content: Content) -> some View {
        content.clipShape(WipeShape(progress: progress, fromLeading: fromLeading))
    }
}

struct WipeShape: Shape {
    var progress: CGFloat
    let fromLeading: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let width = rect.width * progress
        let x = fromLeading ? 0 : rect.width - width
        return Path(CGRect(x: x, y: 0, width: width, height: rect.height))
    }
}
```

## 10. Overlay badges (not ZStack children)

Use `.overlay(alignment:)` for status badges. ZStack children get clipped by parent `clipShape`; overlays render above.

```swift
ThumbnailView(item: item)
    .frame(width: 100, height: 82)
    .cornerRadius(8)
    .overlay(alignment: .bottomTrailing) {
        if item.isReady {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(2)
        }
    }
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? theme.seed : theme.border, lineWidth: isActive ? 2 : 0.6)
    )
```

## 11. Local persistence with FileManager + JSON

Simple JSON file persistence. No Core Data or SwiftData unless schema relationships demand it.

```swift
public final class StorageService: StorageAdapter, @unchecked Sendable {
    public init() {}

    private func appDir() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("myapp", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func saveItems(_ items: [Item]) async throws {
        let path = try appDir().appendingPathComponent("data.json").path
        let data = try JSONEncoder().encode(items)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public func loadItems() async throws -> [Item] {
        let path = try appDir().appendingPathComponent("data.json").path
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([Item].self, from: data)
    }
}
```

## 12. TextEditor with model sync (avoid feedback loops)

When a `TextEditor` is bound to model state updated by both user edits and programmatic changes (e.g. AI generation), use a guard flag to prevent feedback loops.

```swift
@State private var text: String = ""
@State private var isSyncing = false

var body: some View {
    TextEditor(text: Binding(
        get: { text },
        set: { newValue in
            text = newValue
            guard !isSyncing else { return }
            Task { await viewModel.updateText(itemId: item.id, text: newValue) }
        }
    ))
    .onAppear {
        isSyncing = true
        text = item.content
        isSyncing = false
    }
    .onChange(of: item.content) { _, newVal in
        if text != newVal {
            isSyncing = true
            text = newVal
            isSyncing = false
        }
    }
}
```

## 13. Error handling pattern

Typed error enums per service. View model catches and surfaces user-facing messages.

```swift
// Service layer:
public enum MyError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String?)
    case noData
    case invalidInput

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "API error \(code): \(body ?? "unknown")"
        case .noData: return "No data returned."
        case .invalidInput: return "Invalid input."
        }
    }
}

// View model layer:
do {
    let result = try await repository.doWork(item, apiKey: apiKey)
    items = applyResult(items, itemId: itemId, result: result)
    try await repository.saveItems(items)
} catch {
    items = repository.applyStatus(items, itemId: itemId, status: .error)
    self.error = error.localizedDescription
}
```

## 14. macOS app bundle with SwiftPM

SwiftPM produces a CLI binary. Use a script to wrap it in a `.app` bundle for Dock icon and window focus.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sync VERSION from root into resources
cp VERSION Sources/MyApp/Resources/VERSION

swift build

APP="build/MyApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/MyApp "$APP/Contents/MacOS/"
cp Sources/MyApp/Info.plist "$APP/Contents/"
# Copy .icns if available
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true

open "$APP"
```

## 15. Taskfile.yml conventions

Taskfile is a thin wrapper. Complex logic lives in `scripts/`.

```yaml
version: "3"
tasks:
  default:
    desc: List available tasks
    cmds: [task --list]

  build:
    desc: Build release
    cmds:
      - cp VERSION Sources/MyApp/Resources/VERSION
      - swift build -c release

  run:
    desc: Run as macOS .app bundle
    cmds:
      - ./scripts/run-macos.sh

  test:unit:
    desc: Run unit tests
    cmds:
      - swift test

  format:
    desc: Format Swift code
    cmds:
      - swift-format format -i -r Sources/ Tests/

  lint:
    desc: Lint Swift code
    cmds:
      - swift-format lint -r Sources/ Tests/

  loc:
    desc: Count lines of code
    cmds:
      - tokei Sources/
```
