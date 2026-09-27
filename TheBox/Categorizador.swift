import Foundation
import SwiftData

/// Decide sozinho a categoria e o meio de pagamento de um gasto vindo da maquininha,
/// pra automação registrar sem abrir nenhuma pergunta.
@MainActor
enum Categorizador {
    static func normalizar(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: ptBR)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Palavras no nome do estabelecimento → categorias possíveis (usa a primeira que existir)
    private static let regras: [([String], [String])] = [
        (["farmacia", "drogaria", "droga raia", "drogasil", "pague menos", "panvel", "drogao", "ultrafarma"],
         ["Farmácia", "Saúde"]),
        (["supermerc", "mercado", "atacad", "assai", "carrefour", "pao de acucar", "hortifruti", "sacolao",
          "acougue", "mercearia", "atacarejo", "sams club", "makro", "dia %", "oba"],
         ["Mercado", "Alimentação"]),
        (["ifood", "restaurante", "lanchonete", "lanches", "padaria", "panificadora", "burger", "pizza", "cafe",
          "mcdonald", "subway", "sushi", "churrasc", "doceria", "sorvete", "outback", "starbucks", "habib",
          "spoleto", "giraffas", "bob s", "rappi", "ze delivery", "espetinho", "acai"],
         ["Alimentação"]),
        (["posto", "combust", "shell", "ipiranga", "petrobras", "br mania", "uber", "99app", "99 pop", "99pop",
          "estaciona", "pedagio", "sem parar", "veloe", "conectcar", "metro", "onibus", "cabify", "indrive",
          "autopeca", "oficina", "lava jato", "lavacar"],
         ["Transporte"]),
        (["netflix", "spotify", "disney", "prime video", "amazon prime", "hbo", "youtube", "apple.com", "icloud",
          "google one", "deezer", "globoplay", "chatgpt", "openai", "anthropic", "claude.ai", "canva", "adobe",
          "microsoft", "paramount", "crunchyroll"],
         ["Assinaturas"]),
        (["cinema", "cinemark", "ingresso", "teatro", "steam", "playstation", "xbox", "nintendo", "boteco",
          "balada", "parque", "hotel", "airbnb", "booking", "decolar", "latam", "gol linhas", "azul linhas"],
         ["Lazer"]),
        (["hospital", "clinica", "laborat", "medic", "odonto", "dentista", "otica", "academia", "smart fit",
          "smartfit", "psicolog", "fisioter", "unimed", "hapvida", "amil"],
         ["Saúde"]),
        (["escola", "faculdade", "universidade", "curso", "livraria", "udemy", "alura", "colegio", "papelaria"],
         ["Educação"]),
        (["aluguel", "condominio", "enel", "cemig", "copel", "cpfl", "light", "energisa", "sabesp", "saneamento",
          "leroy", "telhanorte", "madeira", "material de constr", "vivo", "claro", "tim ", "oi fibra", "net servicos"],
         ["Moradia"])
    ]

    static func categoria(para descricao: String, ctx: ModelContext) -> String {
        let cats = ((try? ctx.fetch(FetchDescriptor<Categoria>(sortBy: [SortDescriptor(\.ordem)]))) ?? [])
            .filter { $0.tipoRaw == TipoTransacao.gasto.rawValue }
        let nomes = cats.map(\.nome)
        let padrao = nomes.contains("Outros") ? "Outros" : (nomes.first ?? "Outros")
        let d = normalizar(descricao)
        guard !d.isEmpty else { return padrao }

        // 1. Aprendizado: a última vez que você registrou esse mesmo lugar
        var busca = FetchDescriptor<Transacao>(sortBy: [SortDescriptor(\.data, order: .reverse)])
        busca.fetchLimit = 800
        let recentes = (try? ctx.fetch(busca)) ?? []
        if let t = recentes.first(where: {
            $0.tipoRaw == TipoTransacao.gasto.rawValue && normalizar($0.descricao) == d && nomes.contains($0.categoria)
        }) {
            return t.categoria
        }

        // 2. Uma categoria sua com o mesmo nome do lugar (ex.: categoria "Uber")
        if let c = nomes.first(where: { let n = normalizar($0); return n.count >= 3 && d.contains(n) }) {
            return c
        }

        // 3. Palavras-chave
        for (palavras, alvos) in regras where palavras.contains(where: { d.contains($0) }) {
            if let alvo = alvos.first(where: { nomes.contains($0) }) { return alvo }
        }
        return padrao
    }

    /// Acha a carteira pelo nome do cartão da Carteira da Apple. Se não existir, cria.
    static func carteira(para cartao: String?, ctx: ModelContext) -> String {
        let lista = (try? ctx.fetch(FetchDescriptor<Carteira>(sortBy: [SortDescriptor(\.ordem)]))) ?? []
        let nome = (cartao ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !nome.isEmpty {
            let c = normalizar(nome)
            if let w = lista.first(where: {
                let n = normalizar($0.nome)
                return !n.isEmpty && (c.contains(n) || n.contains(c))
            }) {
                return w.nome
            }
            ctx.insert(Carteira(nome: nome, tipo: .credito, ordem: (lista.map(\.ordem).max() ?? 0) + 1))
            return nome
        }
        return lista.first(where: { $0.tipo == .credito })?.nome ?? lista.first?.nome ?? ""
    }
}
