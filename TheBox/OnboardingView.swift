import SwiftUI
import SwiftData

struct OnboardingView: View {
    var concluir: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @AppStorage("objetivo") private var objetivo = ""
    @State private var pagina = 0
    @State private var orcamentoTexto = ""
    @State private var divisao: [String: String] = [:]
    @State private var guia = false
    @FocusState private var foco: Bool

    private let objetivos: [(String, String)] = [
        ("magnifyingglass", "Saber pra onde meu dinheiro vai"),
        ("chart.pie.fill", "Controlar os gastos do mês"),
        ("creditcard.fill", "Organizar o cartão de crédito"),
        ("banknote", "Guardar dinheiro"),
        ("checklist", "Ter tudo organizado")
    ]
    private let sugestao: [(String, String, Double)] = [
        ("Alimentação", "fork.knife", 0.3),
        ("Transporte", "car.fill", 0.2),
        ("Moradia", "house.fill", 0.3),
        ("Lazer", "face.smiling", 0.2)
    ]

    private var orcamento: Double { lerValor(orcamentoTexto) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if pagina > 0 {
                    Button { withAnimation { pagina -= 1 } } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .background(Color.cartao, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(height: 56)
            .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    conteudo
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            rodape
        }
        .padding(.horizontal, 24)
        .background(Color.fundo.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: pagina)
        .sheet(isPresented: $guia, onDismiss: finalizar) { GuiaView(guia: .toqueDuplo) }
    }

    @ViewBuilder
    private var conteudo: some View {
        switch pagina {
        case 0: boasVindas
        case 1: telaObjetivo
        case 2: telaOrcamento
        case 3: telaDivisao
        case 4: telaNotificacoes
        default: telaSuperpoder
        }
    }

    // MARK: Rodapé (botão + pular + pontos)

    @ViewBuilder
    private var rodape: some View {
        VStack(spacing: 10) {
            switch pagina {
            case 0:
                Button { avancar() } label: { HStack { Text("Vamos lá"); Image(systemName: "arrow.right") } }
                    .buttonStyle(EstiloPrincipal())
            case 1:
                EmptyView()
            case 2:
                Button { avancar() } label: { HStack { Text("Continuar"); Image(systemName: "arrow.right") } }
                    .buttonStyle(EstiloPrincipal(ativo: orcamento > 0))
                    .disabled(orcamento <= 0)
                Button("Pular por agora") { avancar() }.font(.subheadline).foregroundStyle(.secondary)
            case 3:
                Button { avancar() } label: { HStack { Text("Continuar"); Image(systemName: "arrow.right") } }
                    .buttonStyle(EstiloPrincipal())
                Button("Pular por agora") { divisao = [:]; avancar() }.font(.subheadline).foregroundStyle(.secondary)
            case 4:
                Button {
                    Task {
                        _ = await Notificacoes.pedirPermissao()
                        avancar()
                    }
                } label: { HStack { Text("Ativar notificações"); Image(systemName: "bell.fill") } }
                    .buttonStyle(EstiloPrincipal())
                Button("Agora não") { avancar() }.font(.subheadline).foregroundStyle(.secondary)
            default:
                Button { guia = true } label: { HStack { Text("Configurar agora"); Image(systemName: "arrow.up.right") } }
                    .buttonStyle(EstiloPrincipal())
                Button("Pular por agora") { finalizar() }.font(.subheadline).foregroundStyle(.secondary)
            }
            Pontos(total: 6, atual: pagina)
                .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    // MARK: Telas

    private var boasVindas: some View {
        VStack(alignment: .leading, spacing: 14) {
            OrbitaLogo()
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .padding(.top, 10)
            Text("Seu dinheiro.\nMais claro.").tituloGrande()
            Text("Sem conectar ao seu banco. É você que registra o que importa, no seu ritmo.")
                .foregroundStyle(.secondary)
            Text("LBO FINANÇAS")
                .font(.system(size: 13, weight: .medium)).tracking(5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    private var telaObjetivo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("O que você mais\nquer melhorar?").tituloGrande().padding(.top, 60)
            Text("Isso ajuda a gente a mostrar o que importa primeiro").foregroundStyle(.secondary)
                .padding(.bottom, 16)
            ForEach(objetivos.indices, id: \.self) { i in
                let item = objetivos[i]
                Button {
                    objetivo = item.1
                    avancar()
                } label: {
                    HStack(spacing: 16) {
                        IconeQuadrado(icone: item.0, tamanho: 52)
                        Text(item.1).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var telaOrcamento: some View {
        VStack(alignment: .leading, spacing: 14) {
            LogoView(tamanho: 110)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .padding(.bottom, 24)
            Text("Qual seu orçamento\nmensal?").tituloGrande()
            Text(fraseObjetivo).foregroundStyle(.secondary).padding(.bottom, 18)
            HStack(spacing: 12) {
                Text(Moeda.atual.simbolo).font(.system(size: 17, weight: .bold)).foregroundStyle(.secondary)
                TextField("ex: 5.000", text: $orcamentoTexto)
                    .font(.system(size: 17, weight: .semibold))
                    .keyboardType(.numberPad)
                    .focused($foco)
            }
            .padding(.horizontal, 22)
            .frame(height: 72)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("sem ideia? começa por aqui").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
            HStack(spacing: 10) {
                ForEach([2000.0, 4000.0, 8000.0], id: \.self) { v in
                    Button {
                        orcamentoTexto = v.inteiro
                        foco = false
                    } label: {
                        Text(v.moedaInteira)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var telaDivisao: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Para onde vai\nseu dinheiro?").tituloGrande().padding(.top, 60)
            Text("Sugerimos uma divisão, ajuste como quiser. Isso ajuda o app a te avisar antes de estourar.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
            ForEach(sugestao.indices, id: \.self) { i in
                let item = sugestao[i]
                HStack(spacing: 16) {
                    IconeQuadrado(icone: item.1, tamanho: 52)
                    Text(item.0).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(Moeda.atual.simbolo).foregroundStyle(.secondary)
                    TextField("0", text: bindingDivisao(item.0, item.2))
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 90)
                }
                .padding(14)
                .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var telaNotificacoes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 30))
                .frame(width: 110, height: 110)
                .background(Color.cartao, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .padding(.bottom, 20)
            Text("Avisamos na\nhora certa").tituloGrande()
            Text("Um aviso quando uma categoria estiver perto de estourar, e um resumo por semana. Sem spam, você desliga quando quiser.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
            AvisoExemplo(titulo: "Limite atingido — Alimentação",
                         texto: "Você atingiu 100% do orçamento de Alimentação (\(1200.0.moeda)).")
            AvisoExemplo(titulo: "Resumo da semana",
                         texto: "Você gastou \(340.0.moeda) essa semana, 12% a menos que a média.")
            AvisoExemplo(titulo: "Fatura chegando",
                         texto: "Sua fatura do cartão vence em 3 dias (\(890.0.moeda)).")
        }
    }

    private var telaSuperpoder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 40))
                .frame(width: 210, height: 210)
                .background(Color.cartao, in: Circle())
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
                .padding(.bottom, 40)
            Text("Seu superpoder\nestá aqui 👇").tituloGrande()
            Text("Toque 2x na parte de trás do iPhone e registre um gasto. Sem abrir o app, sem tocar na tela.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Lógica

    private var fraseObjetivo: String {
        let frases = [
            "Saber pra onde meu dinheiro vai": "saber pra onde seu dinheiro vai",
            "Controlar os gastos do mês": "controlar os gastos do mês",
            "Organizar o cartão de crédito": "organizar o cartão de crédito",
            "Guardar dinheiro": "guardar dinheiro",
            "Ter tudo organizado": "ter tudo organizado"
        ]
        guard let f = frases[objetivo] else { return "vamos começar por aqui." }
        return "já que você quer \(f), vamos começar por aqui."
    }

    private func bindingDivisao(_ nome: String, _ fatia: Double) -> Binding<String> {
        Binding(
            get: { divisao[nome] ?? (orcamento > 0 ? (orcamento * fatia).inteiro.replacingOccurrences(of: ".", with: "") : "") },
            set: { divisao[nome] = $0 }
        )
    }

    private func avancar() {
        foco = false
        withAnimation { pagina += 1 }
    }

    private func finalizar() {
        let hoje = Mes.indice()
        if orcamento > 0 { ctx.insert(LimiteMensal(mes: hoje, valor: orcamento)) }
        for item in sugestao {
            let texto = divisao[item.0] ?? (orcamento > 0 ? String(Int(orcamento * item.2)) : "")
            if let v = lerValor(texto), v > 0,
               let c = categorias.first(where: { $0.nome == item.0 && $0.tipo == .gasto }) {
                c.limite = v
            }
        }
        try? ctx.save()
        concluir()
    }
}

struct AvisoExemplo: View {
    let titulo: String
    let texto: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LogoView(tamanho: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("LBO FINANÇAS").font(.system(size: 12, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Text("agora").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Text(titulo).font(.system(size: 14, weight: .semibold))
                Text(texto).font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Logo no centro com ícones girando em volta (tela de boas-vindas)
struct OrbitaLogo: View {
    @State private var girar = false
    private let externos = ["house.fill", "car.fill", "bell.badge.fill", "doc.text.fill", "hand.tap.fill"]
    private let internos = ["banknote", "chart.pie.fill", "creditcard.fill"]

    var body: some View {
        let angulo: Double = girar ? 360 : 0
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .frame(width: 300, height: 300)
            Circle()
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .frame(width: 180, height: 180)
            ForEach(Array(externos.enumerated()), id: \.offset) { i, icone in
                let a = Double(i) * 72
                bolha(icone, 60)
                    .rotationEffect(.degrees(-a - angulo))
                    .offset(y: -150)
                    .rotationEffect(.degrees(a + angulo))
            }
            ForEach(Array(internos.enumerated()), id: \.offset) { i, icone in
                let a = Double(i) * 120 + 40
                bolha(icone, 48)
                    .rotationEffect(.degrees(-a + angulo))
                    .offset(y: -90)
                    .rotationEffect(.degrees(a - angulo))
            }
            LogoView(tamanho: 120)
                .shadow(color: .black.opacity(0.3), radius: 20)
        }
        .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: girar)
        .onAppear { girar = true }
    }

    private func bolha(_ icone: String, _ tamanho: CGFloat) -> some View {
        Image(systemName: icone)
            .font(.system(size: tamanho * 0.34, weight: .semibold))
            .frame(width: tamanho, height: tamanho)
            .background(Color.cartao2, in: Circle())
    }
}
