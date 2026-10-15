import SwiftUI
import SwiftData

struct OnboardingView: View {
    var concluir: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @AppStorage("objetivo") private var objetivo = ""
    @State private var pagina = 0
    @State private var rendaTexto = ""
    @State private var diaSalario = 5
    @State private var saldoTexto = ""
    @State private var guia = false
    @FocusState private var foco: Bool

    private let total = 5
    private let objetivos: [(String, String)] = [
        ("flag.checkered", "Sair das dívidas"),
        ("chart.pie.fill", "Controlar os gastos do mês"),
        ("magnifyingglass", "Saber pra onde meu dinheiro vai"),
        ("creditcard.fill", "Organizar o cartão de crédito"),
        ("banknote", "Guardar dinheiro")
    ]

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
        case 2: telaDinheiro
        case 3: telaNotificacoes
        default: telaSuperpoder
        }
    }

    // MARK: Rodapé (botão + pular + pontos)

    @ViewBuilder
    private var rodape: some View {
        VStack(spacing: 10) {
            switch pagina {
            case 0:
                Button { avancar() } label: { HStack { Text("Começar"); Image(systemName: "arrow.right") } }
                    .buttonStyle(EstiloPrincipal())
            case 1:
                EmptyView()
            case 2:
                Button { avancar() } label: { HStack { Text("Continuar"); Image(systemName: "arrow.right") } }
                    .buttonStyle(EstiloPrincipal())
                Button("Pular por agora") { rendaTexto = ""; saldoTexto = ""; avancar() }
                    .font(.subheadline).foregroundStyle(.secondary)
            case 3:
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
            Pontos(total: total, atual: pagina)
                .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    // MARK: Telas

    private var boasVindas: some View {
        VStack(alignment: .leading, spacing: 14) {
            OrbitaLogo()
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .padding(.top, 4)
            Text("Seu dinheiro.\nMais claro.").tituloGrande()
            Text("Sem conectar ao banco. Você registra em segundos e o app faz as contas.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            beneficio("banknote", "Quanto você pode gastar hoje", "Sem estourar o mês.")
            beneficio("bell.badge.fill", "Avisos na hora certa", "Antes da conta vencer e antes de passar do orçamento.")
            beneficio("flag.checkered", "Saia das dívidas mais rápido", "Veja o dia em que fica livre e como adiantar.")
        }
    }

    private func beneficio(_ icone: String, _ titulo: String, _ texto: String) -> some View {
        HStack(spacing: 14) {
            IconeQuadrado(icone: icone, tamanho: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 15, weight: .semibold))
                Text(texto).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var telaObjetivo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("O que você mais\nquer agora?").tituloGrande().padding(.top, 40)
            Text("O app mostra primeiro o que importa pra você").foregroundStyle(.secondary)
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

    private var telaDinheiro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Seu dinheiro\nhoje").tituloGrande().padding(.top, 40)
            Text("Com isso o app já calcula quanto você pode gastar por dia. Dá pra mudar depois.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
            campoDinheiro("Quanto você ganha por mês?", texto: $rendaTexto)
            if (lerValor(rendaTexto) ?? 0) > 0 {
                Stepper(value: $diaSalario, in: 1...31) {
                    Text("Cai todo dia \(diaSalario)").font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .frame(height: 60)
                .background(Color.cartao, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            campoDinheiro("Quanto tem na conta agora?", texto: $saldoTexto)
            Text("Olhe o saldo no app do banco e digite aqui.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func campoDinheiro(_ titulo: String, texto: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(Moeda.atual.simbolo).font(.system(size: 17, weight: .bold)).foregroundStyle(.secondary)
                TextField("0,00", text: texto)
                    .font(.system(size: 17, weight: .semibold))
                    .mascaraDinheiro(texto)
                    .focused($foco)
            }
            .padding(.horizontal, 22)
            .frame(height: 64)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            Text("Antes de uma conta vencer, quando o orçamento estiver acabando e um resumo por semana. Você desliga quando quiser.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
            AvisoExemplo(titulo: "Conta de luz vence amanhã",
                         texto: "\(187.0.moeda) vence amanhã. Toque em Paguei quando pagar.")
            AvisoExemplo(titulo: "80% do orçamento da semana",
                         texto: "Você já usou \(120.0.moeda) de \(150.0.moeda). Restam \(30.0.moeda).")
            AvisoExemplo(titulo: "Registrou tudo hoje?",
                         texto: "Hoje: 3 gastos, \(64.9.moeda). Faltou algum?")
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

    private func avancar() {
        foco = false
        withAnimation { pagina += 1 }
    }

    private func finalizar() {
        let hoje = Mes.indice()
        if let renda = lerValor(rendaTexto), renda > 0 {
            let cats = categorias.filter { $0.tipo == .receita }
            let cat = cats.first { $0.nome == "Salário" }?.nome ?? cats.first?.nome ?? "Salário"
            let cart = carteiras.first { $0.tipo != .credito }?.nome ?? ""
            // se o salário deste mês já caiu, ele já está no saldo de hoje
            let jaCaiu = Calendar.current.component(.day, from: .now) >= diaSalario
            ctx.insert(Recorrencia(nome: "Salário", valor: renda, dia: diaSalario, categoria: cat, carteira: cart,
                                   ultimoMes: jaCaiu ? hoje : hoje - 1))
        }
        if let saldo = lerValor(saldoTexto), saldo > 0 {
            ctx.insert(Transacao(tipo: .receita, valor: saldo, categoria: Transacao.categoriaAjuste, carteira: "",
                                 descricao: "Saldo inicial"))
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
