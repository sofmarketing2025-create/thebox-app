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

    @Parameter(title: "Onde foi?")
    var descricao: String?

    @Parameter(title: "Cartão")
    var cartao: String?

    /// Vazio = o app escolhe sozinho pelo nome do lugar
    @Parameter(title: "Categoria", optionsProvider: OpcoesCategoria())
    var categoria: String?

    /// Vazio = o app usa o cartão informado
    @Parameter(title: "Pagamento", optionsProvider: OpcoesCarteira())
    var pagamento: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$valor) em \(\.$descricao)") {
            \.$cartao
            \.$categoria
            \.$pagamento
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = Store.atual else {
            throw ErroAtalho(texto: "Entre no LBO Finanças primeiro.")
        }
        let ctx = container.mainContext
        let desc = (descricao ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = (categoria ?? "").isEmpty ? Categorizador.categoria(para: desc, ctx: ctx) : (categoria ?? "")
        let pag = (pagamento ?? "").isEmpty ? Categorizador.carteira(para: cartao, ctx: ctx) : (pagamento ?? "")
        ctx.insert(Transacao(tipo: .gasto, valor: abs(valor), categoria: cat, carteira: pag, descricao: desc))
        try ctx.save()
        // Mesmo aviso do app: "R$ 20,00 registrado — Drogasil · Saúde"
        Notificacoes.registrado(valor: abs(valor), titulo: desc.isEmpty ? "Gasto" : desc, categoria: cat)
        Notificacoes.verificarLimite(categoria: cat, valor: abs(valor), data: .now, ctx: ctx)
        Notificacoes.reagendar(ctx)
        return .result()
    }
}

/// Ação "Registrar por texto": lê e-mail ou SMS do banco (Pix, transferência) e registra sozinho
struct RegistrarTextoIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar por texto"
    static var description = IntentDescription("Lê o texto de um e-mail ou SMS do banco (Pix, transferência, depósito) e registra o gasto ou a receita no LBO Finanças.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Texto")
    var texto: String

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar a partir de \(\.$texto)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = Store.atual else {
            throw ErroAtalho(texto: "Entre no LBO Finanças primeiro.")
        }
        try LeitorTexto.registrar(texto: texto, ctx: container.mainContext)
        return .result()
    }
}

/// Ação "Registrar comprovante": recebe o comprovante (PDF ou imagem) compartilhado e registra sozinho
struct RegistrarComprovanteIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar comprovante"
    static var description = IntentDescription("Lê um comprovante de Pix ou transferência (PDF ou imagem) e registra o gasto ou a receita no LBO Finanças.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Comprovante", supportedTypeIdentifiers: ["public.image", "com.adobe.pdf"],
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var arquivo: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$arquivo)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = Store.atual else {
            throw ErroAtalho(texto: "Entre no LBO Finanças primeiro.")
        }
        let texto = await LeitorArquivo.texto(de: arquivo)
        try LeitorTexto.registrar(texto: texto, ctx: container.mainContext)
        return .result()
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
