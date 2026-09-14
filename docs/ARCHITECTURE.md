# DuckMD — Архитектура (ARCHITECTURE)

> Детали реализации: стек, слои, модели данных, структура файлов, паттерны.
> Требования см. в `SPEC.md`, экраны — в `UX.md`, статус реализации — в `CHANGELOG.md`.

---

## 1. Технологические решения и обоснование

| Решение | Выбор | Почему |
|---|---|---|
| UI-фреймворк | **SwiftUI** (хром/тулбары) + **WKWebView** (рендер Markdown-превью), macOS 26+ | SwiftUI — декларативная оболочка; единственный рендер Markdown — WKWebView c HTML из `MarkdownToHTML` (исторический SwiftUI-рендер на `Text`/`AttributedString` удалён — ADR D-22 в `docs/DECISIONS.md`; ранее хранился в `archive/dead-swift-render/`, каталог удалён) |
| Документная модель | **`ReferenceFileDocument`** (`MarkdownDocument`) + единый контейнер `MainContainerView` в окне `main` | Факт v0.6.15: `DocumentGroup` НЕ используется; хаб и документ — состояния одного окна `main` (`AppState.showHub`/`activeDocument`), мгновенное открытие через `pendingOpenURL`/`flushPendingOpenURL` |
| Markdown-парсер | **swift-markdown** (Apple, cmark-gfm) | Официальная либа Apple, GFM из коробки (таблицы, зачёркивание, todo), умные кавычки, активно поддерживается |
| Рендер форматированного текста | **WKWebView** (`loadHTMLString(html, baseURL: docDir)`) + `PreviewBridgeScript` | Полный контроль HTML/CSS без конфликтов дескрипторов песочницы WebKit; тот же HTML идёт и в превью (`OutputMode.preview`), и в экспорт (`OutputMode.export`) |
| Редактор кода | **`NSTextView`** (через `NSViewRepresentable`) | SwiftUI `TextEditor` не поддерживает attributed text/подсветку; NSTextView — единственный надёжный путь |
| Подсветка синтаксиса | Собственный `MarkdownHighlighter` (regex по строкам) | Без тяжёлых зависимостей, достаточно для MD; позже можно Highlightr |
| Автоформатирование | **`MarkdownAutoFormatter`** (`NSTextViewDelegate`) | Перехват клавиш → умные правки (списки, пары, заголовки) |
| Конвертеры | `ConverterService` (Foundation/AppKit/PDFKit) | Собственная реализация без swift-docx/Demark; единственная SPM-зависимость проекта — swift-markdown |
| Мониторинг файлов | **`DispatchSource.makeFileSystemObjectSource`** | Нативный FSEvents-враппер, лёгкий, потокобезопасный |
| Настройки | **`@AppStorage`** / `UserDefaults` | Встроенный реактивный persistence SwiftUI |
| Сборка проекта | **`xcodegen`** (`project.yml`) + `xcodebuild` | Воспроизводимая генерация `.xcodeproj` из манифеста; чистый git-flow |
| Иконка | **Swift Core Graphics** скрипт → PNG | Векторный источник, масштабируется; позже заменить на финальный дизайн |

> **Кроссплатформенность** НЕ цель. Для Windows/Linux в будущем — отдельные нативные проекты (WinUI / GTK), не единый кодбейз. Осознанный выбор ради скорости и «вкуса» на каждой ОС.

---

## 2. Архитектурные слои

```
┌─────────────────────────────────────────────────────────┐
│  Presentation (SwiftUI Views)                            │
│  HubView · ContentView · Settings · Converter            │
│  WebPreviewView (WKWebView) · CodeEditorView · DuckLogo  │
├─────────────────────────────────────────────────────────┤
│  State / App Coordination                                │
│  AppState · SettingsStore · RecentFilesStore             │
│  FileWatcherService                                      │
├─────────────────────────────────────────────────────────┤
│  Domain Models                                           │
│  MarkdownDocument · MarkdownBlock/Inline · EditorMode    │
├─────────────────────────────────────────────────────────┤
│  Services (Parsing · Editing · Conversion · App)         │
│  MarkdownParser · MarkdownToHTML (OutputMode)            │
│  MarkdownHighlighter · TextEditApplier · MarkdownAutoFmt │
│  DocumentFileService · DocumentDropHelper · FileWatcher  │
│  Converters (Txt/Rtf/Html/Docx/Pdf → MD)                 │
├─────────────────────────────────────────────────────────┤
│  Platform / External                                     │
│  swift-markdown · WebKit (WKWebView) · PDFKit · AppKit   │
└─────────────────────────────────────────────────────────┘
```

