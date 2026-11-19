import AppKit
import Foundation

private struct Usage: Decodable {
    let sessao: Int?
    let semana: Int?
    let entrada_5h: Int?
    let saida_5h: Int?
    let cache_5h: Int?
    let eventos_5h: Int?
    let sessoes_5h: Int?
    let ultima_atividade: String?
    let pct_sessao: Double?
    let pct_semana: Double?
    let pct_restante_sessao: Double?
    let pct_restante_semana: Double?
    let renova_sessao: String?
    let renova_semana: String?
    let limite_estimado_sessao: Bool?
    let limite_estimado_semana: Bool?
    let status: String
    let mensagem: String?
    let hora: String
}

private final class ProgressBar: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var fillColor = NSColor(calibratedRed: 0, green: 0.90, blue: 0.46, alpha: 1) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        bounds.fill()
        guard fraction > 0 else { return }
        fillColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * min(fraction, 1), height: bounds.height).fill()
    }
}

private final class MonitorController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var header: NSTextField!
    private var statusDot: NSView!
    private var tabs: NSSegmentedControl!
    private var footer: NSTextField!
    private var pin: NSButton!
    private var summaryView = NSView()
    private var limitsView = NSView()
    private var activityView = NSView()
    private var miniView = NSView()

    private var summaryTitles: [NSTextField] = []
    private var summaryValues: [NSTextField] = []
    private var summaryPercents: [NSTextField] = []
    private var summaryResets: [NSTextField] = []
    private var summaryBars: [ProgressBar] = []

    private var limitTitles: [NSTextField] = []
    private var limitPercents: [NSTextField] = []
    private var limitRemains: [NSTextField] = []
    private var limitResets: [NSTextField] = []
    private var limitBars: [ProgressBar] = []

    private var activityTitles: [NSTextField] = []
    private var activityValues: [NSTextField] = []
    private var miniTitles: [NSTextField] = []
    private var miniValues: [NSTextField] = []
    private var miniBars: [ProgressBar] = []
    private var miniNotice: NSTextField!
    private var timer: Timer?
    private var loading = false
    private var lastUsage: Usage?
    private var dockAlignedAtResizeStart = false
    private var rightAlignedAtResizeStart = false

    private let signal = NSColor(calibratedRed: 0, green: 0.90, blue: 0.46, alpha: 1)
    private let yellow = NSColor(calibratedRed: 0.96, green: 0.83, blue: 0.28, alpha: 1)
    private let orange = NSColor(calibratedRed: 1, green: 0.62, blue: 0.04, alpha: 1)
    private let danger = NSColor(calibratedRed: 1, green: 0.34, blue: 0.26, alpha: 1)
    private let critical = NSColor(calibratedRed: 1, green: 0.18, blue: 0.54, alpha: 1)
    private let foreground = NSColor(calibratedWhite: 0.95, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.64, alpha: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 370, height: 300)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY)
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Pulse"
        window.level = .floating
        window.contentMinSize = NSSize(width: 320, height: 36)
        window.setFrameAutosaveName("CodexPulseCompactWindow")
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedRed: 0.043, green: 0.047, blue: 0.039, alpha: 1).cgColor
        window.contentView = content

        content.addSubview(summaryView)
        content.addSubview(limitsView)
        content.addSubview(activityView)
        content.addSubview(miniView)
        makeSummary()
        makeLimits()
        makeActivity()
        makeMini()

        header = label("CODEX PULSE", size: 15, color: foreground, bold: true)
        content.addSubview(header)
        statusDot = NSView(frame: .zero)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = muted.cgColor
        content.addSubview(statusDot)

        tabs = NSSegmentedControl(labels: ["Resumo", "Limites", "Atividade"],
                                  trackingMode: .selectOne, target: self, action: #selector(changeLayout(_:)))
        tabs.segmentStyle = .rounded
        tabs.font = .systemFont(ofSize: 11)
        tabs.selectedSegment = min(max(UserDefaults.standard.integer(forKey: "CodexPulseLayout"), 0), 2)
        content.addSubview(tabs)

        footer = label("Atualizando...", size: 10, color: muted, alignment: .right)
        content.addSubview(footer)
        pin = NSButton(checkboxWithTitle: "Sempre à frente", target: self, action: #selector(toggleFloating(_:)))
        pin.state = .on
        pin.font = .systemFont(ofSize: 10)
        content.addSubview(pin)

        showLayout()
        window.makeKeyAndOrderFront(nil)
        if let dockEdge = window.screen?.visibleFrame.minY,
           abs(window.frame.minY - dockEdge) < 40 {
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: dockEdge))
        }
        NSApp.activate(ignoringOtherApps: true)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        NSApp.terminate(nil)
    }

    func windowDidResize(_ notification: Notification) {
        if header != nil { layoutContent() }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let visible = window.screen?.visibleFrame else { return }
        dockAlignedAtResizeStart = abs(window.frame.minY - visible.minY) < 40
        rightAlignedAtResizeStart = abs(window.frame.maxX - (visible.maxX - 16)) < 32
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let visible = window.screen?.visibleFrame else { return }
        let x = rightAlignedAtResizeStart ? visible.maxX - window.frame.width - 16 : window.frame.minX
        let y = dockAlignedAtResizeStart ? visible.minY : window.frame.minY
        if dockAlignedAtResizeStart || rightAlignedAtResizeStart {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        dockAlignedAtResizeStart = false
        rightAlignedAtResizeStart = false
    }

    @objc private func toggleFloating(_ sender: NSButton) {
        window.level = sender.state == .on ? .floating : .normal
    }

    @objc private func changeLayout(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegment, forKey: "CodexPulseLayout")
        showLayout()
        updateMini(lastUsage)
    }

    private func showLayout() {
        layoutContent()
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, bold: Bool = false,
                       alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        return field
    }

    private func makeSummary() {
        for title in ["Últimas 5 horas", "Últimos 7 dias"] {
            let titleField = label(title, size: 11, color: muted, bold: true)
            let percentField = label("—", size: 12, color: signal, bold: true, alignment: .right)
            let valueField = label("Carregando...", size: 13, color: foreground)
            let bar = ProgressBar(frame: .zero)
            let resetField = label("", size: 10, color: muted)
            for view in [titleField, percentField, valueField, bar, resetField] { summaryView.addSubview(view) }
            summaryTitles.append(titleField)
            summaryPercents.append(percentField)
            summaryValues.append(valueField)
            summaryBars.append(bar)
            summaryResets.append(resetField)
        }
    }

    private func makeLimits() {
        for title in ["5H RESTANTE", "7D RESTANTE"] {
            let titleField = label(title, size: 11, color: muted, bold: true)
            let percentField = label("—", size: 34, color: signal, bold: true)
            let bar = ProgressBar(frame: .zero)
            let remainField = label("", size: 11, color: foreground)
            let resetField = label("", size: 10, color: muted)
            for view in [titleField, percentField, bar, remainField, resetField] { limitsView.addSubview(view) }
            limitTitles.append(titleField)
            limitPercents.append(percentField)
            limitBars.append(bar)
            limitRemains.append(remainField)
            limitResets.append(resetField)
        }
    }

    private func makeActivity() {
        for title in ["ENTRADA", "SAÍDA", "CACHE DE ENTRADA", "EVENTOS DE USO", "SESSÕES COM USO", "ÚLTIMA ATIVIDADE"] {
            let titleField = label(title, size: 10, color: muted, bold: true)
            let valueField = label("—", size: 20, color: foreground, bold: true)
            activityView.addSubview(titleField)
            activityView.addSubview(valueField)
            activityTitles.append(titleField)
            activityValues.append(valueField)
        }
    }

    private func makeMini() {
        for title in ["5 h", "7 dias"] {
            let titleField = label(title, size: 10, color: muted, bold: true)
            let valueField = label("—", size: 16, color: foreground, bold: true)
            let bar = ProgressBar(frame: .zero)
            miniView.addSubview(titleField)
            miniView.addSubview(valueField)
            miniView.addSubview(bar)
            miniTitles.append(titleField)
            miniValues.append(valueField)
            miniBars.append(bar)
        }
        miniNotice = label("Aguardando dados do Codex", size: 11, color: foreground, bold: true,
                           alignment: .center)
        miniView.addSubview(miniNotice)
    }

    private func layoutContent() {
        guard let bounds = window.contentView?.bounds else { return }
        let width = bounds.width
        let height = bounds.height
        let fullWidth = width - 32
        for view in [summaryView, limitsView, activityView, miniView] { view.frame = bounds }

        let mini = height < 175
        let medium = height < 300 && !mini
        let full = !mini && !medium
        summaryView.isHidden = mini || tabs.selectedSegment != 0
        limitsView.isHidden = mini || tabs.selectedSegment != 1
        activityView.isHidden = mini || tabs.selectedSegment != 2
        miniView.isHidden = !mini
        header.isHidden = !full
        statusDot.isHidden = !full
        pin.isHidden = !full
        tabs.isHidden = mini
        footer.isHidden = mini
        for index in 0..<2 {
            summaryResets[index].isHidden = !full
            limitResets[index].isHidden = !full
        }
        for index in 4..<6 {
            activityTitles[index].isHidden = !full
            activityValues[index].isHidden = !full
        }

        if mini {
            let margin: CGFloat = 12
            let gap: CGFloat = 16
            let columnWidth = (width - margin * 2 - gap) / 2
            let rowY = (height - 20) / 2
            for index in 0..<2 {
                let x = margin + CGFloat(index) * (columnWidth + gap)
                let titleWidth: CGFloat = index == 0 ? 27 : 42
                miniTitles[index].frame = NSRect(x: x, y: rowY + 2, width: titleWidth, height: 16)
                miniValues[index].frame = NSRect(x: x + titleWidth + 4, y: rowY,
                                                  width: 52, height: 21)
                let barX = x + titleWidth + 60
                miniBars[index].frame = NSRect(x: barX, y: rowY + 7,
                                                width: columnWidth - (barX - x), height: 7)
            }
            miniNotice.frame = NSRect(x: margin, y: (height - 18) / 2,
                                      width: width - margin * 2, height: 18)
            updateMini(lastUsage)
            return
        }

        if medium {
            tabs.frame = NSRect(x: 12, y: height - 34, width: width - 24, height: 26)
            for index in 0..<2 {
                let offset = CGFloat(index) * 54
                summaryTitles[index].frame = NSRect(x: 12, y: height - 65 - offset, width: width - 110, height: 16)
                summaryPercents[index].frame = NSRect(x: width - 98, y: height - 65 - offset, width: 86, height: 16)
                summaryValues[index].frame = NSRect(x: 12, y: height - 84 - offset, width: width - 24, height: 17)
                summaryBars[index].frame = NSRect(x: 12, y: height - 96 - offset, width: width - 24, height: 5)
            }
            let columnWidth = (width - 36) / 2
            for index in 0..<2 {
                let x = 12 + CGFloat(index) * (columnWidth + 12)
                limitTitles[index].frame = NSRect(x: x, y: height - 65, width: columnWidth, height: 16)
                limitPercents[index].frame = NSRect(x: x, y: height - 108, width: columnWidth, height: 37)
                limitBars[index].frame = NSRect(x: x, y: height - 120, width: columnWidth, height: 5)
                limitRemains[index].frame = NSRect(x: x, y: height - 151, width: columnWidth, height: 18)
            }
            for index in 0..<4 {
                let row = index / 2
                let column = index % 2
                let x = 12 + CGFloat(column) * (columnWidth + 12)
                let offset = CGFloat(row) * 54
                activityTitles[index].frame = NSRect(x: x, y: height - 65 - offset, width: columnWidth, height: 16)
                activityValues[index].frame = NSRect(x: x, y: height - 95 - offset, width: columnWidth, height: 24)
            }
            footer.frame = NSRect(x: 12, y: 5, width: width - 24, height: 14)
            return
        }

        header.frame = NSRect(x: 16, y: height - 35, width: fullWidth - 20, height: 22)
        statusDot.frame = NSRect(x: width - 27, y: height - 28, width: 8, height: 8)
        tabs.frame = NSRect(x: 16, y: height - 73, width: fullWidth, height: 26)

        for index in 0..<2 {
            let offset = CGFloat(index) * 74
            summaryTitles[index].frame = NSRect(x: 16, y: height - 108 - offset, width: fullWidth - 92, height: 17)
            summaryPercents[index].frame = NSRect(x: width - 108, y: height - 108 - offset, width: 92, height: 17)
            summaryValues[index].frame = NSRect(x: 16, y: height - 129 - offset, width: fullWidth, height: 18)
            summaryBars[index].frame = NSRect(x: 16, y: height - 146 - offset, width: fullWidth, height: 8)
            summaryResets[index].frame = NSRect(x: 16, y: height - 168 - offset, width: fullWidth, height: 16)
        }

        let columnWidth = (fullWidth - 12) / 2
        for index in 0..<2 {
            let x = 16 + CGFloat(index) * (columnWidth + 12)
            limitTitles[index].frame = NSRect(x: x, y: height - 109, width: columnWidth, height: 17)
            limitPercents[index].frame = NSRect(x: x, y: height - 167, width: columnWidth, height: 45)
            limitBars[index].frame = NSRect(x: x, y: height - 181, width: columnWidth, height: 8)
            limitRemains[index].frame = NSRect(x: x, y: height - 211, width: columnWidth, height: 18)
            limitResets[index].frame = NSRect(x: x, y: height - 233, width: columnWidth, height: 16)
        }

        for index in 0..<6 {
            let row = index / 2
            let column = index % 2
            let x = 16 + CGFloat(column) * (columnWidth + 12)
            let offset = CGFloat(row) * 52
            activityTitles[index].frame = NSRect(x: x, y: height - 109 - offset, width: columnWidth, height: 16)
            activityValues[index].frame = NSRect(x: x, y: height - 143 - offset, width: columnWidth, height: 27)
        }

        footer.frame = NSRect(x: 16, y: 31, width: fullWidth, height: 16)
        pin.frame = NSRect(x: 12, y: 7, width: 140, height: 21)
    }

    private func refresh() {
        guard !loading, let script = Bundle.main.resourceURL?.appendingPathComponent("usage.py") else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let usage: Usage?
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                usage = process.terminationStatus == 0 ? try? JSONDecoder().decode(Usage.self, from: data) : nil
            } catch {
                usage = nil
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                self.display(usage)
            }
        }
    }

    private func display(_ usage: Usage?) {
        lastUsage = usage
        setSummary(0, tokens: usage?.sessao, percent: usage?.pct_restante_sessao, resetAt: usage?.renova_sessao,
                   estimated: usage?.limite_estimado_sessao == true)
        setSummary(1, tokens: usage?.semana, percent: usage?.pct_restante_semana, resetAt: usage?.renova_semana,
                   estimated: usage?.limite_estimado_semana == true)
        setLimit(0, percent: usage?.pct_restante_sessao, resetAt: usage?.renova_sessao,
                 estimated: usage?.limite_estimado_sessao == true)
        setLimit(1, percent: usage?.pct_restante_semana, resetAt: usage?.renova_semana,
                 estimated: usage?.limite_estimado_semana == true)

        let values: [Int?] = [usage?.entrada_5h, usage?.saida_5h, usage?.cache_5h,
                              usage?.eventos_5h, usage?.sessoes_5h]
        for index in 0..<5 {
            activityValues[index].stringValue = compactNumber(values[index])
            activityValues[index].toolTip = values[index].map { number($0) + (index < 3 ? " tokens" : "") }
        }
        if let date = parseDate(usage?.ultima_atividade) {
            activityValues[5].stringValue = formatDate(date, pattern: "HH:mm:ss")
            activityValues[5].toolTip = formatDate(date, pattern: "dd/MM/yyyy HH:mm:ss")
        } else {
            activityValues[5].stringValue = "—"
            activityValues[5].toolTip = nil
        }
        updateMini(usage)

        let lowestRemaining = [usage?.pct_restante_sessao, usage?.pct_restante_semana].compactMap { $0 }.min()
        let hasBothLimits = usage?.pct_restante_sessao != nil && usage?.pct_restante_semana != nil
        statusDot.layer?.backgroundColor = (hasBothLimits ? colorForRemaining(lowestRemaining) : muted).cgColor
        footer.textColor = hasBothLimits ? muted : foreground
        if !hasBothLimits {
            footer.stringValue = "Sem limites. Abra o Codex para gerar dados."
            footer.toolTip = "O Codex Pulse lê os limites nos arquivos locais de ~/.codex/sessions."
        } else if let usage = usage {
            footer.stringValue = "Atualizado · \(usage.hora)"
            footer.toolTip = nil
        } else {
            footer.stringValue = "Falha ao ler sessões locais"
            footer.toolTip = nil
        }
    }

    private func setSummary(_ index: Int, tokens: Int?, percent: Double?, resetAt: String?, estimated: Bool) {
        summaryValues[index].stringValue = tokens.map { number($0) + " tokens" } ?? "Tokens indisponíveis"
        summaryPercents[index].stringValue = percent.map { "\(Int($0.rounded()))%\(estimated ? "*" : "") restante" } ?? "—"
        summaryPercents[index].toolTip = percent.map { "\(Int((100 - $0).rounded()))% usado" }
        summaryPercents[index].textColor = colorForRemaining(percent)
        summaryBars[index].fraction = CGFloat(max(0, min(percent ?? 0, 100)) / 100)
        summaryBars[index].fillColor = colorForRemaining(percent)
        summaryResets[index].stringValue = estimated ? "Renovação estimada; aguardando Codex" :
            (parseDate(resetAt).map { "Limite renova em " + formatDate($0, pattern: "dd/MM/yyyy HH:mm") }
                ?? "Renovação indisponível")
    }

    private func setLimit(_ index: Int, percent: Double?, resetAt: String?, estimated: Bool) {
        limitPercents[index].stringValue = percent.map { "\(Int($0.rounded()))%\(estimated ? "*" : "")" } ?? "—"
        limitPercents[index].toolTip = percent.map { "\(Int((100 - $0).rounded()))% usado" }
        limitPercents[index].textColor = colorForRemaining(percent)
        limitBars[index].fraction = CGFloat(max(0, min(percent ?? 0, 100)) / 100)
        limitBars[index].fillColor = colorForRemaining(percent)
        if estimated {
            limitRemains[index].stringValue = "Renovação estimada"
            limitResets[index].stringValue = "Aguardando Codex"
        } else if let date = parseDate(resetAt) {
            let seconds = max(0, Int(date.timeIntervalSinceNow))
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            let minutes = (seconds % 3600) / 60
            if seconds == 0 {
                limitRemains[index].stringValue = "Renovação pendente"
            } else if days > 0 {
                limitRemains[index].stringValue = "Renova em \(days)d \(hours)h"
            } else if hours > 0 {
                limitRemains[index].stringValue = "Renova em \(hours)h \(minutes)min"
            } else {
                limitRemains[index].stringValue = "Renova em \(max(1, minutes))min"
            }
            limitResets[index].stringValue = formatDate(date, pattern: "dd/MM HH:mm")
        } else {
            limitRemains[index].stringValue = "Renovação indisponível"
            limitResets[index].stringValue = ""
        }
    }

    private func updateMini(_ usage: Usage?) {
        let percents: [Double?] = [usage?.pct_restante_sessao, usage?.pct_restante_semana]
        let waiting = percents.allSatisfy { $0 == nil }
        miniNotice.isHidden = !waiting
        for index in 0..<2 {
            miniTitles[index].isHidden = waiting
            miniValues[index].isHidden = waiting
            miniBars[index].isHidden = waiting
            let estimated = index == 0 ? usage?.limite_estimado_sessao == true : usage?.limite_estimado_semana == true
            miniValues[index].stringValue = percents[index].map { "\(Int($0.rounded()))%\(estimated ? "*" : "")" } ?? "—"
            miniValues[index].textColor = colorForRemaining(percents[index])
            miniValues[index].toolTip = estimated ? "Renovação estimada; aguardando Codex" :
                percents[index].map { "\(Int((100 - $0).rounded()))% usado" }
            miniBars[index].fraction = CGFloat(max(0, min(percents[index] ?? 0, 100)) / 100)
            miniBars[index].fillColor = colorForRemaining(percents[index])
        }
    }

    private func colorForRemaining(_ percent: Double?) -> NSColor {
        guard let percent = percent else { return muted }
        if percent <= 5 { return critical }
        if percent <= 10 { return danger }
        if percent <= 25 { return orange }
        if percent <= 50 { return yellow }
        return signal
    }

    private func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func compactNumber(_ value: Int?) -> String {
        guard let value = value else { return "—" }
        if value < 10_000 { return number(value) }
        let divisor: Double = value >= 1_000_000 ? 1_000_000 : 1_000
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        let abbreviated = formatter.string(from: NSNumber(value: Double(value) / divisor)) ?? number(value)
        return abbreviated + (divisor == 1_000_000 ? " mi" : " mil")
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func formatDate(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

let app = NSApplication.shared
private let controller = MonitorController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
