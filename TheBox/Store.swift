import Foundation
import SwiftData

/// Banco de dados local. Cada conta (usuário) tem o seu próprio arquivo no iPhone.
@MainActor
enum Store {
    private static var cache: [String: ModelContainer] = [:]

    private static func url(_ uid: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "lbo-\(uid).store")
    }

    static func container(_ uid: String) -> ModelContainer {
        if let c = cache[uid] { return c }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url(uid))
        do {
            let c = try ModelContainer(for: Transacao.self, Conta.self, Categoria.self, Carteira.self, LimiteMensal.self,
                                       Recorrencia.self, Caixinha.self,
                                       configurations: config)
            cache[uid] = c
            semear(c.mainContext)
            return c
        } catch {
            fatalError("Não foi possível abrir o banco de dados: \(error)")
        }
    }

    /// Banco do usuário logado (usado pelas ações do app Atalhos)
    static var atual: ModelContainer? {
        guard let uid = UserDefaults.standard.string(forKey: "uidAtual") else { return nil }
        return container(uid)
    }

    static func apagar(_ uid: String) {
        cache[uid] = nil
        let base = url(uid).path
        for sufixo in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: base + sufixo)
        }
    }

    /// Categorias e carteiras iniciais de uma conta nova
    static func semear(_ ctx: ModelContext) {
        let n = (try? ctx.fetchCount(FetchDescriptor<Categoria>())) ?? 0
        guard n == 0 else { return }

        let gastos: [(String, String, Bool)] = [
            ("Alimentação", "fork.knife", true),
            ("Transporte", "car.fill", true),
            ("Saúde", "heart.fill", true),
            ("Assinaturas", "rectangle.stack.fill", false),
            ("Lazer", "gamecontroller.fill", false),
            ("Moradia", "house.fill", true),
            ("Educação", "book.fill", true),
            ("Outros", "square.grid.2x2.fill", false)
        ]
        for (i, g) in gastos.enumerated() {
            ctx.insert(Categoria(nome: g.0, icone: g.1, tipo: .gasto, essencial: g.2, ordem: i))
        }

        let receitas: [(String, String)] = [
            ("Salário", "briefcase.fill"),
            ("Freelance", "laptopcomputer"),
            ("Investimentos", "chart.line.uptrend.xyaxis"),
            ("Reembolso", "arrow.uturn.backward"),
            ("Presente", "gift.fill"),
            ("Outros", "square.grid.2x2.fill")
        ]
        for (i, r) in receitas.enumerated() {
            ctx.insert(Categoria(nome: r.0, icone: r.1, tipo: .receita, ordem: i))
        }

        ctx.insert(Carteira(nome: "Pix", tipo: .pix, ordem: 0))
        ctx.insert(Carteira(nome: "Dinheiro", tipo: .dinheiro, ordem: 1))
        ctx.insert(Carteira(nome: "Cartão de crédito", tipo: .credito, ordem: 2))
        try? ctx.save()
    }
}
