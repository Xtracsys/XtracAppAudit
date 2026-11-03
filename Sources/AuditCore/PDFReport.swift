import Foundation
import CoreGraphics
import CoreText
import ImageIO

public enum PDFReport {
    public static func data(_ snapshot: AuditSnapshot, baseline: AuditSnapshot?, policy: AuditPolicy) throws -> Data {
        let findings = snapshot.findings ?? FindingEngine.evaluate(snapshot, baseline: baseline, policy: policy)
        let changes = baseline.map { AuditComparison.changes(baseline: $0, current: snapshot) } ?? []
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw AuditFileError.invalid("Cannot create PDF context.") }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 42, width: CGFloat = 511, usable: CGFloat = 724
        var used: CGFloat = 0, pages = 0, pageOpen = false
        let bodyFont = CTFontCreateWithName("HelveticaNeue" as CFString, 9.5, nil)
        let headingFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 14, nil)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 25, nil)
        let monoFont = CTFontCreateWithName("Menlo" as CFString, 7.5, nil)
        let rust = CGColor(red: 178 / 255, green: 70 / 255, blue: 48 / 255, alpha: 1)
        func text(_ value: String, font: CTFont, color: CGColor = CGColor(gray: 0.13, alpha: 1)) -> NSAttributedString {
            NSAttributedString(string: value.replacingOccurrences(of: "\0", with: "") + "\n", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
        }
        func line(_ value: String, y: CGFloat, font: CTFont) {
            context.textMatrix = .identity; context.textPosition = CGPoint(x: margin, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(text(value, font: font)), context)
        }
        func newPage() throws {
            guard pages < 500, !Task.isCancelled else { throw AuditFileError.invalid("PDF page limit reached or export cancelled.") }
            if pageOpen { context.endPDFPage() }
            context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: [Double(0), 0, 595, 842], length: 32)] as CFDictionary)
            // Explicit media box avoids dependence on printer configuration.
            pageOpen = true; pages += 1; used = 0
            line("XTRACSYS / APP AUDIT  •  " + snapshot.captured.formatted(date: .abbreviated, time: .shortened), y: page.height - 27, font: monoFont)
            line("Local evidence · not a malware/CVE verdict                                  Page \(pages)", y: 23, font: monoFont)
            context.setStrokeColor(CGColor(gray: 0.83, alpha: 1)); context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: page.height - 36)); context.addLine(to: CGPoint(x: page.width - margin, y: page.height - 36)); context.strokePath()
        }
        var pendingHeading: NSAttributedString?
        func block(_ value: NSAttributedString) throws {
            let hadHeading = pendingHeading != nil
            let content = NSMutableAttributedString(string: "")
            if let heading = pendingHeading { content.append(heading); pendingHeading = nil }
            content.append(value)
            let framesetter = CTFramesetterCreateWithAttributedString(content)
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: content.length), nil, CGSize(width: width, height: 100000), nil)
            if !pageOpen || (measured.height <= usable && used + ceil(measured.height) + 10 > usable) || (hadHeading && measured.height > usable && used > 0) { try newPage() }
            var offset = 0
            while offset < content.length {
                if used >= usable - 12 { try newPage() }
                let height = usable - used
                let rect = CGRect(x: margin, y: page.height - 54 - used - height, width: width, height: height)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: rect, transform: nil), nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 && used > 0 { try newPage(); continue }
                guard visible.length > 0 else { throw AuditFileError.invalid("PDF layout could not advance.") }
                context.textMatrix = .identity; CTFrameDraw(frame, context)
                let drawHeight = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, visible, nil, CGSize(width: width, height: 100000), nil).height
                offset += visible.length; used += ceil(drawHeight) + 10
                if offset < content.length { try newPage() }
            }
        }
        func section(_ title: String) throws { pendingHeading = text(title, font: headingFont, color: rust) }
        func detail(_ title: String, _ paragraphs: [String]) throws {
            let content = NSMutableAttributedString(string: "")
            content.append(text(title, font: headingFont, color: rust))
            for paragraph in paragraphs { content.append(text(paragraph, font: bodyFont)) }
            try block(content)
        }
        try block(text("App Audit report", font: titleFont, color: rust))
        if let data = Brand.logoData, let source = CGImageSourceCreateWithData(data as CFData, nil), let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            context.draw(logo, in: CGRect(x: 488, y: 761, width: 60, height: 56))
        }
        if snapshot.redacted == true { try detail("REDACTED EXPORT", ["Personal paths, web addresses and free-text context/exception notes omitted. Review before sharing: app names, identifiers, versions and evidence may still be sensitive."]) }
        try detail("Audit overview", ["Captured: \(snapshot.captured.formatted())", "\(snapshot.apps.count) applications · \(findings.filter { $0.severity == .action }.count) action needed · \(findings.filter { $0.severity == .review }.count) review · \(findings.filter { $0.severity == .unknown }.count) unknown", "Scan folders: \(snapshot.roots.joined(separator: "; "))", "Security \(snapshot.evidence.count)/\(snapshot.apps.count); integrity \(snapshot.integrity?.count ?? 0)/\(snapshot.apps.count); update observations/routes \(snapshot.updates.count)/\(snapshot.apps.count). Policy \(policy.enabled ? "enabled" : "disabled"), \(policy.rules.count) app rules. Baseline: \(baseline?.captured.formatted() ?? "none")", "Unknown is not a safe/unsafe verdict. Receipt dates describe installer events, not original installation proof. SHA-256 covers the main executable, Info.plist and CodeResources when readable, not every bundle file. Imported evidence is unauthenticated historical data."])
        try detail("Audit context, age evidence and network mode", [snapshot.workflowSummary])
        if !snapshot.warnings.isEmpty { try detail("Scan warnings", snapshot.warnings) }
        if let baseline { let notes = AuditComparison.scopeNotes(baseline: baseline, roots: snapshot.roots, warnings: snapshot.warnings); if !notes.isEmpty { try detail("Comparison coverage", notes) } }
        try section("Findings and suggested next steps")
        if findings.isEmpty { try block(text("No findings recorded. Review coverage before interpreting this result.", font: bodyFont)) }
        for item in findings {
            var paragraphs = [item.app + " · " + item.path, "Evidence: " + String(item.evidence.prefix(1800)), "Suggested next step: " + item.nextStep]
            if let value = item.exception { paragraphs += [value.status(for: item, now: snapshot.captured), value.description] } else { paragraphs.append("Decision: Unreviewed") }
            try detail(item.severity.rawValue + " · " + item.title, paragraphs)
        }
        try section("Changes from baseline")
        if changes.isEmpty { try block(text(baseline == nil ? "No comparison baseline selected." : "No comparable changes recorded.", font: bodyFont)) }
        for item in changes { try detail(item.kind + " · " + item.name, [item.summary]) }
        try section("Application evidence")
        for app in snapshot.apps {
            let security = snapshot.evidence[app.id], update = UpdateRouting.result(app, recorded: snapshot.updates[app.id], at: snapshot.captured), integrity = snapshot.integrity?[app.id]
            let content = NSMutableAttributedString(string: "")
            content.append(text(app.name + " · " + app.version + " / " + app.build, font: headingFont, color: rust))
            content.append(text(snapshot.workflowEvidence(app), font: bodyFont))
            let manual = snapshot.developerLinks?[DeveloperLinks.key(app)] ?? DeveloperLinks()
            for (label, address) in manual.entries { content.append(text("User supplied · " + label + ": " + address, font: bodyFont)) }
            if manual.website.isEmpty, let homepage = update?.homepage { content.append(text("Catalog homepage: " + homepage, font: bodyFont)) }
            let updateChecked = (app.classification.managedByMacOS || app.appStore) ? "Availability not checked; channel only" : (update?.checked.formatted() ?? "Not checked")
            let values = ["Bundle ID: \(app.bundleID) · architecture: \(app.architecture ?? "Unknown")", "Path: \(app.path)", "Install evidence: \((security?.installDate ?? app.created)?.formatted() ?? "Unknown"). \(security?.installSource ?? "Filesystem creation estimate; receipts not checked")", "Last used: \(app.lastUsed?.formatted() ?? "Unknown") · Spotlight best effort", "Signature: \(security?.signature ?? "Not checked"). Publisher: \(security?.publisher ?? "Not collected")", "Team: \(security?.teamID ?? "Unknown"). Signed ID: \(security?.signedID ?? "Unknown")", "Gatekeeper: \(security?.gatekeeper ?? "Not checked"). Notarization: \(security?.notarization ?? "Not checked")", "Security checked: \(security?.checked.formatted() ?? "Not checked"). Receipts: \(security?.receipts.map(\.packageID).joined(separator: "; ") ?? "Not checked")", "Update: \(update?.status ?? "Not checked"). Latest: \(update?.latest ?? "Unknown")", "Update identity: \(update?.identity ?? "Not checked"). Source: \(update?.source ?? "None")", "Update checked: \(updateChecked)"]
            for value in values { content.append(text(value, font: bodyFont)) }
            if let integrity {
                for key in integrity.hashes.keys.sorted() { content.append(text("SHA-256 \(key): \(integrity.hashes[key] ?? "")", font: monoFont)) }
                for key in integrity.errors.keys.sorted() { content.append(text("Unavailable \(key): \(integrity.errors[key] ?? "")", font: bodyFont)) }
            } else { content.append(text("Integrity: not collected", font: bodyFont)) }
            try block(content)
        }
        if pageOpen { context.endPDFPage() }
        context.closePDF()
        guard output.length > 100 else { throw AuditFileError.invalid("Empty PDF output.") }
        return output as Data
    }
}
