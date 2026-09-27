import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ConfigView: View {
    enum Folha: String, Identifiable {
        case nome, tema, catGasto, catReceita, carteiras, moeda, toqueDuplo, maquininha
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var ctx
    @Environment(Sessao.self) private var sessao
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @Query(sort: \Transacao.data, order: .reverse) private var transacoes: [Transacao]
    @AppStorage("nomeUsuario") private var nome = ""
    @AppStorage("emailUsuario") private var email = ""
    @AppStorage("tema") private var tema = "sistema"
    @AppStorage("moeda") private var moeda = "BRL"
    @AppStorage("avisoContas") private var avisoContas = true
    @AppStorage("lembreteRegistro") private var lembreteRegistro = true
    @AppStorage("resumoSemana") private var resumoSemana = true
    @AppStorage("alertasInteligentes") private var alertas = true
    @AppStorage("diasAntes") private var diasAntes = 2
    @AppStorage("faceID") private var faceID = false

    @State private var folha: Folha?
    @State private var exportar: ArquivoExportado?
    @State private var importar = false
    @State private var mensagem: String?
    @State private var confirmarSair = false
    @State private var confirmarExcluir = false

    private var iniciais: String {
        let partes = nome.split(separator: " ").prefix(2)
        let r = partes.compactMap { $0.first }.map { String($0) }.joined().uppercased()
        return r.isEmpty ? "?" : r
    }
    private var nomeTema: String { ["claro": "Claro", "escuro": "Escuro"][tema] ?? "Sistema" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Cabecalho(sub: "Preferências", titulo: "Config")
                    .padding(.bottom, 20)

                Button { folha = .nome } label: {
                    HStack(spacing: 18) {
                        Text(iniciais)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.sobreDestaque)
                            .frame(width: 72, height: 72)
                            .background(Color.destaque, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nome.isEmpty ? "Seu nome" : nome).font(.system(size: 20, weight: .semibold))
                            Text("Toque para editar").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .cartao(18)
                }
                .buttonStyle(.plain)

                Secao("Aparência") {
                    LinhaConfig(titulo: "Tema", valor: nomeTema) { folha = .tema }
                }

                Secao("Registro") {
                    LinhaConfig(titulo: "Categorias de gasto",
                                valor: "\(categorias.filter { $0.tipo == .gasto }.count) ativas") { folha = .catGasto }
                    Divisor()
                    LinhaConfig(titulo: "Categorias de receita",
                                valor: "\(categorias.filter { $0.tipo == .receita }.count) ativas") { folha = .catReceita }
                    Divisor()
                    LinhaConfig(titulo: "Carteiras", valor: "\(carteiras.count) ativas") { folha = .carteiras }
                    Divisor()
                    LinhaConfig(titulo: "Moeda padrão", valor: "\(moeda) · \(Moeda.atual.simbolo)") { folha = .moeda }
                }

                Secao("Notificações") {
                    LinhaToggle(titulo: "Contas próximas do vencimento", ligado: $avisoContas)
                    if avisoContas {
                        Stepper(value: $diasAntes, in: 0...10) {
                            Text(diasAntes == 0 ? "Só no dia do vencimento" :
                                    (diasAntes == 1 ? "Avisar 1 dia antes" : "Avisar \(diasAntes) dias antes"))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)
                    }
                    Divisor()
                    LinhaToggle(titulo: "Lembretes de registro", ligado: $lembreteRegistro)
                    Divisor()
                    LinhaToggle(titulo: "Resumo da semana", ligado: $resumoSemana)
                    Divisor()
                    LinhaToggle(titulo: "Alertas inteligentes", ligado: $alertas)
                }

                Secao("Segurança") {
                    LinhaToggle(titulo: "Bloqueio com Face ID", ligado: $faceID)
                }

                Secao("Automação") {
                    LinhaConfig(titulo: "Toque duplo nas costas", icone: "hand.tap") { folha = .toqueDuplo }
                    Divisor()
                    LinhaConfig(titulo: "Registrar pela maquininha", icone: "wave.3.right") { folha = .maquininha }
                }

                Secao("Dados") {
                    LinhaConfig(titulo: "Exportar transações (CSV)", icone: "square.and.arrow.up") {
                        if let url = CSV.gerar(transacoes) { exportar = ArquivoExportado(url: url) }
                    }
                    Divisor()
                    LinhaConfig(titulo: "Importar transações (CSV)", icone: "square.and.arrow.down") { importar = true }
                }

                Secao("Sobre") {
                    LinhaConfig(titulo: "Versão do app", valor: versao, seta: false) {}
                }

                Secao("Conta") {
                    if !email.isEmpty {
                        LinhaConfig(titulo: email, seta: false) {}
                        Divisor()
                    }
                    LinhaConfig(titulo: "Sair", icone: "rectangle.portrait.and.arrow.right", perigo: true) { confirmarSair = true }
                }

                LinhaConfig(titulo: "Excluir conta", icone: "trash", perigo: true) { confirmarExcluir = true }
                    .padding(.horizontal, 22)
                    .background(Color.cartao, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.borda))
                    .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.fundo)
        .onChange(of: avisoContas) { _, _ in Notificacoes.reagendar(ctx) }
        .onChange(of: diasAntes) { _, _ in Notificacoes.reagendar(ctx) }
        .onChange(of: lembreteRegistro) { _, _ in Notificacoes.reagendar(ctx) }
        .onChange(of: resumoSemana) { _, _ in Notificacoes.reagendar(ctx) }
        .onChange(of: faceID) { _, ligado in
            if ligado {
                Task { if !(await Biometria.autenticar()) { faceID = false } }
            }
        }
        .sheet(item: $folha) { f in
            switch f {
            case .nome: NomeSheet(nome: $nome)
            case .tema: TemaSheet(tema: $tema)
            case .catGasto: CategoriasSheet(tipo: .gasto)
            case .catReceita: CategoriasSheet(tipo: .receita)
            case .carteiras: CarteirasSheet()
            case .moeda: MoedaSheet(moeda: $moeda)
            case .toqueDuplo: GuiaView(guia: .toqueDuplo)
            case .maquininha: GuiaView(guia: .maquininha)
            }
        }
        .sheet(item: $exportar) { a in Compartilhar(itens: [a.url]) }
        .fileImporter(isPresented: $importar, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { resultado in
            if case let .success(url) = resultado {
                let n = CSV.importar(url, ctx: ctx)
                mensagem = n > 0 ? "\(n) transações importadas." : "Nenhuma transação encontrada no arquivo."
            }
        }
        .alert(mensagem ?? "", isPresented: Binding(get: { mensagem != nil }, set: { if !$0 { mensagem = nil } })) {
            Button("OK") { mensagem = nil }
        }
        .confirmationDialog("Sair da sua conta?", isPresented: $confirmarSair, titleVisibility: .visible) {
            Button("Sair", role: .destructive) { Task { await sessao.sair() } }
        } message: {
            Text("Seus dados continuam salvos neste iPhone e voltam quando você entrar de novo.")
        }
        .confirmationDialog("Excluir sua conta?", isPresented: $confirmarExcluir, titleVisibility: .visible) {
            Button("Excluir conta e dados", role: .destructive) {
                Task {
                    do { try await sessao.excluirConta() } catch { mensagem = Sessao.mensagem(error) }
                }
            }
        } message: {
            Text("Isso apaga sua conta e todos os dados deste iPhone. Não dá pra desfazer.")
        }
    }

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
    }
}