**Принципы:**
- **Однонаправленный поток данных**: View → Action → mutate State → View обновляется.
- **Единый источник правды** для документа — `MarkdownDocument.text` (`@Published`). Рендер и редактор оба слушают его.
- **Парсер изолирован от рендера**: `swift-markdown` AST → типобезопасные `MarkdownBlock`/`MarkdownInline` → SwiftUI. Сменить парсер можно, не трогая вью.
- **Слабая связность**: View-шки зависят от моделей и services через протоколы/простые типы, не от реализации.

---

## 3. Модели данных (Domain)

### 3.1. Документ

```swift
final class MarkdownDocument: ObservableObject, ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.markdownDoc, .markdownStandard, .plainText] }
    typealias Snapshot = String                          // Sendable снимок для сохранения
    @Published var text: String                          // единый источник правды

    init(text: String = "")
    required init(configuration: ReadConfiguration) throws
    func snapshot(contentType: UTType) throws -> String
    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper
}
```

**Ключевое:** `ReferenceFileDocument` (не `FileDocument`) — даёт ссылочную семантику: несколько окон одного файла разделяют один объект, правки в одном видны в другом.

### 3.2. AST-блоки (результат парсинга)

```swift
indirect enum MarkdownBlock {
    case heading(level: Int, inline: [MarkdownInline])
    case paragraph([MarkdownInline])
    case blockquote([MarkdownBlock])
    case bulletList(items: [[MarkdownBlock]])
    case orderedList(items: [[MarkdownBlock]], start: Int)
    case code(language: String?, content: String)
    case thematicBreak
    case table(header: [[MarkdownInline]], rows: [[[MarkdownInline]]], alignments: [TableColumnAlignment])
    case html(content: String)
}

enum MarkdownInline {
    case text(String) | strong([MarkdownInline]) | emphasis([MarkdownInline])
    case code(String) | link(text:url:title:) | image(alt:url:title:)
    case softBreak | lineBreak | strikethrough([MarkdownInline])
}

enum TableColumnAlignment { case none, left, center, right }
```

> **Замечание для реализации:** `swift-markdown`'s `List` не имеет публичного `isTight` — `tight` убран из модели (влияло только на вертикальные отступы). `Image` имеет `.source`, не `.destination`. `Table.ColumnAlignment?` — опциональный (нет `.none`, это `Optional.none`).

### 3.3. Режимы и состояние

```swift
final class AppState: ObservableObject {
    @Published var prefersDark: Bool?
    @Published var readingWidth: CGFloat = 720
    @Published var editorMode: EditorMode = .rendered
    @Published var splitRatio: CGFloat = 0.5
}

enum EditorMode: String, CaseIterable, Identifiable {
    case rendered   // Просмотр  ⌘1
    case split      // Правка    ⌘2  (код + живой рендер)
    case code       // Код       ⌘3
}
```

### 3.4. Хаб: недавние файлы (реализовано; персист sortOption — R-HUB-8)

```swift
struct RecentFile: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    var bookmarkData: Data          // security-scoped bookmark (для песочницы)
    var lastOpened: Date
    var lastModified: Date
    var title: String               // кешированный заголовок (первая строка/заголовок)
    var preview: String             // кешированное превью (первые ~200 символов рендера)
    var wordCount: Int
}

final class RecentFilesStore: ObservableObject {
    @Published var files: [RecentFile] = []
    @Published var sortOption: SortOption = .lastOpened
    @Published var searchText: String = ""
    // persistence в UserDefaults / JSON в Application Support
}

enum SortOption: String, CaseIterable { case lastOpened, lastModified, name, size }
```

### 3.5. Настройки (реализовано; `extChangeTimerSeconds`, `maxRecentFiles`, персист sortOption)

