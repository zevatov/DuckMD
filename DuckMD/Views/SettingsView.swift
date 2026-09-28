import SwiftUI

/// Настройки — единый экран с секциями, Apple-стиль.
struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: — Header (ReTypeR style: App identity + links + update indicator)
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.85), Color.orange.opacity(0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.orange.opacity(0.25), radius: 6, x: 0, y: 2)
                        DuckLogo(size: 26)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("DuckMD")
                            .font(.system(size: 18, weight: .bold))
                        HStack(spacing: 6) {
                            Text("Быстрый Markdown редактор • Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.6.16")")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if case .updateAvailable(let version, _) = updateChecker.status {
                                Button(action: {
                                    updateChecker.openUpdateTarget()
                                }) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 6, height: 6)
                                        Text("Доступна \(version)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Link(destination: URL(string: "https://t.me/+8oSXf_D7EwEyYzZi")!) {
                            HStack(spacing: 5) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.2, green: 0.65, blue: 0.95))
                                Text("Telegram")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Link(destination: URL(string: "https://github.com/zevatov/DuckMD")!) {
                            HStack(spacing: 5) {
                                Image(systemName: "curlybraces")
                                    .font(.system(size: 11))
                                Text("GitHub")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)

                // MARK: — Оформление
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Оформление", icon: "paintpalette")
                    
                    settingsCard {
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
                }
                
                // MARK: — Редактор
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Редактор", icon: "square.and.pencil")
                    
                    settingsCard {
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
                }
                
                // MARK: — Приватность превью
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Приватность", icon: "lock.shield")
                    
                    settingsCard {
                        Toggle("Загружать удалённые изображения", isOn: $settings.allowRemoteImages)
                            .help("Выключено: http/https-картинки в превью не загружаются (защита от трекинг-пикселей). Локальные изображения не затрагиваются.")
                    }
                }
                
                // MARK: — Файлы
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Файлы", icon: "folder")
                    
                    settingsCard {
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
                }
            }
            .padding(24)
        }
        .frame(width: 530, height: 620)
        .onAppear {
            updateChecker.checkForUpdates()
        }
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

    // MARK: - Card Container
    
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(14)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
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
