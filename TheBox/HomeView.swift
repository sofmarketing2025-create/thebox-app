import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Gasto.data, order: .reverse) private var gastos: [Gasto]
    @Query private var contas: [Conta]
    @State private var criando = false
    @State private var editando: Gasto?

    private var saudacao: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Bom dia" : (h < 18 ? "Boa tarde" : "Boa noite")
    }

    var body: some View {
        let hoje = Mes.indice()
        let doMes = gastos.filter { $0.mes == hoje }
        let totalGastos = doMes.reduce(0) { $0 + $1.valor }
        let pendentes = contas.filter { $0.ocorre(em: hoje) && !$0.pago(em: hoje) }.sorted { $0.dia < $1.dia }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(sub: saudacao, titulo: "The Box") {
                    BotaoMais { criando = true }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("GASTOS EM \(Mes.nome(hoje).uppercased())")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(.secondary)
                    Text(totalGastos.brl)
                        .font(.system(size: 36, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 4)
                    Text("\(doMes.count) \(doMes.count == 1 ? "gasto" : "gastos") no mês")
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Pagamento.allCases) { p in
                                let v = doMes.filter { $0.pagamento == p }.reduce(0) { $0 + $1.valor }
                                if v > 0 { Chip("\(p.nome) \(v.brl)") }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .cartao()

                if !pendentes.isEmpty {
                    Text("Contas a pagar").font(.system(size: 24, weight: .bold)).padding(.top, 8)
                    ForEach(pendentes) { conta in
                        LinhaConta(conta: conta, mes: hoje) {
                            conta.alternarPago(em: hoje)
                            try? ctx.save()
                            Notificacoes.reagendar(ctx)
                        }
                    }
                }

                Text("Gastos recentes").font(.system(size: 24, weight: .bold)).padding(.top, 8)
                if gastos.isEmpty {
                    Vazio(texto: "Seus gastos aparecem aqui.\nConfigure a automação da maquininha em Config.",
                          botao: "Adicionar gasto") { criando = true }
                } else {
                    VStack(spacing: 0) {
                        ForEach(gastos.prefix(30)) { g in
                            LinhaGasto(gasto: g)
                                .contentShape(Rectangle())
                                .onTapGesture { editando = g }
                            if g.id != gastos.prefix(30).last?.id { Divider().overlay(Color.borda) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.borda))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.fundo)
        .sheet(isPresented: $criando) { FormGasto(gasto: nil) }
        .sheet(item: $editando) { g in FormGasto(gasto: g) }
    }
}

struct LinhaGasto: View {
    let gasto: Gasto
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: gasto.categoria.icone)
                .font(.system(size: 17))
                .foregroundStyle(gasto.categoria.cor)
                .frame(width: 44, height: 44)
                .background(gasto.categoria.cor.opacity(0.15), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(gasto.descricao.isEmpty ? gasto.categoria.nome : gasto.descricao)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text("\(gasto.categoria.nome) · \(gasto.pagamento.nome) · \(gasto.data.formatted(.dateTime.day().month(.abbreviated).locale(ptBR)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(gasto.valor.brl).font(.system(size: 16, weight: .bold)).lineLimit(1)
        }
        .padding(.vertical, 12)
    }
}
