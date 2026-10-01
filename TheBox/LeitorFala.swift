import Foundation

/// Entende o valor falado pra Siri: "25", "25 reais", "vinte e cinco reais",
/// "25 e 50", "trinta reais e cinquenta centavos", "mil e duzentos", "12,90"
enum LeitorFala {
    private static let palavras: [String: Double] = [
        "zero": 0, "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
        "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12, "treze": 13, "catorze": 14,
        "quatorze": 14, "quinze": 15, "dezesseis": 16, "dezessete": 17, "dezoito": 18, "dezenove": 19,
        "vinte": 20, "trinta": 30, "quarenta": 40, "cinquenta": 50, "sessenta": 60, "setenta": 70,
        "oitenta": 80, "noventa": 90, "cem": 100, "cento": 100, "duzentos": 200, "duzentas": 200,
        "trezentos": 300, "quatrocentos": 400, "quinhentos": 500, "seiscentos": 600, "setecentos": 700,
        "oitocentos": 800, "novecentos": 900
    ]

    static func valor(_ fala: String) -> Double? {
        let t = fala.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: "r$", with: " ")
        if let v = comDigitos(t) { return v }
        return porExtenso(t)
    }

    /// "25", "25,90", "1.200", "1.200,50", "25 e 50", "25 reais e 50 centavos"
    private static func comDigitos(_ t: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d\.,]*"#) else { return nil }
        let grupos = re.matches(in: t, range: NSRange(t.startIndex..., in: t))
            .compactMap { Range($0.range, in: t).map { String(t[$0]) } }
        guard let primeiro = grupos.first, let inteiro = numero(primeiro) else { return nil }
        // segundo número curto depois de "e"/"com"/"virgula" = centavos ("25 e 50")
        if grupos.count >= 2, !primeiro.contains(","), let cent = Double(grupos[1].filter(\.isNumber)),
           grupos[1].filter(\.isNumber).count <= 2 {
            return inteiro + cent / 100
        }
        return inteiro
    }

    private static func numero(_ s: String) -> Double? {
        var x = s.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if x.contains(",") {
            x = x.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let ponto = x.lastIndex(of: "."), x.distance(from: ponto, to: x.endIndex) == 4 {
            x = x.replacingOccurrences(of: ".", with: "")   // "1.200" = mil e duzentos
        }
        return Double(x)
    }

    /// "vinte e cinco reais e cinquenta centavos", "mil e duzentos", "doze e noventa"
    private static func porExtenso(_ t: String) -> Double? {
        let limpo = t.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ")
        var partes = limpo.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
        // separa reais de centavos
        var reais: [String] = []
        var centavos: [String] = []
        if let i = partes.firstIndex(where: { $0 == "reais" || $0 == "real" || $0 == "virgula" || $0 == "com" }) {
            reais = Array(partes[..<i])
            centavos = Array(partes[(i + 1)...]).filter { $0 != "centavos" && $0 != "centavo" }
        } else {
            partes = partes.filter { $0 != "centavos" && $0 != "centavo" }
            reais = partes
        }
        let r = somar(reais)
        var c = somar(centavos)
        // "doze e noventa" sem a palavra reais: o último número < 100 depois de um "e" vira centavos
        if centavos.isEmpty, let par = separarCentavos(reais) {
            return par.0 + par.1 / 100
        }
        if c >= 100 { c = 0 }
        let total = r + c / 100
        return total > 0 ? total : nil
    }

    private static func somar(_ ws: [String]) -> Double {
        var total = 0.0
        var atual = 0.0
        for w in ws {
            if w == "mil" {
                total += (atual == 0 ? 1 : atual) * 1000
                atual = 0
            } else if let v = palavras[w] {
                atual += v
            }
        }
        return total + atual
    }

    /// "doze e noventa" → (12, 90); "vinte e cinco" continua 25 (não separa dezena + unidade)
    private static func separarCentavos(_ ws: [String]) -> (Double, Double)? {
        guard let i = ws.lastIndex(of: "e"), i > 0, i < ws.count - 1 else { return nil }
        let antes = Array(ws[..<i])
        let depois = Array(ws[(i + 1)...])
        let a = somar(antes)
        let d = somar(depois)
        guard a > 0, d >= 10, d < 100 else { return nil }
        // "vinte e cinco", "trinta e oito": unidade depois de dezena redonda = mesmo número, não centavos
        if a.truncatingRemainder(dividingBy: 10) == 0 && a < 100 && d < 10 { return nil }
        // "cento e vinte", "mil e duzentos" (centena/milhar seguida de dezena) = mesmo número
        if a >= 100 && a.truncatingRemainder(dividingBy: 100) == 0 && d >= 10 && !antes.contains("reais") {
            return nil
        }
        // dezena seguida de dezena redonda ("doze e noventa", "quinze e cinquenta") = reais e centavos
        guard d.truncatingRemainder(dividingBy: 10) == 0 || d >= 10 else { return nil }
        return (a, d)
    }
}
