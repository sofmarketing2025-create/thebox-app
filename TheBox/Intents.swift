import AppIntents
import SwiftData

struct ErroAtalho: Error, CustomLocalizedStringResourceConvertible {
    let texto: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: texto) }
}

struct OpcoesCategoria: DynamicOptionsProvider {
    func results() async throws -> [String] {
        await MainActor.run { () -> [String] in
            guard let c = Store.atual else { return [] }
            let cats = (try? c.mainContext.fetch(FetchDescriptor<Categoria>(sortBy: [SortDescriptor(\.ordem)]))) ?? []
            return cats.filter { $0.tipoRaw == "gasto" }.map(\.nome)
        }
    }
}

struct OpcoesCarteira: DynamicOptionsProvider {
    func results() async throws -> [String] {
        await MainActor.run { () -> [String] in
            guard let c = Store.atual else { return [] }
            let lista = (try? c.mainContext.fetch(FetchDescriptor<Carteira>(sortBy: [SortDescriptor(\.ordem)]))) ?? []
            return lista.map(\.nome)
        }
    }
}

/// Ação "Registrar gasto" do app Atalhos (automação Transação da maquininha)
struct RegistrarGastoIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Salva um gasto no LBO Finanças.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Valor")
    var valor: Double

    @Parameter(title: "Categoria", optionsProvider: OpcoesCategoria())
    var categoria: String

    @Parameter(title: "Pagamento", optionsProvider: OpcoesCarteira())
    var pagamento: String

    @Parameter(title: "Onde foi?")
    var descricao: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$valor) em \(\.$categoria)") {
            \.$pagamento
            \.$descricao
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = Store.atual else {
            throw ErroAtalho(texto: "Entre no LBO Finanças primeiro.")
        }
        let ctx = container.mainContext
        let desc = (descricao ?? "").trimmingCharacters(in: .whitespaces)
        ctx.insert(Transacao(tipo: .gasto, valor: valor, categoria: categoria, carteira: pagamento, descricao: desc))
        try ctx.save()
        Notificacoes.verificarLimite(categoria: categoria, valor: valor, data: .now, ctx: ctx)
        Notificacoes.reagendar(ctx)
        return .result(dialog: IntentDialog(stringLiteral: "\(valor.moeda) registrado em \(categoria)."))
    }
}

/// Abre o app direto na tela de registrar (usado no toque duplo nas costas)
struct NovoRegistroIntent: AppIntent {
    static var title: LocalizedStringResource = "Novo registro"
    static var description = IntentDescription("Abre o LBO Finanças na tela de registrar um gasto.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.abrirRegistro = true
        return .result()
    }
}

struct LBOAtalhos: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NovoRegistroIntent(),
            phrases: [
                "Novo registro no \(.applicationName)",
                "Registrar no \(.applicationName)"
            ],
            shortTitle: "Novo registro",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: RegistrarGastoIntent(),
            phrases: [
                "Registrar gasto no \(.applicationName)"
            ],
            shortTitle: "Registrar gasto",
            systemImageName: "creditcard"
        )
    }
}