struct ArquivoExportado: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Peças da tela de Config

struct Secao<Conteudo: View>: View {
    let titulo: String
    @ViewBuilder var conteudo: () -> Conteudo

    init(_ titulo: String, @ViewBuilder conteudo: @escaping () -> Conteudo) {
        self.titulo = titulo
        self.conteudo = conteudo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo.uppercased())
                .font(.system(size: 14, weight: .semibold)).tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            VStack(spacing: 0) { conteudo() }
                .padding(.horizontal, 22)
                .padding(.vertical, 4)
                .background(Color.cartao, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.borda))
        }
        .padding(.top, 26)
    }
}

struct Divisor: View {
    var body: some View { Divider().overlay(Color.borda) }
}

struct LinhaConfig: View {
    let titulo: String
    var valor: String? = nil
    var icone: String? = nil
    var perigo = false
    var seta = true
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                Text(titulo)
                    .font(.system(size: 17))
                    .foregroundStyle(perigo ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer()
                if let valor { Text(valor).foregroundStyle(.secondary) }
                if let icone {
                    Image(systemName: icone).foregroundStyle(perigo ? Color.red : Color.secondary)
                } else if seta {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Folhas

struct NomeSheet: View {
    @Binding var nome: String
    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seu nome").font(.system(size: 24, weight: .bold))
            Text("Como você quer ser chamado no app").foregroundStyle(.secondary)
            TextField("Seu nome", text: $texto)
                .font(.system(size: 26, weight: .bold))
                .textContentType(.name)
                .focused($foco)
                .padding(.vertical, 22)
                .padding(.horizontal, 12)
            Button("Salvar") {
                nome = texto.trimmingCharacters(in: .whitespaces)
                dismiss()
            }
            .buttonStyle(EstiloPrincipal())
        }
        .padding(28)
        .folha([.height(330)])
        .onAppear {
            texto = nome
            foco = true
        }
    }
}

struct TemaSheet: View {
    @Binding var tema: String
    @Environment(\.dismiss) private var dismiss
    private let opcoes: [(String, String, String)] = [
        ("sistema", "Sistema", "circle.lefthalf.filled"),
        ("claro", "Claro", "sun.max"),
        ("escuro", "Escuro", "moon.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Aparência").font(.system(size: 24, weight: .bold)).padding(.bottom, 12)
            ForEach(opcoes.indices, id: \.self) { i in
                let o = opcoes[i]
                Button {
                    tema = o.0
                    dismiss()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: o.2).frame(width: 26)
                        Text(o.1).font(.system(size: 18))
                        Spacer()
                        if tema == o.0 { Image(systemName: "checkmark") }
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divisor()
            }
        }
        .padding(28)
        .folha([.height(320)])
    }
}

