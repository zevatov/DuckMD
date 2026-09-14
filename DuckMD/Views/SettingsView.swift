import SwiftUI

/// Настройки — единый экран с секциями, Apple-стиль.
struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: — Оформление
                sectionHeader("Оформление", icon: "paintpalette")
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        // Тема
                        HStack {
                            Text("Тема")
                            Spacer()
                            Picker("", selection: $settings.theme) {
                                ForEach(ThemeMode.allCases) { m in
                                    Text(m.label).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                        }
                        
                        Divider()
                        
                        // Стиль рендерера
                        Text("Стиль рендерера")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(RenderThemeOption.allCases) { option in
                                themePreviewTile(option)
                            }
                        }
                        
                        Divider()
                        
                        // Шрифт рендерера
                        HStack {
                            Text("Шрифт рендерера")
                            Spacer()
                            Picker("", selection: $settings.bodyFontDesign) {
                                ForEach(FontDesignMode.allCases) { m in
                                    Text(m.label).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                        }
                        
                        // Размер текста рендерера
                        HStack {
                            Text("Размер текста рендерера")
                            Spacer()
                            Stepper(value: $settings.renderFontSize, in: 12...24, step: 1) {
                                Text("\(Int(settings.renderFontSize)) pt")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        
                        // Ширина контента
                        HStack {
                            Text("Ширина контента")
                            Spacer()
                            Text("\(Int(settings.readingWidth)) pt")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        Slider(value: $settings.readingWidth, in: 480...1200, step: 20)
                    }
                    .padding(6)
                }
                
                // MARK: — Редактор
                sectionHeader("Редактор", icon: "square.and.pencil")
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Размер шрифта")
                            Spacer()
                            Stepper(value: $settings.editorFontSize, in: 10...24, step: 1) {
                                Text("\(Int(settings.editorFontSize)) pt")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        
                        Divider()
                        
                        Toggle("Умное автоформатирование", isOn: $settings.autoformatEnabled)
                        Toggle("Авто-закрытие скобок", isOn: $settings.autoClosePairs)
                        Toggle("Синхронный скролл в Split", isOn: $settings.syncScroll)
                        Toggle("Номера строк в редакторе", isOn: $settings.showLineNumbers)
                    }
                    .padding(6)
                }
                
                // MARK: — Приватность превью (Этап 2, SPEC N-6)
                sectionHeader("Приватность", icon: "lock.shield")
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Загружать удалённые изображения", isOn: $settings.allowRemoteImages)
                            .help("Выключено: http/https-картинки в превью не загружаются (защита от трекинг-пикселей). Локальные изображения не затрагиваются.")
                    }
                    .padding(6)
                }
                
                // MARK: — Файлы
                sectionHeader("Файлы", icon: "folder")
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Автосохранение при вводе", isOn: $settings.autosaveEnabled)
                        
                        Divider()
                        
                        Toggle("Периодическое автосохранение", isOn: $settings.periodicAutosaveEnabled)
                        
                        if settings.periodicAutosaveEnabled {
                            HStack {
                                Text("Интервал")
                                    .foregroundColor(.secondary)
                                Slider(
                                    value: $settings.autoSaveInterval,
                                    in: 60...900,
                                    step: 60
                                )
                                Text("\(Int(settings.autoSaveInterval / 60)) мин")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }
                        
                        Divider()
                        
                        // Таймер баннера внешних изменений (R9)
                        HStack {
                            Text("Таймер внешних изменений")
                            Spacer()
                            Picker("", selection: $settings.extChangeTimerSeconds) {
                                Text("3 сек").tag(3)
                                Text("5 сек").tag(5)
                                Text("10 сек").tag(10)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                            .help("Сколько секунд ждать до авто-принятия изменений файла извне")
                        }
                        
                        Divider()
                        
                        // Лимит недавних файлов (R9)
                        HStack {
                            Text("Недавних файлов")
                            Spacer()
                            Picker("", selection: $settings.maxRecentFiles) {
                                Text("5").tag(5)
                                Text("10").tag(10)
                                Text("20").tag(20)
                                Text("50").tag(50)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                            .help("Сколько недавних файлов хранить в Хабе")
                        }
                        
                        Divider()
                        
                        // Папка по умолчанию
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Папка сохранения по умолчанию")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundColor(.secondary)
                                Text(settings.defaultSavePath.isEmpty ? "Не задана" : (settings.defaultSavePath as NSString).lastPathComponent)
                                    .foregroundColor(settings.defaultSavePath.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                Button("Выбрать…") {
                                    pickDefaultSaveFolder()
                                }
                                .controlSize(.small)
                                
                                if !settings.defaultSavePath.isEmpty {
                                    Button {
                                        settings.defaultSavePath = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                
                Spacer(minLength: 8)
                
                HStack(spacing: 8) {
                    Spacer()
                    
                    Text("DuckMD · Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Link(destination: URL(string: "https://t.me/")!) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Telegram")
                    
                    Link(destination: URL(string: "https://github.com/")!) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("GitHub")
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(width: 520, height: 580)
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
    }
    
    // MARK: - Theme Tile
    
    private func themePreviewTile(_ option: RenderThemeOption) -> some View {
        let isSelected = settings.renderTheme == option
        let isDark = colorScheme == .dark
        let bg = isDark ? option.previewDarkBg : option.previewLightBg
        let fg = isDark ? option.previewDarkFg : option.previewLightFg
        let accent = isDark ? option.previewDarkAccent : option.previewLightAccent
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.renderTheme = option
            }
        } label: {
            VStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Заголовок")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(accent)
                    Text("Текст абзаца")
                        .font(.system(size: 7.5))
                        .foregroundColor(fg)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent.opacity(0.3))
                        .frame(height: 3)
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(fg.opacity(0.15))
                                .frame(width: 18, height: 5)
                        }
                    }
                }
                .padding(7)
                .frame(width: 82, height: 55)
                .background(bg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                
                Text(option.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func pickDefaultSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Выберите папку сохранения по умолчанию"
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultSavePath = url.path
        }
    }
}