```swift
final class SettingsStore: ObservableObject {
    // Внешний вид
    @AppStorage("theme") var theme: ThemeMode = .system
    @AppStorage("readingWidth") var readingWidth: Double = 720
    @AppStorage("bodyFontDesign") var bodyFontDesign: String = "serif"
    // Редактор
    @AppStorage("autoformatEnabled") var autoformatEnabled: Bool = true
    @AppStorage("autoClosePairs") var autoClosePairs: Bool = true
    @AppStorage("editorFontSize") var editorFontSize: Double = 13
    // Файлы
    @AppStorage("autosaveEnabled") var autosaveEnabled: Bool = true
    @AppStorage("extChangeTimer") var extChangeTimer: Double = 5
    @AppStorage("maxRecentFiles") var maxRecentFiles: Int = 50
}

enum ThemeMode: String, CaseIterable { case system, light, dark }
```

---

## 4. Структура проекта (фактическая, v0.6.15)

```
DuckMD/
├── project.yml                      # xcodegen манифест: v0.6.15 (MARKETING_VERSION — единый источник версии → CFBundleShortVersionString), таргеты DuckMD + DuckMDTests, схема с test-экшеном
├── docs/                            # документация
│   ├── SPEC.md · ARCHITECTURE.md · UX.md · DECISIONS.md
├── CHANGELOG.md                     # журнал изменений проекта
├── scripts/
│   ├── build-release.sh             # релизная сборка + инструкция notarization [Этап 2]
│   ├── build-test-dmg.sh            # локальный тестовый DMG (Apple Development/ad-hoc, versioned naming; НЕ Developer ID/notarization) — см. §10.1
│   ├── export-diagnostics.sh        # экспорт логов Unified Logging (public/private-режимы) [G-DIAG]
│   └── generate_icon.swift          # генерация иконки macOS AppIcon с low-poly уточкой (PNG 1024)
├── security/
│   └── DuckMD.entitlements          # минимальные entitlements, без sandbox (решение владельца: без MAS) [Этап 2]
├── DuckMD/
│   ├── DuckMDApp.swift              # @main, Window("DuckMD", id: "main") + MainContainerView (хаб/документ-состояния) + Settings scene; DocumentGroup/HubWindow НЕ используются
│   ├── Info.plist                   # CFBundleShortVersionString = $(MARKETING_VERSION)
│   ├── Assets.xcassets/             # AppIcon (1024x1024 squircle), DuckLogo.imageset, AccentColor (#FFC800)
│   ├── App/
│   │   ├── AppState.swift            # EditorMode, глобальный state
│   │   ├── SettingsStore.swift       # @AppStorage: autosaveEnabled, maxRecentFiles, extChangeTimerSeconds, autoSaveInterval…
│   │   ├── RecentFilesStore.swift    # недавние хаба; applyingLimit (R10); персист sortOption в UserDefaults (R-HUB-8)
│   │   ├── FileWatcherService.swift  # FSEvents-мониторинг; restartWatch после delete/rename [Этап 1]; onDeleted + токен подавления собственных записей [hardening 2026-09-13]
│   │   ├── DocumentFileService.swift # файловый I/O: чтение, атомарная запись, rename, autosave debounce 1.0s [R6]; serial ioQueue, DocumentFileError (invalidUTF8/writeFailed/invalidFileName), isWriteSuspended, окно подавления 1.5с, validatedRename [hardening 2026-09-13]
│   │   ├── DocumentDropHelper.swift  # drag&drop → appState.openDocument [Этап 1]
│   │   └── AppIconHelper.swift
│   ├── Models/
│   │   └── MarkdownDocument.swift    # ReferenceFileDocument + UTType; чист от SettingsStore; parseGeneration (фоновый парсинг больших документов ≥256 КБ/4000 строк, stale-guard) [Этап 3]
│   ├── Parsing/
│   │   ├── MarkdownBlock.swift       # AST enum'ы
│   │   ├── MarkdownParser.swift      # swift-markdown → блоки
│   │   └── MarkdownToHTML.swift      # блоки → HTML; OutputMode (.preview / .export) [R3]
│   ├── Editing/
│   │   ├── MarkdownAutoFormat.swift  # NSTextViewDelegate автоформатирование
│   │   ├── MarkdownHighlighter.swift # regex-подсветка синтаксиса [R3]
│   │   ├── RenderEditParser.swift    # правки из превью → исходник (RenderEditParserTests)
│   │   └── TextEditApplier.swift     # применение правок к тексту документа [R3]
│   ├── Conversion/
│   │   └── ConverterService.swift    # конвертация → MD (единый сервис; Foundation/AppKit/PDFKit); лимиты 50 МБ / 200 стр. PDF, pre-check до парсинга [Этап 2]
│   ├── Views/
│   │   ├── ContentView.swift         # документ: 3 режима; валидация webview-payload [Этап 0]; очередь pendingExternalTexts, handleFileDeleted/showUnreadableFileAlert, verifyDiskContent, алерты ошибок записи [hardening 2026-09-13]
│   │   ├── WebPreviewView.swift      # NSViewRepresentable над WKWebView (единственный рендер); decidePolicyFor: allowlist навигаций, http/https → системный браузер [Этап 2]
│   │   ├── CodeEditorView.swift      # NSViewRepresentable NSTextView; dismantleNSView [Этап 1]
│   │   ├── SplitEditorView.swift     # split-режим, скролл-синк
│   │   ├── HubView.swift             # хаб: недавние, «Новый», «Конвертировать»
│   │   ├── HubCardView.swift         # карточка файла
│   │   ├── SettingsView.swift        # окно настроек
│   │   ├── ConverterView.swift       # UI конвертации
│   │   ├── AboutView.swift           # о программе, версия из Bundle (0.6.15; единый источник — MARKETING_VERSION в project.yml → CFBundleShortVersionString)
│   │   ├── MarkdownGuideView.swift   # справочник Markdown
│   │   ├── ExtChangeBanner.swift     # баннер внешнего изменения (extChangeTimerSeconds)
│   │   └── Components/
│   │       ├── DuckLogo.swift            # low-poly уточка через ассет DuckLogo.imageset
│   │       ├── LineNumberRulerView.swift # номера строк редактора [R3]
│   │       ├── WebPreviewFactory.swift   # фабрика/настройка WKWebView [R3]
│   │       ├── PreviewBridgeScript.swift # JS-бридж: PreviewMessageHandlerName + Codable-payload [R7]
│   │       ├── PDFExporter.swift         # экспорт в PDF без утечек [R3]
│   │       └── WindowSupport.swift       # close-interceptor и оконная логика [R3]
│   └── Theme/
│       └── HTMLThemeResolver.swift   # HTMLTheme.resolved() — единственная точка Models↔настройки [R3]
├── DuckMDTests/                     # тест-таргет DuckMDTests (XCTest): 131 тест [hardening + security-превью + производительность 2026-09-13] — TEST SUCCEEDED (прогон релизного аудита, static count совпадает, см. §6); вкл. DocumentAssociationAndThemeTests (ассоциация/UTType, темы), ParseGenerationTests (generation-guard, пороги больших документов, кэш regex)
└── DuckMD.xcodeproj/                # генерируется xcodegen из project.yml
```