struct MoedaSheet: View {
    @Binding var moeda: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Moeda padrão").font(.system(size: 24, weight: .bold)).padding(.bottom, 12)
                ForEach(Moeda.allCases) { m in
                    Button {
                        moeda = m.rawValue
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            Text(m.simbolo).font(.system(size: 18, weight: .bold)).frame(width: 60, alignment: .leading)
                            Text(m.nome).font(.system(size: 18))
                            Spacer()
                            if moeda == m.rawValue {
                                Image(systemName: "checkmark")
                            } else {
                                Text(m.rawValue).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divisor()
                }
            }
            .padding(28)
        }
        .folha([.medium, .large])
    }
}

struct CategoriasSheet: View {
    let tipo: TipoTransacao
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @State private var nova = ""

    private var lista: [Categoria] { categorias.filter { $0.tipo == tipo } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(tipo == .gasto ? "Categorias de gasto" : "Categorias de receita")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, 16)
                HStack(spacing: 12) {
                    TextField("Nova categoria...", text: $nova)
                        .submitLabel(.done)
                        .onSubmit(adicionar)
                        .campo()
                    Button(action: adicionar) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.sobreDestaque)
                            .frame(width: 60, height: 58)
                            .background(Color.destaque, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 12)

                ForEach(lista) { c in
                    HStack(spacing: 14) {
                        Image(systemName: c.icone).frame(width: 24).foregroundStyle(.secondary)
                        Text(c.nome).font(.system(size: 18))
                        Spacer()
                        if tipo == .gasto {
                            Button(c.essencial ? "essencial" : "desejo") {
                                c.essencial.toggle()
                                try? ctx.save()
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                        Button {
                            ctx.delete(c)
                            try? ctx.save()
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 16)
                    Divisor()
                }
                if tipo == .gasto {
                    Text("Toque em essencial/desejo pra mudar. Isso aparece na Análise.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
                }
            }
            .padding(28)
        }
        .folha([.large])
    }

    private func adicionar() {
        let n = nova.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !lista.contains(where: { $0.nome.lowercased() == n.lowercased() }) else { return }
        ctx.insert(Categoria(nome: n, icone: Categoria.iconePadrao(n), tipo: tipo,
                             essencial: true, ordem: (lista.map(\.ordem).max() ?? 0) + 1))
        try? ctx.save()
        nova = ""
    }
}

struct CarteirasSheet: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @State private var frente: UUID?
    @State private var removendo: Carteira?
    @State private var adicionando = false

    var body: some View {
        let principal = carteiras.first { $0.chave == frente } ?? carteiras.first
        let resto = carteiras.filter { $0.chave != principal?.chave }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Carteiras").font(.system(size: 26, weight: .bold)).padding(.bottom, 20)
                if let principal {
                    CartaoCarteira(carteira: principal, aberto: true)
                        .onLongPressGesture { removendo = principal }
                }
                VStack(spacing: -22) {
                    ForEach(resto) { c in
                        CartaoCarteira(carteira: c, aberto: false)
                            .onTapGesture { withAnimation(.snappy) { frente = c.chave } }
                            .onLongPressGesture { removendo = c }
                    }
                }
                .padding(.top, 14)
                Text("toque num cartão pra trazer pra frente · toque e segure pra remover")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)
                Button("Adicionar meio de pagamento") { adicionando = true }
                    .buttonStyle(EstiloPrincipal())
                    .padding(.top, 20)
            }
            .padding(28)
        }
        .folha([.large])
        .sheet(isPresented: $adicionando) { NovaCarteiraSheet(ordem: (carteiras.map(\.ordem).max() ?? 0) + 1) }
        .confirmationDialog("Remover \(removendo?.nome ?? "")?",
                            isPresented: Binding(get: { removendo != nil }, set: { if !$0 { removendo = nil } }),
                            titleVisibility: .visible) {
            Button("Remover", role: .destructive) {
                if let removendo { ctx.delete(removendo) }
                try? ctx.save()
                removendo = nil
            }
        } message: {
            Text("As transações já registradas continuam com o nome dela.")
        }
    }
}

