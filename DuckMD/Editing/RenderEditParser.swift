import Foundation

/// Утилита для обратной конвертации: HTML textContent → Markdown строка.
/// Заменяет содержимое блока в исходном Markdown-тексте по номерам строк,
/// сохраняя оригинальные префиксы (заголовки, цитаты, списки) и выравнивание.
struct RenderEditParser {
    static func applyEdit(startLine: Int, endLine: Int, newText: String, to sourceText: String) -> String {
        let lines = sourceText.components(separatedBy: "\n")
        guard startLine >= 1 && startLine <= lines.count else { return sourceText }
        let end = max(startLine, min(endLine, lines.count))
        
        let startIdx = startLine - 1
        let endIdx = end - 1
        
        let firstLine = lines[startIdx]
        
        // Извлекаем Markdown-префикс с помощью регулярного выражения
        let pattern = #"^\s*(?:#+\s+|(?:>\s*)+|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+\.\s+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return sourceText }
        
        let nsLine = firstLine as NSString
        let range = regex.rangeOfFirstMatch(in: firstLine, options: [], range: NSRange(location: 0, length: nsLine.length))
        
        let prefix: String
        if range.location != NSNotFound {
            prefix = nsLine.substring(with: range)
        } else {
            prefix = ""
        }
        
        // Формируем измененный текст блока
        let newLines = newText.components(separatedBy: .newlines)
        let replacement: String
        
        if prefix.contains(">") {
            // Цитата: добавляем префикс цитаты к каждой строке
            replacement = newLines.map { prefix + $0 }.joined(separator: "\n")
        } else if prefix.contains("#") {
            // Заголовок: префикс только на первой строке
            if newLines.count > 1 {
                replacement = prefix + newLines[0] + "\n" + newLines[1...].joined(separator: "\n")
            } else {
                replacement = prefix + newText
            }
        } else {
            // Список или абзац: префикс на первой строке, отступ на остальных
            var resultLines: [String] = []
            for (idx, line) in newLines.enumerated() {
                if idx == 0 {
                    resultLines.append(prefix + line)
                } else {
                    let indent = String(repeating: " ", count: prefix.count)
                    resultLines.append(indent + line)
                }
            }
            replacement = resultLines.joined(separator: "\n")
        }
        
        var updatedLines = Array(lines[0..<startIdx])
        updatedLines.append(replacement)
        if endIdx + 1 < lines.count {
            updatedLines.append(contentsOf: lines[(endIdx + 1)...])
        }
        
        return updatedLines.joined(separator: "\n")
    }

    // MARK: - Task Checkbox Toggle (SPEC R-MD-4)

    /// Toggle GFM task-чекбокса: находит в исходных строках первую task-строку блока
    /// с `sourceLine == line` (regexp `^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])`) и
    /// меняет маркер `[ ]`↔`[x]`. Возвращает новые строки документа или nil, если
    /// строка не найдена/вне диапазона (валидация payload, как в validatedEditPayload).
    static func applyCheckboxToggle(lines: [String], line: Int, checked: Bool) -> [String]? {
        guard line >= 1 && line <= lines.count else { return nil }
        let pattern = #"^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        // Первая строка блока — начиная с line-1 (0-based). Сканируем вниз, пока
        // строки могут принадлежать блоку (пустые или с отступом-продолжением);
        // первая посторонняя непустая строка — маркер не найден (nil).
        for idx in (line - 1)..<lines.count {
            let nsLine = lines[idx] as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = regex.firstMatch(in: lines[idx], options: [], range: range),
               match.numberOfRanges == 4 {
                let marker = nsLine.substring(with: match.range(at: 2))
                let isChecked = (marker != " ")
                // Уже в требуемом состоянии — без изменений (лишний перерендер не нужен).
                guard isChecked != checked else { return lines }
                let replacement = checked ? "x" : " "
                var updated = lines
                updated[idx] = nsLine.replacingCharacters(in: match.range(at: 2), with: replacement)
                return updated
            }
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            let isContinuation = trimmed.isEmpty || lines[idx].hasPrefix(" ") || lines[idx].hasPrefix("\t")
            guard isContinuation else { return nil }
        }
        return nil
    }

    // MARK: - Table Editing

    static func applyTableCellEdit(
        tableLine: Int,
        row: Int,
        col: Int,
        newText: String,
        to sourceText: String
    ) -> String {
        let lines = sourceText.components(separatedBy: "\n")
        guard let tableRange = getTableRange(startingAt: tableLine - 1, in: lines) else { return sourceText }
        let tableLines = Array(lines[tableRange])
        
        var (headers, separator, rows) = parseTableLines(tableLines)
        
        if row == 0 {
            if col < headers.count {
                headers[col] = newText
            }
        } else {
            let bodyRowIdx = row - 1
            if bodyRowIdx < rows.count && col < rows[bodyRowIdx].count {
                rows[bodyRowIdx][col] = newText
            }
        }
        
        let newTableStr = rebuildTable(headers: headers, separator: separator, rows: rows)
        
        var updatedLines = Array(lines[0..<tableRange.lowerBound])
        updatedLines.append(newTableStr)
        if tableRange.upperBound < lines.count {
            updatedLines.append(contentsOf: lines[tableRange.upperBound...])
        }
        return updatedLines.joined(separator: "\n")
    }

