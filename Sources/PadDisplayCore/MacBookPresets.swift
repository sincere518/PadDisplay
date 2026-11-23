import Foundation

extension ScreenPreset {
    private struct MacBookScreen {
        let preset: ScreenPreset
        let identifiers: [String]

        init(_ id: String, _ label: String, _ width: Int, _ height: Int,
             hiDPI: Bool = true, identifiers: [String] = []) {
            preset = ScreenPreset(id: "macbook-\(id)", label: label,
                                  spec: DisplaySpec(width: width, height: height, hiDPI: hiDPI))
            self.identifiers = identifiers
        }
    }

    // Apple 的机型识别与技术规格见 README。共用面板的代际合并为一项。
    private static let macBookScreens: [MacBookScreen] = [
        .init("neo", "MacBook Neo 13 英寸", 2408, 1506, identifiers: ["mac17,5"]),
        .init("air13-liquid", "MacBook Air 13 英寸（M2 至 M5）", 2560, 1664,
              identifiers: ["mac14,2", "mac15,12", "mac16,12", "mac17,3"]),
        .init("air15", "MacBook Air 15 英寸（M2 至 M5）", 2880, 1864,
              identifiers: ["mac14,15", "mac15,13", "mac16,13", "mac17,4"]),
        .init("air13-retina", "MacBook Air 13 英寸（Retina，2018 至 M1）", 2560, 1600,
              identifiers: ["macbookair8,1", "macbookair8,2", "macbookair9,1", "macbookair10,1"]),
        .init("air13-2010", "MacBook Air 13 英寸（2010 至 2017）", 1440, 900, hiDPI: false,
              identifiers: ["macbookair3,2", "macbookair4,2", "macbookair5,2", "macbookair6,2", "macbookair7,2"]),
        .init("air13-2008", "MacBook Air 13 英寸（2008 至 2009）", 1280, 800, hiDPI: false,
              identifiers: ["macbookair1,1", "macbookair2,1"]),
        .init("air11", "MacBook Air 11 英寸（2010 至 2015）", 1366, 768, hiDPI: false,
              identifiers: ["macbookair3,1", "macbookair4,1", "macbookair5,1", "macbookair6,1", "macbookair7,1"]),
        .init("pro14-xdr", "MacBook Pro 14 英寸（Liquid Retina XDR）", 3024, 1964,
              identifiers: ["macbookpro18,3", "macbookpro18,4", "mac14,5", "mac14,9", "mac15,3", "mac15,6",
                            "mac15,8", "mac15,10", "mac16,1", "mac16,6", "mac16,8", "mac17,2", "mac17,7",
                            "mac17,9", "mac18,1"]),
        .init("pro16-xdr", "MacBook Pro 16 英寸（Liquid Retina XDR）", 3456, 2234,
              identifiers: ["macbookpro18,1", "macbookpro18,2", "mac14,6", "mac14,10", "mac15,7", "mac15,9",
                            "mac15,11", "mac16,5", "mac16,7", "mac17,6", "mac17,8"]),
        .init("pro14-proled", "MacBook Pro 14 英寸（PROLED XDR）", 3024, 1986,
              identifiers: ["mac17,11", "mac17,13"]),
        .init("pro16-proled", "MacBook Pro 16 英寸（PROLED XDR）", 3472, 2266,
              identifiers: ["mac17,10", "mac17,12"]),
        .init("pro13-retina", "MacBook Pro 13 英寸（Retina，2012 至 M2）", 2560, 1600,
              identifiers: ["macbookpro10,2", "macbookpro11,1", "macbookpro12,1", "macbookpro13,1", "macbookpro13,2",
                            "macbookpro14,1", "macbookpro14,2", "macbookpro15,2", "macbookpro15,4", "macbookpro16,2",
                            "macbookpro16,3", "macbookpro17,1", "mac14,7"]),
        .init("pro13-legacy", "MacBook Pro 13 英寸（非 Retina）", 1280, 800, hiDPI: false,
              identifiers: ["macbookpro5,5", "macbookpro7,1", "macbookpro8,1", "macbookpro9,2"]),
        .init("pro15-retina", "MacBook Pro 15 英寸（Retina，2012 至 2019）", 2880, 1800,
              identifiers: ["macbookpro10,1", "macbookpro11,2", "macbookpro11,3", "macbookpro11,4", "macbookpro11,5",
                            "macbookpro13,3", "macbookpro14,3", "macbookpro15,1", "macbookpro15,3"]),
        .init("pro15-legacy", "MacBook Pro 15 英寸（非 Retina，标准屏）", 1440, 900, hiDPI: false,
              identifiers: ["macbookpro5,1", "macbookpro5,3"]),
        .init("pro15-highres", "MacBook Pro 15 英寸（非 Retina，高分辨率屏）", 1680, 1050, hiDPI: false),
        .init("pro16-intel", "MacBook Pro 16 英寸（Intel，2019）", 3072, 1920,
              identifiers: ["macbookpro16,1", "macbookpro16,4"]),
        .init("pro17-legacy", "MacBook Pro 17 英寸（1680 × 1050）", 1680, 1050, hiDPI: false),
        .init("pro17-highres", "MacBook Pro 17 英寸（1920 × 1200）", 1920, 1200, hiDPI: false,
              identifiers: ["macbookpro5,2", "macbookpro6,1", "macbookpro8,3"]),
        .init("retina12", "MacBook 12 英寸（Retina，2015 至 2017）", 2304, 1440,
              identifiers: ["macbook8,1", "macbook9,1", "macbook10,1"]),
        .init("legacy13", "MacBook 13 英寸（2006 至 2010）", 1280, 800, hiDPI: false,
              identifiers: ["macbook1,1", "macbook2,1", "macbook3,1", "macbook4,1", "macbook5,1", "macbook5,2",
                            "macbook6,1", "macbook7,1"]),
    ]

