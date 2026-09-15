# 🦆 DuckMD


> **Мгновенный, красивый Markdown-ридер для macOS** — как Apple Notes, только для `.md`.
> Оптимизирован под чтение и правку отчётов и текстов от нейросетей.
> **Версия:** 0.6.15 (`MARKETING_VERSION` в `project.yml` — единый источник версии → `CFBundleShortVersionString` в `Info.plist`) · **Платформа:** macOS 14+ · **Стек:** SwiftUI + WKWebView + swift-markdown
> **Дизайн:** Apple Notes × Bear × Liquid Glass · **Маскот:** гранёная (low-poly) уточка

<p align="center">
  <img src="docs/assets/duckmd-demo.gif" width="760" alt="DuckMD Live Demo" />
</p>

---

## Что это

Открыл `.md` двойным кликом — и через **<1 секунду** видишь красивый текст. Без загрузки тяжеловесных редакторов, без Electron и лишних кнопок. 

Хочешь поправить — режим «Правка» (код + живой рендер рядом) с умным автоформатированием (Enter в списке → новый пункт, авто-закрытие `**`, триггеры `# `/`- `).

При запуске приложения без файла единое окно `main` показывает **хаб-состояние** (`MainContainerView` + `HubView`, без отдельного `HubWindow`) в macOS-стиле. В нём собраны недавние файлы (без ограничений на количество), встроен нативный поиск и сортировка, а также три карточки быстрых действий (Новый документ, Открыть существующий, Конвертировать). Открытие документа и возврат кнопкой «← Хаб» — переключение состояний того же окна (`.opacity` 0.18s).

Встроен **Конвертер документов** (DOCX, PDF, RTF, HTML, TXT). Вы перетаскиваете любой файл, и приложение автоматически конвертирует его в `.md`, сохраняет в папку по умолчанию (`~/Documents/DuckMD`) и сразу открывает в редакторе.

В настройках доступна смена тем отображения (Apple, Paper, Mono, Ocean, Night) с живым обновлением, регулировка ширины контента, умное автосохранение и ссылки на репозиторий.

Маскот — стильная жёлтая low-poly уточка, которая автоматически адаптируется под системную тему оформления.

---

## 🗺 Roadmap и планы

### Большая цель: сборник нативных программ для macOS (как Office, только локальный и быстрый)
Планируется создать комплект базовых рабочих программ для macOS по типу Microsoft Office, но со своей философией:
- **Супербыстро и нативно:** Только чистый Swift, SwiftUI и AppKit. Никаких чудовищных Electron-обёрток, лагов и жора оперативной памяти.
- **100% локально и приватно:** Никаких обязательных аккаунтов, облачных синхронизаций, телеметрии и слежки. Документы живут только на вашей машине.
- **Полностью бесплатно:** Доступные инструменты для работы без подписок и скрытых платежей.

**Состав пакета:**
1. **DuckMD** — просмотр, редактор и конвертер Markdown/текстовых документов.
2. **DuckSheets (в планах)** — шустрые локальные таблицы (CSV, TSV, XLSX) без тормозов Excel.
3. **DuckSlides (в планах)** — быстрая сборка слайдов и презентаций из простого структурированного текста.

### Ближайшие обновления DuckMD
- ⚙️ **Обновление внешнего вида Настроек:** Освежить меню параметров — сделать современный вид в духе нативных системных настроек macOS (аккуратные иконки в скруглённых плашках, понятная эргономика).
- 🎨 **Поднастройка интерфейса:** Докрутить сплиттер, отступы тулбара и анимации переходов между хабом и документом.
- 🔔 **Индикатор обновления версий:** Добавить деликатный индикатор наличия свежих релизов с GitHub Releases, чтобы видеть обновления прямо в приложении и скачивать свежий DMG в один клик.

---

## 📚 Документация

Полная спецификация проекта живёт в [`docs/`](./docs). **Читай в этом порядке:**