> SwiftUI-рендер (RenderedMarkdownView/MarkdownInlineRenderer/MarkdownTheme/InlineEditableText) удалён из таргета (ADR D-22 в `DECISIONS.md`); ранее хранился в `archive/dead-swift-render/`, каталог полностью удалён.

---

## 5. Поток данных: ключевые сценарии

### 5.1. Запуск приложения и показ Хаба (факт v0.6.15: единый контейнер)
```
Запуск DuckMD → macOS launcher → DuckMDApp
  → Единственное окно Window("DuckMD", id: "main") с MainContainerView
  → AppDelegate.applicationShouldOpenUntitledFile() перехватывает запуск
  → Выставляет UserDefaults для отключения стандартной панели Finder
  → Возвращает false (SwiftUI не открывает пустой документ)
  → AppState.showHub = true → MainContainerView показывает HubView-состояние
  → Отдельного HubWindow / openWindow(id: "hub") / DocumentGroup НЕТ (исторические упоминания HubWindow в доках = то же хаб-состояние единого окна main)
```

### 5.2. Открытие документа из Хаба или Finder (факт v0.6.15: то же окно main)
```
Клик на файл в Хабе / Двойной клик на файл в Finder
  → AppDelegate.openIncoming(url:) → буфер pendingOpenURL при холодном старте → flushPendingOpenURL() после привязки appState
  → appState.openDocument(at:) → activeDocument + activeFileURL установлены, showHub = false
  → MainContainerView в том же окне main переключается HubView → ContentView (.opacity 0.18s)
  → Кнопка «← Хаб» возвращает showHub = true без закрытия окна; NSDocumentController/DocumentGroup/window.close() НЕ используются
```

