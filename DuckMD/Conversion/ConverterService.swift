import Foundation
import AppKit
import PDFKit

/// Ошибки конвертации файлов
enum ConversionError: Error, LocalizedError {
    case unsupportedFormat
    case invalidPDF
    case loadFailed
    /// Этап 2: входной файл превышает maxInputFileSize — отказ ДО парсинга.
    case fileTooLarge(bytes: Int)
    /// Этап 2: PDF превышает maxPDFPages — защита от квадратичной конкатенации.
    case tooManyPages(count: Int)
    /// Этап 2: пустой файл (для форматов, где пустой = битый).
    case emptyFile
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Неподдерживаемый формат файла"
        case .invalidPDF: return "Не удалось прочитать PDF файл"
        case .loadFailed: return "Не удалось загрузить файл"
        case .fileTooLarge(let bytes):
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "Файл слишком большой (%.1f МБ). Лимит — %.0f МБ", mb, Double(ConverterService.maxInputFileSize) / (1024 * 1024))
        case .tooManyPages(let count):
            return "PDF содержит \(count) страниц. Лимит — \(ConverterService.maxPDFPages) страниц"
        case .emptyFile: return "Файл пуст"
        }
    }
}

/// Сервис конвертации различных форматов в Markdown
struct ConverterService {
    /// Этап 2: лимит размера входного файла (отказ до парсинга).
    static let maxInputFileSize = 50 * 1024 * 1024 // 50 МБ
    /// Этап 2: лимит страниц PDF (текст конкатенируется в одну строку —
    /// без лимита большой PDF квадратично раздувает память).
    static let maxPDFPages = 200
    
    /// Сконвертировать файл в Markdown по его URL
    static func convert(url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        
        // Этап 2: pre-check ДО парсинга — только регулярный файл, не пустой (кроме txt),
        // не больше maxInputFileSize. Расширение — не единственная проверка типа.
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let fileSize = resourceValues?.fileSize ?? 0
        if resourceValues?.isRegularFile == false {
            throw ConversionError.loadFailed
        }
        if fileSize > maxInputFileSize {
            throw ConversionError.fileTooLarge(bytes: fileSize)
        }
        
        switch ext {
        case "txt":
            // Пустой txt → пустой markdown (легитимный сценарий, см. тесты).
            return try String(contentsOf: url, encoding: .utf8)
            
        case "pdf":
            if fileSize == 0 { throw ConversionError.emptyFile }
            guard let pdf = PDFDocument(url: url) else {
                throw ConversionError.invalidPDF
            }
            if pdf.pageCount > maxPDFPages {
                throw ConversionError.tooManyPages(count: pdf.pageCount)
            }
            var text = ""
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "> ⚠️ PDF содержит сканированные страницы. Для конвертации нужен OCR."
            }
            return text
            
        case "docx", "rtf", "html", "rtfd":
            if fileSize == 0 { throw ConversionError.emptyFile }
            var docType: NSAttributedString.DocumentType = .rtf
            if ext == "docx" {
                docType = .officeOpenXML
            } else if ext == "html" {
                docType = .html
            } else if ext == "rtfd" {
                docType = .rtfd
            }
            
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: docType,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            // Этап 2 (SPEC N-6), ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ (Этап 5 — подтверждено):
            // NSAttributedString HTML-импорт использует legacy WebKit-парсер,
            // у которого НЕТ публичной опции отключения загрузки внешних ресурсов
            // (<img src="http..."> и т.п.). Удалённые ресурсы HTML-файла при его
            // конвертации могут быть запрошены — это относится и к fallback-ветке
            // автоопределения ниже (options: [:] тоже идёт через WebKit для html).
            // Безопасного код-фикса без смены поведения нет (STAGE2 §4) —
            // контракт: сеть возможна ТОЛЬКО по явному действию пользователя
            // над его собственным файлом; результат — текст Markdown (картинки
            // не рендерятся и не кэшируются).
            var docAttrs: NSDictionary? = nil
            guard let attrString = try? NSAttributedString(url: url, options: options, documentAttributes: &docAttrs) else {
                // Fallback-автоопределение: та же сетевая семантика (см. выше).
                if let attr = try? NSAttributedString(url: url, options: [:], documentAttributes: &docAttrs) {
                    return convertAttributedStringToMarkdown(attr)
                }
                throw ConversionError.loadFailed
            }
            return convertAttributedStringToMarkdown(attrString)
            
        default:
            throw ConversionError.unsupportedFormat
        }
    }
    
    /// Маппинг атрибутов форматирования NSAttributedString в разметку Markdown
    private static func convertAttributedStringToMarkdown(_ attrString: NSAttributedString) -> String {
        var markdown = ""
        let fullRange = NSRange(location: 0, length: attrString.length)
        
        attrString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let substring = attrString.attributedSubstring(from: range).string
            var text = substring
            
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Извлекаем стили шрифта (Bold / Italic)
                if let font = attributes[.font] as? NSFont {
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                    let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                    
                    let leadingWS = text.prefix(while: { $0.isWhitespace })
                    let trailingWS = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
                    let coreText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !coreText.isEmpty {
                        var formatted = coreText
                        if isBold && isItalic {
                            formatted = "***\(formatted)***"
                        } else if isBold {
                            formatted = "**\(formatted)**"
                        } else if isItalic {
                            formatted = "*\(formatted)*"
                        }
                        text = String(leadingWS) + formatted + String(trailingWS)
                    }
                }
                
                // Ссылки
                if let link = attributes[.link] {
                    let linkStr: String
                    if let url = link as? URL {
                        linkStr = url.absoluteString
                    } else if let str = link as? String {
                        linkStr = str
                    } else {
                        linkStr = ""
                    }
                    
                    if !linkStr.isEmpty {
                        let leadingWS = text.prefix(while: { $0.isWhitespace })
                        let trailingWS = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
                        let coreText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !coreText.isEmpty {
                            text = String(leadingWS) + "[\(coreText)](\(linkStr))" + String(trailingWS)
                        }
                    }
                }
            }
            
            markdown += text
        }
        
        return markdown
    }
}