struct CartaoCarteira: View {
    let carteira: Carteira
    let aberto: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 14) {
                Image(systemName: carteira.tipo.icone).font(.system(size: 22, weight: .semibold))
                Text(carteira.nome).font(.system(size: 22, weight: .bold)).lineLimit(1)
                Spacer()
            }
            if aberto {
                Spacer()
                HStack {
                    Text(carteira.tipo.nome.uppercased()).tracking(2)
                    Spacer()
                    if carteira.tipo == .credito { Text("vence dia \(carteira.diaVencimento)") }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: aberto ? 200 : 80, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.16)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RadialGradient(colors: [.white.opacity(0.25), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 10, y: -2)
        }
    }
}

struct NovaCarteiraSheet: View {
    let ordem: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var nome = ""
    @State private var tipo: TipoCarteira = .credito
    @State private var diaTexto = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Novo meio de pagamento").font(.system(size: 24, weight: .bold))
            TextField("Nome (ex.: Nubank, Inter)", text: $nome).campo()
            Picker("Tipo", selection: $tipo) {
                ForEach(TipoCarteira.allCases) { t in Text(t.nome).tag(t) }
            }
            .pickerStyle(.segmented)
            if tipo == .credito {
                TextField("Dia de vencimento da fatura (ex: 10)", text: $diaTexto)
                    .keyboardType(.numberPad)
                    .campo()
            }
            Spacer()
            Button("Salvar") {
                let dia = min(max(Int(diaTexto) ?? 10, 1), 31)
                ctx.insert(Carteira(nome: nome.trimmingCharacters(in: .whitespaces), tipo: tipo, diaVencimento: dia, ordem: ordem))
                try? ctx.save()
                dismiss()
            }
            .buttonStyle(EstiloPrincipal(ativo: !nome.trimmingCharacters(in: .whitespaces).isEmpty))
            .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(28)
        .folha([.height(440)])
    }
}

// MARK: - Guias de automação

struct GuiaView: View {
    enum Guia { case toqueDuplo, maquininha }
    let guia: Guia
    @Environment(\.dismiss) private var dismiss

    private var titulo: String { guia == .toqueDuplo ? "Toque duplo nas costas" : "Registrar pela maquininha" }
    private var passos: [String] {
        switch guia {
        case .toqueDuplo:
            return [
                "Abra o app Atalhos e toque em + pra criar um atalho novo.",
                "Toque em \"Adicionar Ação\", procure \"Novo registro\" (LBO Finanças) e adicione.",
                "Dê o nome \"Registrar gasto\" pro atalho e salve.",
                "Agora abra Ajustes → Acessibilidade → Toque → Tocar Atrás.",
                "Escolha \"Toque Duplo\" e selecione o atalho \"Registrar gasto\".",
                "Pronto: dois toques nas costas do iPhone abrem a tela de registrar na hora."
            ]
        case .maquininha:
            return [
                "Abra este app pelo menos uma vez, pra o iPhone conhecer a ação \"Registrar gasto\".",
                "Abra o app Atalhos e vá em Automação.",
                "Toque em + e escolha \"Transação\".",
                "Selecione seus cartões da Carteira, marque \"Executar Imediatamente\" e avance.",
                "Adicione a ação \"Registrar gasto\" do LBO Finanças e toque na seta pra ver todos os campos.",
                "Valor: escolha a variável \"Quantia\" da transação.",
                "Onde foi?: escolha a variável \"Comerciante\".",
                "Cartão: escolha a variável \"Cartão\".",
                "Deixe Categoria e Pagamento em branco: o app escolhe sozinho pelo nome do lugar e pelo cartão.",
                "Salve. Na próxima compra por aproximação, o gasto entra sozinho, sem abrir nenhuma pergunta.",
                "Categoria errada? Toque na transação e corrija uma vez: das próximas vezes, o app lembra."
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(titulo).font(.system(size: 26, weight: .bold))
                    Spacer()
                    BotaoFechar { dismiss() }
                }
                ForEach(passos.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(i + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.sobreDestaque)
                            .frame(width: 28, height: 28)
                            .background(Color.destaque, in: Circle())
                        Text(passos[i]).font(.system(size: 17))
                    }
                }
            }
            .padding(28)
        }
        .folha([.large])
    }
}