### 5.3. Предупреждение при закрытии окна (Close Interceptor)
```
Нажатие на кнопку закрытия (крестик) окна ContentView
  → Если автосохранение включено: окно закрывается штатно (изменения сохранены).
  → Если автосохранение выключено:
     → WindowCloseInterceptor перехватывает клик по standardWindowButton(.closeButton)
     → Проверяется: document.text != lastSavedText (наличие несохраненных изменений)
     → Если изменений нет: окно закрывается
     → Если изменения есть: выводится нативный NSAlert ("Сохранить" / "Отмена" / "Не сохранять")
        → "Сохранить": вызывает saveDocument() и закрывает окно
        → "Не сохранять": сбрасывает проверку изменений и закрывает окно
        → "Отмена": прерывает событие закрытия, окно остается открытым
```

### 5.4. Автоматическая конвертация и импорт
```
Файл перетаскивается в окно Конвертера
  → ConverterService.convert(url) запускается в фоновом потоке
  → Текст конвертируется в Markdown
  → Файл автоматически сохраняется в папку по умолчанию (~/Documents/DuckMD)
  → Если имя файла занято, генерируется имя "Имя (1).md", "Имя (2).md" и т.д.
  → Вызывается NSDocumentController.shared.openDocument(withContentsOf: targetURL)
  → Открывается окно редактора DuckMD
  → Окно Конвертера закрывается автоматически
```

### 5.5. Умный центрированный синхронный скролл (Smart Centered Sync Scroll)
В версии **0.6.6** механизм синхронизации скролла полностью переработан. Простая интерполяция глобальной доли скролла (`scrollY / maxScroll`) приводила к рассинхронизации, когда блоки кода, списки или таблицы имели разную высоту в коде и в HTML-рендере.

**Принципы Smart Centered Sync Scroll:**
1. **Привязка к оптическому центру (`midY`):**
   - Вычисляется блок, пересекающий горизонтальную осевую линию видимой области (`viewport.midY`).
   - Для блока берётся номер исходной строки Markdown (`data-source-line` в HTML, номер строки в `NSTextView`) и относительное смещение внутри блока `offsetInLine` (0.0..1.0).
2. **Адаптивная скорость (heterogeneous heights):**
   - Блоки разной высоты скроллятся с разной скоростью: редактор пролистывает блок кода медленнее или быстрее рендера так, чтобы текущая точка фокуса удерживалась по центру экрана.
3. **Жёсткая краевая доводка:**
   - Вблизи верха ($y \le 0.005$) обе панели гарантированно переходят в $y = 0$.
   - Вблизи низа ($y \ge 0.995$) обе панели гарантированно переходят в максимальное положение без обрезания нижних строк.
4. **Подавление эха (`isProgrammaticScroll`):**
```
1. Редактор (NSTextView) -> Превью (WKWebView):
   → Пользователь скроллит NSTextView
   → Coordinator вычисляет centered line, offsetInLine и fraction
   → SplitEditorView передаёт previewTargetPosition = (line, offset, fraction)
   → WebPreviewView вызывает window.scrollToSourceLine(line, offset, fraction)
   → JS выставляет _isProgrammaticScroll = true, центрирует элемент с data-source-line=line
   → Scroll-listener в JS ловит событие, видит _isProgrammaticScroll и не шлёт эхо обратно в Swift.

2. Превью (WKWebView) -> Редактор (NSTextView):
   → Пользователь скроллит WKWebView
   → JS-scroll-listener находит элемент на середине высоты окна (window.innerHeight / 2)
   → Отправляет сообщение scrollHandler: { line, offset, fraction }
   → Swift-координатор получает payload и вызывает onScrollPosition
   → CodeEditorView выставляет isProgrammaticScroll = true и скроллит NSTextView к line + offset
   → AppKit генерирует BoundsDidChangeNotification, координатор видит isProgrammaticScroll и игнорирует событие
   → На следующем витке RunLoop флаг сбрасывается.
```

---

## 6. Зависимости (SPM)

В `project.yml` — единственная SPM-зависимость:

```yaml
packages:
  swift-markdown:
    url: https://github.com/swiftlang/swift-markdown.git
    from: "0.4.0"
```