| Документ | О чём |
|  ---  |  ---  |
| **[docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)** | Как устроено: архитектура, стек, оконная система, поток данных, зависимости, сборка и хаки |
| **[docs/UX.md](./docs/UX.md)** | Экраны: хаб, документ (3 режима), конвертер, настройки, About; макеты, флоу, состояния, горячие клавиши |
| **[docs/SPEC.md](./docs/SPEC.md)** | Что строим: концепция, требования, критерии приёмки |
| **[docs/DECISIONS.md](./docs/DECISIONS.md)** | Почему так: журнал решений и ответов на уточняющие вопросы с привязкой к требованиям |
| **[CHANGELOG.md](./CHANGELOG.md)** | Статус реализации и история версий (канон статуса для публики) |

---

## 🚀 Быстрый старт

```bash
# Требования: macOS 14+, Xcode 15+, xcodegen
# brew install xcodegen   # если ещё не установлен

# 1. Сгенерировать Xcode-проект
xcodegen generate

# 2. Один раз (если xcodebuild ругается на плагин симулятора)
xcodebuild -runFirstLaunch

# 3. Собрать (Debug)
xcodebuild -project DuckMD.xcodeproj -scheme DuckMD \
  -configuration Debug -destination 'platform=macOS' build

# 4. Запустить
open ~/Library/Developer/Xcode/DerivedData/DuckMD-*/Build/Products/Debug/DuckMD.app
```

---

## ✅ Текущий статус

**Полностью стабильная сборка (v0.6.15).** Реализовано:

- **Устранение бага белого экрана (v0.6.6)**: переход на `webView.loadHTMLString(html, baseURL: docDir)` полностью устранил ошибки блокировки файлов системной песочницей WebKit. Локальные картинки и ссылки открываются мгновенно.
- **Smart Centered Sync Scroll (v0.6.6)**: умная синхронизация скролла с оптическим центрированием по строкам (`data-source-line`), адаптивной скоростью для разновысоких блоков (код, таблицы, абзацы) и жёсткой доводкой до крайних положений ($y=0$ и $y=\text{maxScroll}$).
- **Премиальная Apple-типографика (v0.6.6)**: нативные системные шрифты (`-apple-system`, `SF Pro Text`, `SF Pro Display`, `SF Mono`), интерлиньяж 1.65, оформление блоков кода и таблиц в виде скруглённых карточек macOS (radius 10px).
- **Синхронизация фона подложки**: цвет фона `underPageBackgroundColor` строго следует за темой приложения без белых вспышек.
- **Единый контейнер (v0.6.15, факт)**: одно окно `main` (`MainContainerView`) — хаб и документ как состояния (`AppState.showHub`/`activeDocument`), без отдельного `HubWindow`/`DocumentGroup`; холодный старт из Finder без мелькания хаба (`pendingOpenURL`/`flushPendingOpenURL`).
- **Интерактивный Хаб**: Нативный поиск и сортировка, быстрые действия, ховер-эффекты на кнопках и моментальное открытие файлов без искусственных задержек.
- **Интеллектуальный Конвертер**: Поддержка drag-and-drop, автосохранение результата в `~/Documents/DuckMD` и мгновенное открытие сконвертированного файла.
- **Фирменный стиль (v0.6.5)**: новая гранёная (low-poly) уточка-маскот, кристально чёткий Retina мастер-ассет в Assets.xcassets, обновлённый AppIcon 1024×1024 со сквирклом Apple.
- **Интерактивные GFM-чекбоксы**: интерактивный toggle в превью с автоматическим обновлением кода и автосохранением.

---

## 🗂 Структура проекта

