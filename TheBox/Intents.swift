import AppIntents
import SwiftData

/// Ação "Registrar gasto" que aparece no app Atalhos.
/// Use na automação "Transação" da Carteira para registrar cada compra com o iPhone.
struct RegistrarGastoIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Salva um gasto no The Box App.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Valor")
    var valor: Double

    @Parameter(title: "Descrição")
    var descricao: String

    @Parameter(title: "Categoria")
    var categoria: Categoria

    @Parameter(title: "Tipo de pagamento")
    var pagamento: Pagamento

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$valor) em \(\.$descricao)") {
            \.$categoria
            \.$pagamento
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Store.container.mainContext
        ctx.insert(Gasto(valor: valor, descricao: descricao, categoria: categoria, pagamento: pagamento))
        try ctx.save()
        let mensagem = "Gasto de \(valor.brl) salvo em \(categoria.nome)."
        return .result(dialog: IntentDialog(stringLiteral: mensagem))
    }
}

struct TheBoxAtalhos: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegistrarGastoIntent(),
            phrases: [
                "Registrar gasto no \(.applicationName)",
                "Novo gasto no \(.applicationName)"
            ],
            shortTitle: "Registrar gasto",
            systemImageName: "creditcard"
        )
    }
}
