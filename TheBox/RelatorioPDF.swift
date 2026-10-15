import SwiftUI
import SwiftData

/// Relatório do mês em PDF (pra mandar no WhatsApp, imprimir ou guardar)
@MainActor
enum RelatorioPDF {
    static func gerar(mes: Int, ctx: ModelContext) -> URL? {
        let fin = Financas(transacoes: (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? [],
                           contas: (try? ctx.fetch(FetchDescriptor<Conta>())) ?? [],
                           carteiras: (try? ctx.fetch(FetchDescriptor<Carteira>())) ?? [],
                           limites: (try? ctx.fetch(FetchDescriptor<LimiteMensal>())) ?? [])
        let nome = UserDefaults.standard.string(forKey: "nomeUsuario") ?? ""
        let pagina = PaginaRelatorio(mes: mes, fin: fin, nome: nome)
            .frame(width: 595)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: pagina)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LBO Financas - \(Mes.nome(mes)) \(Mes.ano(mes)).pdf")
        var ok = false
        renderer.render { tamanho, desenhar in
            var caixa = CGRect(origin: .zero, size: tamanho)
            guard let pdf = CGContext(url as CFURL, mediaBox: &caixa, nil) else { return }
            pdf.beginPDFPage(nil)
            desenhar(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

private struct PaginaRelatorio: View {
    let mes: Int
    let fin: Financas
    let nome: String

    private let cinza = Color(white: 0.45)
    private let linhaCor = Color(white: 0.88)

    var body: some View {
        let doMes = fin.transacoes(em: mes).sorted { $0.data < $1.data }
        let entrou = doMes.filter { $0.tipo == .receita && !$0.ehAjuste }.reduce(0) { $0 + $1.valor }
        let gastou = fin.gastoTotal(em: mes)
        let quitado = fin.contas.filter { PlanoCalculo.temFim($0) && $0.ocorre(em: mes) && $0.pago(em: mes) }
            .reduce(0) { $0 + $1.valor }
        let guardado = doMes.filter { $0.nomeCaixinha != nil }.reduce(0) { $0 + ($1.entrada ? -$1.valor : $1.valor) }
        let porCategoria = fin.gastoPorCategoria(em: mes).sorted { $0.value > $1.value }
        let contasMes = fin.contasDoMes(mes)
        let dividas = PlanoCalculo.dividas(fin.contas, hoje: Mes.indice())
        let resta = dividas.reduce(0) { $0 + $1.total }
        let livre = dividas.map(\.fim).max()

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LBO FINANÇAS").font(.system(size: 10, weight: .semibold)).tracking(3).foregroundStyle(cinza)
                Text("Relatório de \(Mes.nome(mes).lowercased()) de \(String(Mes.ano(mes)))")
                    .font(.system(size: 22, weight: .bold))
                Text((nome.isEmpty ? "" : "\(nome) · ") + "gerado em \(Date.now.formatted(.dateTime.day().month().year().locale(ptBR)))")
                    .font(.system(size: 10)).foregroundStyle(cinza)
            }

            HStack(spacing: 10) {
                bloco("Entrou", entrou)
                bloco("Saiu", gastou)
                bloco("Quitou", quitado)
                bloco("Guardou", guardado)
            }

            HStack(spacing: 10) {
                bloco("Saldo no fim do mês", mes < Mes.indice() ? fin.saldo(em: mes) : fin.saldoPrevisto(em: mes))
                bloco("Ainda deve", resta)
            }
            if let livre {
                Text("Livre das dívidas em \(Mes.nome(livre).lowercased()) de \(String(Mes.ano(livre))).")
                    .font(.system(size: 11)).foregroundStyle(cinza)
            }

            if !porCategoria.isEmpty {
                secao("Gastos por categoria")
                ForEach(porCategoria, id: \.key) { item in
                    linha(item.key, gastou > 0 ? porcento(item.value / gastou) : "", item.value.moeda)
                }
            }

            if !contasMes.isEmpty {
                secao("Contas do mês")
                ForEach(contasMes) { c in
                    linha(c.parcela(em: mes).map { "\(c.nome) (\($0))" } ?? c.nome,
                          c.pago(em: mes) ? "Paga" : "Pendente", c.valor.moeda)
                }
            }

            if !doMes.isEmpty {
                secao("Transações")
                ForEach(doMes) { t in
                    linha("\(t.data.formatted(.dateTime.day().month(.twoDigits).locale(ptBR)))  \(t.titulo)",
                          t.categoria,
                          (t.efeitoNoSaldo < 0 ? "-" : "+") + t.valor.moeda)
                }
            }
        }
        .padding(36)
        .frame(width: 595, alignment: .leading)
        .foregroundStyle(.black)
        .background(Color.white)
    }

    private func bloco(_ titulo: String, _ valor: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(cinza)
            Text(valor.moeda).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 8))
    }

    private func secao(_ titulo: String) -> some View {
        Text(titulo.uppercased())
            .font(.system(size: 10, weight: .bold)).tracking(1.5)
            .padding(.top, 6)
    }

    private func linha(_ a: String, _ b: String, _ c: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(a).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 8)
                Text(b).font(.system(size: 10)).foregroundStyle(cinza).lineLimit(1)
                Text(c).font(.system(size: 11, weight: .semibold)).frame(width: 90, alignment: .trailing)
            }
            Rectangle().fill(linhaCor).frame(height: 0.5)
        }
    }
}