    static func addRow(tableLine: Int, to sourceText: String) -> String {
        let lines = sourceText.components(separatedBy: "\n")
        guard let tableRange = getTableRange(startingAt: tableLine - 1, in: lines) else { return sourceText }
        let tableLines = Array(lines[tableRange])
        
        var (headers, separator, rows) = parseTableLines(tableLines)
        
        let newRow = Array(repeating: "", count: headers.count)
        rows.append(newRow)
        
        let newTableStr = rebuildTable(headers: headers, separator: separator, rows: rows)
        
        var updatedLines = Array(lines[0..<tableRange.lowerBound])
        updatedLines.append(newTableStr)
        if tableRange.upperBound < lines.count {
            updatedLines.append(contentsOf: lines[tableRange.upperBound...])
        }
        return updatedLines.joined(separator: "\n")
    }

    static func addColumn(tableLine: Int, to sourceText: String) -> String {
        let lines = sourceText.components(separatedBy: "\n")
        guard let tableRange = getTableRange(startingAt: tableLine - 1, in: lines) else { return sourceText }
        let tableLines = Array(lines[tableRange])
        
        var (headers, separator, rows) = parseTableLines(tableLines)
        
        headers.append("")
        let newSeparator = adjustSeparator(separator: separator, colCount: headers.count)
        
        for i in 0..<rows.count {
            rows[i].append("")
        }
        
        let newTableStr = rebuildTable(headers: headers, separator: newSeparator, rows: rows)
        
        var updatedLines = Array(lines[0..<tableRange.lowerBound])
        updatedLines.append(newTableStr)
        if tableRange.upperBound < lines.count {
            updatedLines.append(contentsOf: lines[tableRange.upperBound...])
        }
        return updatedLines.joined(separator: "\n")
    }

    static func deleteRow(tableLine: Int, row: Int, to sourceText: String) -> String {
        let lines = sourceText.components(separatedBy: "\n")
        guard let tableRange = getTableRange(startingAt: tableLine - 1, in: lines) else { return sourceText }
        let tableLines = Array(lines[tableRange])
        
        var (headers, separator, rows) = parseTableLines(tableLines)
        
        let bodyRowIdx = row - 1
        guard bodyRowIdx >= 0 && bodyRowIdx < rows.count else { return sourceText }
        
        rows.remove(at: bodyRowIdx)
        
        let newTableStr = rebuildTable(headers: headers, separator: separator, rows: rows)
        
        var updatedLines = Array(lines[0..<tableRange.lowerBound])
        updatedLines.append(newTableStr)
        if tableRange.upperBound < lines.count {
            updatedLines.append(contentsOf: lines[tableRange.upperBound...])
        }
        return updatedLines.joined(separator: "\n")
    }

    static func deleteColumn(tableLine: Int, col: Int, to sourceText: String) -> String {
        let lines = sourceText.components(separatedBy: "\n")
        guard let tableRange = getTableRange(startingAt: tableLine - 1, in: lines) else { return sourceText }
        let tableLines = Array(lines[tableRange])
        
        var (headers, separator, rows) = parseTableLines(tableLines)
        
        guard col >= 0 && col < headers.count else { return sourceText }
        
        headers.remove(at: col)
        let newSeparator = adjustSeparator(separator: separator, colCount: headers.count)
        
        for i in 0..<rows.count {
            if col < rows[i].count {
                rows[i].remove(at: col)
            }
        }
        
        let newTableStr = rebuildTable(headers: headers, separator: newSeparator, rows: rows)
        
        var updatedLines = Array(lines[0..<tableRange.lowerBound])
        updatedLines.append(newTableStr)
        if tableRange.upperBound < lines.count {
            updatedLines.append(contentsOf: lines[tableRange.upperBound...])
        }
        return updatedLines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func getTableRange(startingAt startIdx: Int, in lines: [String]) -> Range<Int>? {
        guard startIdx >= 0 && startIdx < lines.count else { return nil }
        var currentIdx = startIdx
        while currentIdx < lines.count {
            let line = lines[currentIdx].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") || line.contains("|") {
                currentIdx += 1
            } else {
                break
            }
        }
        return startIdx..<currentIdx
    }

    private static func splitByPipe(_ string: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isEscaped = false
        for char in string {
            if char == "\\" {
                isEscaped = true
                current.append(char)
            } else if char == "|" {
                if isEscaped {
                    current.append(char)
                    isEscaped = false
                } else {
                    parts.append(current)
                    current = ""
                }
            } else {
                isEscaped = false
                current.append(char)
            }
        }
        parts.append(current)
        return parts
    }

    private static func parseTableLines(_ tableLines: [String]) -> (headers: [String], separator: String, rows: [[String]]) {
        var headers: [String] = []
        var separator = ""
        var rows: [[String]] = []
        
        for (idx, line) in tableLines.enumerated() {
            var parts = splitByPipe(line)
            if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                parts.removeFirst()
            }
            if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                parts.removeLast()
            }
            let cells = parts.map { $0.trimmingCharacters(in: .whitespaces) }
            
            if idx == 0 {
                headers = cells
            } else if idx == 1 {
                separator = line
            } else {
                rows.append(cells)
            }
        }
        return (headers, separator, rows)
    }

    private static func adjustSeparator(separator: String, colCount: Int) -> String {
        var parts = splitByPipe(separator)
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            parts.removeFirst()
        }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            parts.removeLast()
        }
        
        if parts.count == colCount {
            return "| " + parts.joined(separator: " | ") + " |"
        } else if parts.count < colCount {
            var newParts = parts
            while newParts.count < colCount {
                newParts.append("---")
            }
            return "| " + newParts.joined(separator: " | ") + " |"
        } else {
            let newParts = Array(parts.prefix(colCount))
            return "| " + newParts.joined(separator: " | ") + " |"
        }
    }

    private static func rebuildTable(headers: [String], separator: String, rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append(separator)
        for row in rows {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
