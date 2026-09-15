# Руководство по внесению изменений (Contributing)

Мы рады вкладу в развитие **DuckMD**! Перед тем как отправить Pull Request или открыть Issue, ознакомьтесь с основными правилами проекта.

## 🎯 Принципы разработки

1. **Строгое следование канону сборки**:
   - Единственный источник правды для структуры проекта — [`project.yml`](project.yml).
   - Файл `DuckMD.xcodeproj` генерируется через XcodeGen (`xcodegen generate`) и **не коммитится в git**.

2. **Сохранение архитектуры и эстетики**:
   - Вся работа с документами происходит строго локально, без сетевых запросов, облачной синхронизации и телеметрии.
   - Эстетика Apple: нативный дизайн macOS Sequoia, использование VisualEffect, аккуратных сплиттеров и строгих пропорций окон.
   - Любые изменения в парсере Markdown, AST или логике сохранения должны покрываться модульными тестами в `DuckMDTests`.

3. **Конфиденциальность и безопасность**:
   - Запрещено коммитить персональные данные, токены, пароли, приватные сертификаты или ключи.
   - См. [`SECURITY.md`](SECURITY.md).

## 🛠️ Локальная разработка

### Требования
- macOS 15.0+ (Sequoia)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Python 3.10+ с установленным `dmgbuild` (для сборки релизных DMG-образов)

### Команды
```bash
# Генерация Xcode проекта
xcodegen generate

# Запуск полного набора юнит-тестов (131+ тестов)
xcodebuild test -project DuckMD.xcodeproj -scheme DuckMD -destination 'platform=macOS'

# Сборка приложения в конфигурации Release
xcodebuild build -project DuckMD.xcodeproj -scheme DuckMD -configuration Release

# Сборка релизного DMG-пакета
scripts/build_dmg.sh
```

## 📋 Открытие Issues и Pull Requests

- **Баг-репорты**: указывайте версию macOS, шаги воспроизведения и прикладывайте пример Markdown-файла, на котором возникла проблема.
- **Pull Requests**: убедитесь, что все 131/131 тестов успешно проходят (`TEST SUCCEEDED`), проект собирается через `xcodegen generate`, и код следует канонам Swift.
