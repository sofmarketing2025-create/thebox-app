import SwiftUI

enum Aba: CaseIterable {
    case contas, home, analise, config

    var titulo: String {
        switch self {
        case .contas: return "Contas"
        case .home: return "Home"
        case .analise: return "Análise"
        case .config: return "Config"
        }
    }
    var icone: String {
        switch self {
        case .contas: return "calendar.badge.clock"
        case .home: return "house"
        case .analise: return "chart.bar"
        case .config: return "gearshape"
        }
    }
    var iconeAtivo: String {
        switch self {
        case .contas: return "calendar.badge.clock"
        case .home: return "house.fill"
        case .analise: return "chart.bar.fill"
        case .config: return "gearshape.fill"
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var estado
    @State private var aba: Aba = .home
    @State private var mes = Mes.indice()
    @AppStorage("tourFeito") private var tourFeito = false

    var body: some View {
        @Bindable var estado = estado
        ZStack {
            conteudo
                .safeAreaInset(edge: .bottom) {
                    BarraAbas(aba: $aba)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 2)
                }
            if let passo = estado.tourPasso {
                TourOverlay(passo: passo, avancar: {
                    withAnimation {
                        if passo + 1 < TourOverlay.passos.count {
                            estado.tourPasso = passo + 1
                        } else {
                            fecharTour()
                        }
                    }
                }, pular: { withAnimation { fecharTour() } })
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .background(Color.fundo.ignoresSafeArea())
        .sheet(isPresented: $estado.abrirRegistro) { RegistroSheet() }
        .onAppear {
            if !tourFeito && estado.tourPasso == nil { estado.tourPasso = 0 }
        }
        .onChange(of: estado.tourPasso) { _, passo in
            if let passo { aba = TourOverlay.passos[passo].aba }
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        switch aba {
        case .contas: ContasView(mes: $mes)
        case .home: HomeView(mes: $mes)
        case .analise: AnaliseView(mes: $mes)
        case .config: ConfigView()
        }
    }

    private func fecharTour() {
        estado.tourPasso = nil
        tourFeito = true
        aba = .home
    }
}

struct BarraAbas: View {
    @Binding var aba: Aba

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Aba.allCases, id: \.self) { a in
                let ativa = aba == a
                Button {
                    withAnimation(.snappy(duration: 0.25)) { aba = a }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ativa ? a.iconeAtivo : a.icone).font(.system(size: 15))
                        Text(a.titulo)
                            .font(.system(size: 14, weight: ativa ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(ativa ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        if ativa {
                            Capsule().fill(Color.cartao2.opacity(0.8)).overlay(Capsule().stroke(Color.borda))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.borda))
    }
}

struct TourOverlay: View {
    struct Passo {
        let icone: String
        let titulo: String
        let texto: String
        let aba: Aba
        let noTopo: Bool
    }

    static let passos: [Passo] = [
        Passo(icone: "hand.tap.fill", titulo: "Registre em 2 toques",
              texto: "Toque duas vezes na parte de trás do iPhone pra registrar um gasto sem nem abrir o app. Esse botão + faz a mesma coisa na mão, quando preferir.",
              aba: .home, noTopo: true),
        Passo(icone: "calendar.badge.clock", titulo: "Contas e fatura do cartão",
              texto: "Suas contas fixas e parceladas ficam aqui. Marcou como pago no crédito? O valor entra na fatura daquele cartão, não sai do saldo deste mês. Assinaturas e financiamentos futuros também aparecem projetados.",
              aba: .contas, noTopo: false),
        Passo(icone: "chart.bar.fill", titulo: "Análise",
              texto: "Veja pra onde o dinheiro está indo, por categoria e por mês, pra entender seus hábitos ao longo do tempo.",
              aba: .analise, noTopo: false)
    ]

    let passo: Int
    let avancar: () -> Void
    let pular: () -> Void

    var body: some View {
        let p = Self.passos[passo]
        ZStack(alignment: p.noTopo ? .top : .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture {}
            cartao(p)
                .padding(.horizontal, 16)
                .padding(p.noTopo ? .top : .bottom, p.noTopo ? 110 : 96)
        }
    }

    private func cartao(_ p: Passo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: p.icone)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(Color.sobreDestaque.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<Self.passos.count, id: \.self) { i in
                        Capsule()
                            .fill(Color.sobreDestaque.opacity(i == passo ? 1 : 0.2))
                            .frame(width: i == passo ? 26 : 8, height: 8)
                    }
                }
            }
            Text(p.titulo).font(.system(size: 21, weight: .bold)).padding(.top, 6)
            Text(p.texto).font(.system(size: 15)).foregroundStyle(Color.sobreDestaque.opacity(0.6))
            HStack {
                Button("Pular", action: pular).font(.system(size: 15)).foregroundStyle(Color.sobreDestaque.opacity(0.7))
                Spacer()
                Button(action: avancar) {
                    HStack(spacing: 8) {
                        Text(passo + 1 < Self.passos.count ? "Próximo" : "Entendi")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.destaque)
                    .padding(.horizontal, 28)
                    .frame(height: 56)
                    .background(Color.sobreDestaque, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .foregroundStyle(Color.sobreDestaque)
        .padding(28)
        .background(Color.destaque, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}