```
DuckMD/
├── README.md                    ← вы здесь
├── project.yml                  ← манифест xcodegen (зависимости, target, Info.plist)
├── docs/                        ← спецификация и ассеты
│   ├── assets/                  ← скриншоты и демо-гифка интерфейса
│   └── SPEC.md · ARCHITECTURE.md · UX.md · DECISIONS.md · CHANGELOG.md
├── scripts/
│   ├── generate_icon.swift      ← генерация иконки-утки (PNG 1024)
│   └── build-test-dmg.sh        ← сборка локального тестового DMG
├── DuckMD/
│   ├── DuckMDApp.swift          ← @main, AppDelegate, оконная система
│   ├── App/                     ← AppState, SettingsStore, RecentFilesStore, FileWatcherService, DocumentFileService
│   ├── Models/                  ← MarkdownDocument
│   ├── Parsing/                 ← MarkdownParser, блоки, MarkdownToHTML, экспорт
│   ├── Editing/                 ← CodeEditorView, автоформатирование, MarkdownHighlighter
│   ├── Conversion/              ← конвертеры (docx/pdf/html/rtf/txt → md)
│   ├── Views/                   ← ContentView, HubView, SettingsView, WebPreviewView, DuckLogo
│   ├── Theme/                   ← HTMLThemeResolver
│   └── Assets.xcassets/         ← AppIcon, DuckLogo, AccentColor (#FFC800)
└── DuckMD.xcodeproj/            ← генерируется xcodegen (в .gitignore)
```

---

## 🎯 Концепция

| | |
|---|---|
| **Боль** | Посмотреть `.md` красиво сейчас = открыть тяжёлый IDE, ждать, нажать рендер, развернуть |
| **Решение** | Двойной клик → мгновенно красивый рендер в стиле Apple Notes |
| **Вайб** | Apple Notes × Bear × Liquid Glass, жёлтый акцент, low-poly маскот-утка |
| **Аудитория** | Те, кто работает с отчётами/текстами нейросетей |

---

## 📦 Установка из GitHub (GitHub-flow, без Developer ID/notarization)

> Требования: macOS 14+, Xcode 15+, xcodegen (`brew install xcodegen`).
> Нотаризация (notarization) не выполняется осознанно; подпись только локальная (Apple Development / ad-hoc) + hardened runtime.

Дистрибуция — только через GitHub Releases как типичный open-source Mac-проект: versioned DMG `build/dist/DuckMD-<VERSION>.dmg` из [`scripts/build-test-dmg.sh`](./scripts/build-test-dmg.sh) с локальной подписью (Apple Development / ad-hoc) + hardened runtime. Developer ID и notarization отсутствуют осознанно (см. [`docs/DECISIONS.md`](./docs/DECISIONS.md) D-25 и [`docs/SPEC.md`](./docs/SPEC.md) N-8).

### Вариант A — готовый DMG из GitHub Releases

1. Скачай `DuckMD-0.6.15.dmg` из [GitHub Releases](https://github.com/zevatov/DuckMD/releases).
2. Открой DMG и перетащи `DuckMD-0.6.15.app` в `Applications`.

### Вариант B — сборка из исходников

```bash
# 0. Требования: macOS 14+, Xcode 15+, xcodegen
# brew install xcodegen   # если ещё не установлен

# 1. Клонирование:
git clone https://github.com/zevatov/DuckMD.git
cd DuckMD

# 2. Генерация Xcode-проекта:
xcodegen generate

# 3. Сборка versioned DMG локально:
./scripts/build-test-dmg.sh                # build → sign → build/dist/DuckMD-<VERSION>.dmg
DRY_RUN=1 ./scripts/build-test-dmg.sh      # dry-run: показать план команд
SIGN_MODE=adhoc ./scripts/build-test-dmg.sh  # fallback без сертификата (только эта машина)
```

Установка релиза из GitHub требует Gatekeeper-обхода (подпись локальная, без notarization):

1. Открой DMG и перетащи `DuckMD-<VERSION>.app` в `Applications`.
2. Первый запуск при ad-hoc подписи — правый клик по приложению → «Открыть» → подтвердить (либо снятие карантина в терминале: `xattr -d com.apple.quarantine /Applications/DuckMD-<VERSION>.app`, для рекурсивного снятия — `xattr -dr com.apple.quarantine /Applications/DuckMD-<VERSION>.app`).
3. Версия в приложении читается из Bundle (`CFBundleShortVersionString` ← `MARKETING_VERSION = 0.6.15` в `project.yml`).

---

© 2026 DuckMD · Лицензия [MIT](./LICENSE) · [Документация](./docs) · [История изменений](./CHANGELOG.md) · `v0.6.15`