> Конвертер — собственный `ConverterService` (Foundation/AppKit/PDFKit); `swift-docx`/`Demark` в проекте не используются. Юнит-тесты — отдельный таргет `DuckMDTests` (**131 тест**, TEST SUCCEEDED — прогон релизного аудита 2026-09-13; статический подсчёт совпадает), схема `DuckMD` содержит test-экшен. Состав: `MarkdownParserTests`, `MarkdownToHTMLTests`, `RenderEditParserTests`, `ConverterServiceTests`, `RecentFilesStoreTests`, `DocumentFileServiceTests`, `DiagnosticsLogTests`, `DocumentAssociationAndThemeTests`, `PreviewContrastAndScrollTests` (проверка `scrollToSourceLine`, декодирование `ScrollPositionPayload`, контраст тем и Apple typography CSS), `ParseGenerationTests`/`HighlighterPerformanceTests` (generation-guard парсинга, пороги больших документов, кэш regex подсветки).

> **Файловый hardening (релизный аудит 2026-09-13):** все дисковые записи сериализованы через serial `ioQueue` `DocumentFileService`; `writeText` — `throws` (`DocumentFileError.writeFailed`), вызывающие стороны не обновляют `lastSavedText` при неуспехе; `readDocumentText` кидает `invalidUTF8` вместо пустой строки (пустой автосейв не затирает оригинал); `isWriteSuspended` блокирует автосейв до явного решения; эхо собственных записей вотчера подавляется токеном-окном 1.5с (`shouldSuppressOwnEvent`), а не сравнением текста; `.delete`/`.rename` — раздельные колбэки с `restartWatch` 0.3с; read-back записи — `verifyDiskContent`; rename валидируется (`validatedRename`: `/`, `\`, `..`, пустое, NUL) и выполняется атомарным `moveItem`. Компромисс: окно подавления 1.5с — не истинный FS-токен (внешняя запись <1.5с после своей может быть ложно подавлена); merge внешних изменений — бинарный выбор в баннере, без side-by-side diff.

> **Важно для реализации:** продукт `swift-markdown` называется **`Markdown`**, не `swift-markdown` — указывать явно `product: Markdown`. Версия 0.8.0 совместима (проверено). GFM (таблицы/зачёркивание/todo) и smart punctuation **парсятся по умолчанию**, никаких `builtinExtensions` нет.

---

## 7. Инфо.plist / UTType (ассоциация файлов)

В `project.yml` (генерится в Info.plist). Начиная с v0.6.3 — ТОЛЬКО системный
тип Markdown (встроен в macOS 12+; deployment target — macOS 26). Ранее
экспортировался собственный тип `net.duckingfireball.markdown` (опечатка в
идентификаторе), который конкурировал за расширение `.md` и ломал открытие
двойным кликом из Finder — удалён из manifest и из Info.plist.

- `CFBundleDocumentTypes`: `LSHandlerRank: Owner`, `LSItemContentTypes`: `net.daringfireball.markdown` — только Markdown. Факт v0.6.15 (Этап 5): владение `public.plain-text` снято; `.txt` остаётся входом чтения/конвертера (`readableContentTypes` содержит `.plainText`), но не заявляется в `CFBundleDocumentTypes`.
- `UTExportedTypeDeclarations` / `UTImportedTypeDeclarations`: удалены (системный тип повторно объявлять нельзя — конфликт LaunchServices).

В коде:
```swift
extension UTType {
    // Системный Markdown-тип; markdownStandard — псевдоним совместимости.
    static let markdownDoc = UTType("net.daringfireball.markdown") ?? .plainText
    static let markdownStandard = UTType("net.daringfireball.markdown") ?? .plainText
}
```

Холодный старт по двойному клику (pending URL): событие
`application(_:openFiles:)` в [`AppDelegate`](../DuckMD/DuckMDApp.swift) может
прийти раньше, чем `onAppear` главного окна привяжет `appState`. Файл
буферизуется в `pendingOpenURL` и применяется в `flushPendingOpenURL()` после
привязки — открытие не теряется. Регресс-покрытие ассоциации/UTType —
`DocumentAssociationAndThemeTests` (см. §6).

---

## 8. Соглашения по коду

- **Язык комментариев/UI**: русский (основной язык продукта). Код-идентификаторы — английский.
- **Swift 5 mode** (`SWIFT_VERSION: "5"` в base settings) для совместимости, но используется concurrency где уместно.
- **Архитектура**: MVVM-lite (`ObservableObject` как view-model/state, SwiftUI views чистые).
- **Доступность**: `accessibilityLabel` на всех иконочных кнопках, `.help()` tooltips.
- **Именование**: `*View` для SwiftUI, `*Store` для state-managers, `*Service` для side-effect сервисов, `*Converter` для конвертеров.
- **Ошибки**: `throws` + `do/catch` с осмысленными сообщениями; в UI — `.alert` или мягкий баннер, не краш.

---

## 9. Правила версионирования

В проекте используется строгое семантическое версионирование (SemVer):
1. **Мажорная версия (X.y.z)**: Крупные изменения архитектуры, полная переработка дизайна или замена ключевых компонентов.
2. **Минорная версия (x.Y.z)**: Добавление нового функционала, значительных модулей или новых экранов.
3. **Патч-версия (x.y.Z)**: Минорные исправления интерфейса, полировка UI/UX, багфиксы, оптимизация производительности и доработка существующего функционала без добавления кардинально новых возможностей. Все текущие багфиксы и улучшения интерфейса инкрементируют исключительно эту цифру (самую правую, например, переход с `0.6.0` на `0.6.1`).

---

## 10. Сборка и запуск

```bash
# 1. Установить xcodegen (если нет): brew install xcodegen
# 2. Сгенерировать проект
cd DuckMD && xcodegen generate

# 3. Собрать (Debug)
xcodebuild -project DuckMD.xcodeproj -scheme DuckMD \
  -configuration Debug -destination 'platform=macOS' build

# 4. Запустить
open ~/Library/Developer/Xcode/DerivedData/DuckMD-*/Build/Products/Debug/DuckMD.app

# 5. Перегенерировать иконку (если меняли скрипт)
swift scripts/generate_icon.swift
```

> **Известная средовая проблема:** `xcodebuild` может падать с ошибкой плагина `IDESimulatorFoundation`/`DVTDownloads`. Лечится: `xcodebuild -runFirstLaunch` (выполняется один раз). Симптом: `error: Missing package product 'swift-markdown'` — лечится явным `product: Markdown` в зависимостях.

### 10.1. Локальный тестовый DMG — `scripts/build-test-dmg.sh`

Полный локальный прогон «сборка → подпись → versioned DMG» без платного аккаунта, публикации и git-операций:

```bash
./scripts/build-test-dmg.sh                # полный прогон: build → sign → versioned DMG
DRY_RUN=1 ./scripts/build-test-dmg.sh      # dry-run: показать план команд, ничего не выполнять
SIGN_MODE=adhoc ./scripts/build-test-dmg.sh
```

- **Подпись** (`SIGN_MODE=auto|unsigned|adhoc`, по умолчанию `auto`): Release собирается с «Apple Development» + Team ID из `project.yml` (`CODE_SIGN_STYLE: Manual`); при недоступности сертификата в keychain — автоматический откат `auto → adhoc` (подпись `-`, запуск только на этой машине). Режим `unsigned` собирает без подписи и подписывает через `codesign` CLI тем же сертификатом «Apple Development». Все режимы включают hardened runtime и entitlements из `security/DuckMD.entitlements`.
- **Versioned naming:** версия читается из `CFBundleShortVersionString` собранного бандла (read-back, не из `project.yml`), артефакты — `build/dist/DuckMD-<VERSION>.app` и `build/dist/DuckMD-<VERSION>.dmg`; подпись перепроверяется после копирования, DMG — через `hdiutil verify`. Единый источник версии — `MARKETING_VERSION = 0.6.15` в `project.yml` → `CFBundleShortVersionString`.
- **Дистрибуция (Этап 0 адаптирован, v0.6.15):** Developer ID отсутствует, notarization не выполняется — типичный open-source Mac-проект. Публичная раздача — только через GitHub Releases тем же versioned DMG из `scripts/build-test-dmg.sh` с локальной подписью (Apple Development / ad-hoc). `scripts/build-release.sh` (Developer ID + notarization) — историческая заготовка на будущее, в текущем GitHub-flow не используется (см. D-25 в `DECISIONS.md` и N-8 в `SPEC.md`). Установка из GitHub требует Gatekeeper-обхода (правый клик → Открыть / `xattr -dr com.apple.quarantine`) — инструкция в `README.md` § «Установка из GitHub».
