import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var mes: Int
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var estado
    @Query(sort: \Transacao.data, order: .reverse) private var transacoes: [Transacao]
    @Query private var contas: [Conta]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @Query private var limites: [LimiteMensal]
    @AppStorage("nomeUsuario") private var nome = ""
    @AppStorage("ocultarSaldo") private var ocultar = false
    @State private var detalhes = false
    @State private var todas = false
    @State private var editando: Transacao?

    private var saudacao: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Bom dia" : (h < 18 ? "Boa tarde" : "Boa noite")
    }

    var body: some View {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras, limites: limites)
        let doMes = fin.transacoes(em: mes)
        let limite = fin.limite(em: mes)
        let gasto = fin.gastoTotal(em: mes)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(sub: saudacao, titulo: nome.isEmpty ? "Olá" : nome) {
                    SeletorMes(mes: $mes)
                    BotaoCirculo(icone: "plus") { estado.abrirRegistro = true }
                }

                CartaoSaldo(saldo: fin.saldo(em: mes), progresso: limite > 0 ? gasto / limite : 0,
                            ocultar: $ocultar) { detalhes = true }

                HStack(alignment: .firstTextBaseline) {
                    Text("Últimas transações").font(.system(size: 19, weight: .bold))
                    Spacer()
                    Button("Ver todas") { todas = true }
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)

                if doMes.isEmpty {
                    Vazio(titulo: "Nenhuma transação ainda",
                          texto: "Dê 2 toques na parte traseira do iPhone para registrar")
                } else {
                    VStack(spacing: 10) {
                        ForEach(doMes.prefix(15)) { t in
                            LinhaTransacao(transacao: t, iconeCarteira: iconeCarteira(t.carteira))
                                .onTapGesture { editando = t }
                                .contextMenu {
                                    Button { editando = t } label: { Label("Editar", systemImage: "pencil") }
                                    Button(role: .destructive) { apagar(t) } label: { Label("Apagar", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.fundo)
        .sheet(isPresented: $detalhes) { DetalhesSaldoView(mes: mes) }
        .sheet(isPresented: $todas) { TodasTransacoesView() }
        .sheet(item: $editando) { t in RegistroSheet(editando: t) }
    }

    private func apagar(_ t: Transacao) {
        Exclusao.transacao(t, ctx: ctx)
    }

    private func iconeCarteira(_ nome: String) -> String {
        carteiras.first { $0.nome == nome }?.tipo.icone ?? "creditcard"
    }
}

struct CartaoSaldo: View {
    let saldo: Double
    let progresso: Double
    @Binding var ocultar: Bool
    var detalhes: () -> Void

    var body: some View {
        VStack(spacing: -20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Saldo").font(.system(size: 15)).foregroundStyle(.secondary)
                    Spacer()
                    Button { withAnimation { ocultar.toggle() } } label: {
                        Image(systemName: ocultar ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(ocultar ? "\(Moeda.atual.simbolo) ••••••" : saldo.moeda)
                    .font(.system(size: 32, weight: .heavy)).tracking(-1.2)
                    .lineLimit(1).minimumScaleFactor(0.5)
                BarraProgresso(p: progresso, cor: corPorcentagem(progresso), altura: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
            .cartao(22)

            Button(action: detalhes) {
                Text("Ver detalhes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    .frame(height: 40)
                    .background(Color.cartao2, in: Capsule())
                    .overlay(Capsule().stroke(Color.borda))
            }
            .buttonStyle(.plain)
        }
    }
}

struct LinhaTransacao: View {
    let transacao: Transacao
    var iconeCarteira = "creditcard"

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(transacao.titulo).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: iconeCarteira).font(.caption)
                    Text(transacao.categoria).lineLimit(1)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text((transacao.tipo == .gasto ? "-" : "+") + transacao.valor.moeda)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(transacao.tipo == .gasto ? Color.primary : Color.green)
                Text(transacao.data.formatted(.dateTime.day().month(.abbreviated).locale(ptBR)))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.borda))
        .contentShape(Rectangle())
    }
}

struct DetalhesSaldoView: View {
    let mes: Int
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]

    var body: some View {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let porCarteira = Dictionary(grouping: fin.transacoes(em: mes).filter { $0.tipo == .gasto }, by: \.carteira)
            .map { ItemValor(nome: $0.key, valor: $0.value.reduce(0) { $0 + $1.valor }) }
            .sorted { $0.valor > $1.valor }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Saldo de \(Mes.nome(mes).lowercased())").font(.system(size: 21, weight: .bold))
                VStack(spacing: 0) {
                    LinhaStat(titulo: "Receitas", valor: fin.receitas(em: mes).moeda)
                    Divider().overlay(Color.borda)
                    LinhaStat(titulo: "Gastos", valor: "-" + fin.gastosAvulsos(em: mes).moeda)
                    Divider().overlay(Color.borda)
                    LinhaStat(titulo: "Contas pagas", valor: "-" + fin.contasPagasFora(em: mes).moeda)
                    Divider().overlay(Color.borda)
                    LinhaStat(titulo: "Faturas pagas", valor: "-" + fin.faturasPagas(em: mes).moeda)
                    Divider().overlay(Color.borda)
                    LinhaStat(titulo: "Saldo", valor: fin.saldo(em: mes).moeda, destaque: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color.cartao2.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if !porCarteira.isEmpty {
                    Text("Gastos por meio de pagamento").font(.system(size: 15, weight: .semibold)).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(porCarteira) { item in
                            LinhaStat(titulo: item.nome.isEmpty ? "Sem carteira" : item.nome, valor: item.valor.moeda)
                            if item.nome != porCarteira.last?.nome { Divider().overlay(Color.borda) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Color.cartao2.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Text("Contas pagas no cartão de crédito não saem do saldo na hora: entram na fatura do mês seguinte.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .padding(.top, 10)
        }
        .folha([.medium, .large])
    }
}

struct ItemValor: Identifiable {
    let nome: String
    let valor: Double
    var id: String { nome }
}

struct GrupoDia: Identifiable {
    let dia: Date
    let itens: [Transacao]
    var id: Date { dia }
}

struct TodasTransacoesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transacao.data, order: .reverse) private var transacoes: [Transacao]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @State private var busca = ""
    @State private var editando: Transacao?

    private var filtradas: [Transacao] {
        let b = busca.trimmingCharacters(in: .whitespaces).lowercased()
        guard !b.isEmpty else { return transacoes }
        return transacoes.filter {
            $0.descricao.lowercased().contains(b) || $0.categoria.lowercased().contains(b) || $0.carteira.lowercased().contains(b)
        }
    }

    var body: some View {
        let grupos = Dictionary(grouping: filtradas) { Calendar.current.startOfDay(for: $0.data) }
            .map { GrupoDia(dia: $0.key, itens: $0.value) }
            .sorted { $0.dia > $1.dia }

        NavigationStack {
            List {
                if grupos.isEmpty {
                    Vazio(titulo: "Nada por aqui", texto: "Nenhuma transação encontrada.")
                        .listRowBackground(Color.clear)
                }
                ForEach(grupos) { grupo in
                    Section(grupo.dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ptBR))) {
                        ForEach(grupo.itens) { t in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.titulo).font(.system(size: 14, weight: .semibold))
                                    Text("\(t.categoria) · \(t.carteira)").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text((t.tipo == .gasto ? "-" : "+") + t.valor.moeda)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(t.tipo == .gasto ? Color.primary : Color.green)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editando = t }
                            .contextMenu {
                                Button { editando = t } label: { Label("Editar", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Exclusao.transacao(t, ctx: ctx)
                                } label: { Label("Apagar", systemImage: "trash") }
                            }
                            .swipeActions {
                                Button("Apagar", role: .destructive) {
                                    Exclusao.transacao(t, ctx: ctx)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.cartao)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo)
            .searchable(text: $busca, prompt: "Buscar")
            .safeAreaInset(edge: .bottom) {
                BarraDesfazer().padding(.bottom, 8)
            }
            .animation(.snappy, value: AppState.shared.desfazer?.id)
            .navigationTitle("Transações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .sheet(item: $editando) { t in RegistroSheet(editando: t) }
        }
    }
}
