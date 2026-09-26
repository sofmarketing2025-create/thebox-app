import Foundation
import SwiftData

/// Exporta e importa transações em CSV (separado por ponto e vírgula, abre no Excel)
enum CSV {
    private static let cabecalho = "data;tipo;valor;categoria;pagamento;descricao"

    private static var formato: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }

    private static func limpar(_ s: String) -> String {
        s.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ")
    }

    static func gerar(_ transacoes: [Transacao]) -> URL? {
        let f = formato
        var linhas = [cabecalho]
        for t in transacoes {
            let valor = String(format: "%.2f", t.valor).replacingOccurrences(of: ".", with: ",")
            linhas.append([f.string(from: t.data), t.tipo.rawValue, valor,
                           limpar(t.categoria), limpar(t.carteira), limpar(t.descricao)].joined(separator: ";"))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "lbo-financas-transacoes.csv")
        do {
            try linhas.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    @MainActor
    static func importar(_ url: URL, ctx: ModelContext) -> Int {
        let acesso = url.startAccessingSecurityScopedResource()
        defer { if acesso { url.stopAccessingSecurityScopedResource() } }
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let f = formato
        var n = 0
        for linha in texto.components(separatedBy: .newlines) {
            let campos = linha.components(separatedBy: ";")
            guard campos.count >= 3, campos[0] != "data",
                  let data = f.date(from: campos[0].trimmingCharacters(in: .whitespaces)),
                  let valor = lerValor(campos[2]), valor > 0 else { continue }
            let tipo: TipoTransacao = campos[1].lowercased().hasPrefix("rec") ? .receita : .gasto
            ctx.insert(Transacao(tipo: tipo, valor: valor,
                                 categoria: campos.count > 3 ? campos[3] : "Outros",
                                 carteira: campos.count > 4 ? campos[4] : "",
                                 descricao: campos.count > 5 ? campos[5] : "",
                                 data: data))
            n += 1
        }
        try? ctx.save()
        return n
    }
}
