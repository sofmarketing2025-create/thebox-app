import Foundation
import SwiftData

/// Lê o texto de um e-mail ou SMS do banco ("Pix enviado de R$ 50,00 para FULANO") e descobre
/// valor, se é gasto ou receita e o nome de quem pagou/recebeu.
@MainActor
enum LeitorTexto {
    struct Resultado {
        var valor: Double
        var tipo: TipoTransacao
        var nome: String
        var texto: String
    }

    private static let saida = ["pix enviado", "enviou", "voce enviou", "transferencia enviada", "transferiu", "pagamento",
                                "pagou", "compra", "debitado", "debito de", "saque", "boleto pago", "pix realizado",
                                "transferencia realizada", "pix feito", "foi enviado", "enviado"]
    private static let entrada = ["pix recebido", "recebeu", "voce recebeu", "recebimento", "transferencia recebida",
                                  "deposito", "creditado", "credito em conta", "salario", "rendimento", "foi recebido", "recebido"]

    /// Lê o texto e registra o gasto/receita. Sempre avisa o que aconteceu.
    static func registrar(texto: String, ctx: ModelContext) throws {
        UserDefaults.standard.set(String(texto.prefix(3000)), forKey: "ultimoTextoLido")
        UserDefaults.standard.set(Date.now, forKey: "ultimoTextoData")
        guard let r = ler(texto) else {
            Notificacoes.agora("Não achei o valor",
                               texto.isEmpty ? "O comprovante chegou vazio. Tente compartilhar como imagem."
                                             : "Veja o texto recebido em Config → Automação → Pix e mande pro suporte.")
            return
        }
        if duplicado(r, ctx: ctx) {
            Notificacoes.agora("Já estava registrado", "\(r.valor.moeda) já entrou nos últimos 30 minutos.")
            return
        }
        let cat = categoria(r, ctx: ctx)
        let cart = carteira(r, ctx: ctx)
        ctx.insert(Transacao(tipo: r.tipo, valor: r.valor, categoria: cat, carteira: cart, descricao: r.nome))
        try ctx.save()
        Notificacoes.registrado(valor: r.valor, titulo: r.nome.isEmpty ? r.tipo.nome : r.nome, categoria: cat)
        if r.tipo == .gasto {
            Notificacoes.verificarLimite(categoria: cat, valor: r.valor, data: .now, ctx: ctx)
        }
        Notificacoes.reagendar(ctx)
    }

    static func ler(_ bruto: String) -> Resultado? {
        let texto = bruto.replacingOccurrences(of: "\u{00a0}", with: " ")
        guard let valor = achaValor(texto), valor > 0 else { return nil }
        let t = Categorizador.normalizar(texto)
        let ehSaida = saida.contains { t.contains($0) }
        let ehEntrada = entrada.contains { t.contains($0) }
        let tipo: TipoTransacao = (ehEntrada && !ehSaida) ? .receita : .gasto
        return Resultado(valor: valor, tipo: tipo, nome: achaNome(texto, tipo: tipo), texto: t)
    }

    /// Primeiro "R$ 1.234,56" do texto
    static func achaValor(_ s: String) -> Double? {
        let padrao = #"R\$\s*-?\s*(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:,\d{1,2})?)"#
        guard let re = try? NSRegularExpression(pattern: padrao),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        let numero = String(s[r]).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(numero)
    }

    /// Nome depois de "para"/"em" (gasto) ou "de"/"por" (receita), sem pegar o próprio valor
    static func achaNome(_ s: String, tipo: TipoTransacao) -> String {
        // Comprovante (ex.: Nubank): "Destino ... Nome\nFULANO" (ou "Origem" quando é receita)
        if let r = s.range(of: tipo == .gasto ? "Destino" : "Origem", options: .caseInsensitive) {
            let linhas = s[r.upperBound...].split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let i = linhas.firstIndex(where: { $0.lowercased() == "nome" }), i + 1 < linhas.count {
                return linhas[i + 1]
            }
            if let l = linhas.first(where: { $0.lowercased().hasPrefix("nome ") }) {
                return String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        let fimNome = #"(?=\s*(?:[\.,;:\n\(]|\bno valor\b|\bvia\b|\bcom\b|\bem \d|\bno dia\b|\bàs\b|\bas \d|\bpara\b|\bno cart|$))"#
        let preposicoes = tipo == .gasto ? ["para", "pra", "em", "no", "na"] : ["de", "por"]
        for p in preposicoes {
            let padrao = #"(?i)\b"# + p + #"\s+(?!R\$)(?!\d)([^\n]{2,50}?)"# + fimNome
            guard let re = try? NSRegularExpression(pattern: padrao),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: 1), in: s) else { continue }
            var nome = String(s[r]).trimmingCharacters(in: .whitespaces)
            for lixo in [" com sucesso", " foi", " realizado", " realizada"] {
                if let x = nome.range(of: lixo, options: .caseInsensitive) { nome = String(nome[..<x.lowerBound]) }
            }
            let n = Categorizador.normalizar(nome)
            let ignorar = ["sua conta", "seu cartao", "o cartao", "a conta", "cartao", "conta", "voce", "pix", "transferencia"]
            if nome.count >= 2 && !ignorar.contains(where: { n.hasPrefix($0) }) { return nome }
        }
        return ""
    }

    /// Evita registrar duas vezes (ex.: e-mail e SMS do mesmo Pix, ou a compra que já veio pela maquininha)
    static func duplicado(_ r: Resultado, ctx: ModelContext) -> Bool {
        let limite = Date.now.addingTimeInterval(-30 * 60)
        var busca = FetchDescriptor<Transacao>(predicate: #Predicate { $0.data > limite })
        busca.fetchLimit = 50
        let recentes = (try? ctx.fetch(busca)) ?? []
        return recentes.contains { $0.tipoRaw == r.tipo.rawValue && abs($0.valor - r.valor) < 0.01 }
    }

    static func categoria(_ r: Resultado, ctx: ModelContext) -> String {
        if r.tipo == .gasto { return Categorizador.categoria(para: r.nome, ctx: ctx) }
        let cats = ((try? ctx.fetch(FetchDescriptor<Categoria>(sortBy: [SortDescriptor(\.ordem)]))) ?? [])
            .filter { $0.tipoRaw == TipoTransacao.receita.rawValue }.map(\.nome)
        if r.texto.contains("salario"), let s = cats.first(where: { Categorizador.normalizar($0).contains("salario") }) { return s }
        if r.texto.contains("rendimento"), let s = cats.first(where: { Categorizador.normalizar($0).contains("invest") }) { return s }
        return cats.first(where: { $0 == "Outros" }) ?? cats.first ?? "Outros"
    }

    static func carteira(_ r: Resultado, ctx: ModelContext) -> String {
        let lista = (try? ctx.fetch(FetchDescriptor<Carteira>(sortBy: [SortDescriptor(\.ordem)]))) ?? []
        if r.texto.contains("pix"), let c = lista.first(where: { $0.tipo == .pix }) { return c.nome }
        if r.texto.contains("debito"), let c = lista.first(where: { $0.tipo == .debito }) { return c.nome }
        if r.texto.contains("credito") || r.texto.contains("cartao"),
           let c = lista.first(where: { $0.tipo == .credito }) { return c.nome }
        return lista.first(where: { $0.tipo == .pix })?.nome ?? lista.first?.nome ?? ""
    }
}