    public static let macBooks = macBookScreens.map { $0.preset }
    private static let macBookLabels = Dictionary(uniqueKeysWithValues: macBooks.map {
        (normalizedMacBookName($0.label), $0)
    })

    private static let macBookFamily = #"^(?:(?:11|12|13(?:\.[36])?|14(?:\.2)?|15(?:\.3)?|16(?:\.[23])?|17)\s*(?:-?\s*inch|英寸|寸|\")\s*)?macbook(?:\s+(air|pro|neo))?(?=$|[\s(,])"#

    public static func isMacBookName(_ name: String) -> Bool {
        let n = normalizedMacBookName(name)
        return n.range(of: macBookFamily, options: .regularExpression) != nil || macBookIdentifier(n) != nil
    }

    static func macBookSuggestion(for name: String) -> ScreenPreset? {
        let n = normalizedMacBookName(name)
        if let preset = macBookIdentifier(n) { return preset }
        guard let familyMatch = n.range(of: macBookFamily, options: .regularExpression) else { return nil }
        if let preset = macBookLabels[n] { return preset }
        let family = n[familyMatch].split(separator: " ").last ?? ""
        let sizes = Set(matchingParts(#"(?<![a-z0-9.])(?:11|12|13(?:\.[36])?|14(?:\.2)?|15(?:\.3)?|16(?:\.[23])?|17)(?![0-9.])"#, in: n))
        let years = Set(matchingParts(#"(?<![a-z0-9])20[0-9]{2}(?![a-z0-9])"#, in: n))
        let chips = Set(matchingParts(#"(?<![a-z0-9])m[0-9]+(?:\s+(?:pro|max|ultra))?(?![a-z0-9])"#, in: n))
        let m5Variants = chips == ["m5 pro", "m5 max"]
        guard sizes.count <= 1, years.count <= 1, chips.count <= 1 || m5Variants else { return nil }
        let inch = sizes.first.flatMap(Double.init).map(Int.init)
        let year = years.first.flatMap(Int.init)
        guard year.map({ (2006...2026).contains($0) }) != false else { return nil }
        let chip = m5Variants ? "m5 pro" : chips.first
        let nonRetina = n.contains("non-retina") || n.contains("non retina") || n.contains("非 retina") || n.contains("非retina")
        let retina = n.contains("retina") && !nonRetina

        let id: String?
        switch family {
        case "neo":
            id = (inch == nil || sizes.contains("13")) && chip == nil ? "neo" : nil
        case "air":
            switch inch {
            case nil, 13:
                if chip == "m1", !sizes.contains("13.6"), !nonRetina { id = "air13-retina" }
                else if let chip, ["m2", "m3", "m4", "m5"].contains(chip), inch == 13,
                        !sizes.contains("13.3"), !nonRetina { id = "air13-liquid" }
                else if chip == nil, inch == 13 {
                    if sizes.contains("13.6"), !nonRetina, year.map({ $0 >= 2022 }) != false { id = "air13-liquid" }
                    else if sizes.contains("13.6") { id = nil }
                    else if year.map({ (2008...2009).contains($0) }) == true { id = "air13-2008" }
                    else if year.map({ (2010...2017).contains($0) }) == true { id = "air13-2010" }
                    else if !nonRetina, year.map({ $0 >= 2022 }) == true, !sizes.contains("13.3") { id = "air13-liquid" }
                    else if !nonRetina, retina || year.map({ (2018...2020).contains($0) }) == true { id = "air13-retina" }
                    else { id = nil }
                } else { id = nil }
            case 15:
                id = (chip == nil || ["m2", "m3", "m4", "m5"].contains(chip ?? "")) && !nonRetina ? "air15" : nil
            case 11:
                id = chip == nil && !retina ? "air11" : nil
            default: id = nil
            }
        case "pro":
            id = macBookProScreen(name: n, inch: inch, size: sizes.first, year: year, chip: chip,
                                  retina: retina, nonRetina: nonRetina)
        default:
            let namesSize = n[familyMatch].first?.isNumber == true ||
                n[familyMatch.upperBound...].range(of: #"^[\s,(]+(?:retina[\s,]+)?(?:12|13)(?![0-9.])"#, options: .regularExpression) != nil
            if namesSize, sizes.contains("12"), chip == nil, !nonRetina { id = "retina12" }
            else if namesSize, sizes.contains("13"), chip == nil, !retina { id = "legacy13" }
            else { id = nil }
        }
        return id.flatMap { id in macBooks.first { $0.id == "macbook-\(id)" } }
    }

    private static func macBookProScreen(name: String, inch: Int?, size: String?, year: Int?, chip: String?,
                                         retina: Bool, nonRetina: Bool) -> String? {
        switch inch {
        case 13:
            if let chip { return ["m1", "m2"].contains(chip) && !nonRetina ? "pro13-retina" : nil }
            if nonRetina || !retina && year.map({ (2009...2011).contains($0) }) == true { return "pro13-legacy" }
            return retina || year.map({ (2013...2022).contains($0) }) == true ? "pro13-retina" : nil
        case 14, 16:
            guard let inch, !nonRetina else { return nil }
            let proLED = name.contains("proled") || size == "16.3"
            let liquidRetinaXDR = name.contains("liquid retina xdr") || size == "16.2"
            if proLED && liquidRetinaXDR { return nil }
            if proLED { return "pro\(inch)-proled" }
            if inch == 16, chip == nil, !liquidRetinaXDR, name.contains("intel") || year == 2019 { return "pro16-intel" }
            if liquidRetinaXDR { return "pro\(inch)-xdr" }
            // 2026 年的两套 M5 Pro / Max 面板共用芯片名，仅尺寸与芯片不足以区分。
            if chip == "m5 pro" || chip == "m5 max" { return nil }
            let earlierChip = chip.map { $0.range(of: #"^m[1-4](?: (?:pro|max))?$"#, options: .regularExpression) != nil } == true
            if earlierChip || inch == 14 && (chip == "m5" || chip == "m6") ||
                chip == nil && year.map({ (2021...2025).contains($0) }) == true {
                return "pro\(inch)-xdr"
            }
            return nil
        case 15:
            guard chip == nil else { return nil }
            if retina || !nonRetina && year.map({ (2013...2019).contains($0) }) == true { return "pro15-retina" }
            if name.contains("1680"), !name.contains("1440") { return "pro15-highres" }
            if name.contains("1440"), !name.contains("1680") { return "pro15-legacy" }
            return year.map({ (2006...2009).contains($0) }) == true ? "pro15-legacy" : nil
        case 17:
            guard chip == nil else { return nil }
            if name.contains("1680"), !name.contains("1920") { return "pro17-legacy" }
            if name.contains("1920"), !name.contains("1680") { return "pro17-highres" }
            if year == 2006 { return "pro17-legacy" }
            return year.map({ (2009...2011).contains($0) }) == true ? "pro17-highres" : nil
        default: return nil
        }
    }

    private static func macBookIdentifier(_ name: String) -> ScreenPreset? {
        let identifier = name.replacingOccurrences(of: #"\s*,\s*"#, with: ",", options: .regularExpression)
        return macBookScreens.first { $0.identifiers.contains(identifier) }?.preset
    }

    private static func normalizedMacBookName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[‐‑‒–—−]"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[“”″]"#, with: "\"", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchingParts(_ pattern: String, in name: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: name, range: NSRange(name.startIndex..., in: name)).compactMap { match in
            Range(match.range, in: name).map { String(name[$0]) }
        }
    }
}
