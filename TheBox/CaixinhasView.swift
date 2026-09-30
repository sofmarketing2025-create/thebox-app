import SwiftUI
import SwiftData

/// Movimento numa caixinha: guardar (sai da conta) ou resgatar (volta pra conta)
struct MovimentoCaixinha: Identifiable {
    let id = UUID()
    let caixinha: Caixinha
    let guardar: Bool
}

/// Caixinhas na aba Quitar: dinheiro guardado com objetivo
struct SecaoCaixinhas: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Caixinha.ordem) private var caixinhas: [Caixinha]
    @Query private var transacoes: [Transacao]
    @State private var nova = false
    @State private var editando: Caixinha?
    @State private var movimento: MovimentoCaixinha?

    var body: some View {
        let fin = Financas(transacoes: transacoes)
        let total = caixinhas.reduce(0) { $0 + fin.saldoCaixinha($1) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CAIXINHAS").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                    if !caixinhas.isEmpty {
                        Text("\(total.moeda) guardados").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { nova = true } label: {
                    Label("Nova", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.cartao2, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            if caixinhas.isEmpty {
                Text("Guarde dinheiro com um objetivo: reserva de emergência, quitar uma dívida, viagem. O que você guarda sai do saldo da conta, mas não conta como gasto.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .cartao(18)
            }
            ForEach(caixinhas) { c in
                CartaoCaixinha(caixinha: c, saldo: fin.saldoCaixinha(c),
                               guardar: { movimento = MovimentoCaixinha(caixinha: c, guardar: true) },
                               resgatar: { movimento = MovimentoCaixinha(caixinha: c, guardar: false) },
                               editar: { editando = c },
                               apagar: { apagar(c) })
            }
        }
        .sheet(isPresented: $nova) { FormCaixinha(caixinha: nil, ordem: (caixinhas.map(\.ordem).max() ?? 0) + 1) }
        .sheet(item: $editando) { c in FormCaixinha(caixinha: c, ordem: c.ordem) }
        .sheet(item: $movimento) { mv in
            EditarValorSheet(titulo: mv.guardar ? "Guardar em \(mv.caixinha.nome)" : "Resgatar de \(mv.caixinha.nome)",
                             subtitulo: mv.guardar ? "Sai do saldo da conta e vai pra caixinha (não é gasto)"
                                                   : "Volta pro saldo da conta (não é receita)",
                             valor: 0) { v in
                guard v > 0 else { return }
                ctx.insert(Transacao(tipo: .transferencia, valor: v,
                                     categoria: Transacao.prefixoCaixinha + mv.caixinha.nome, carteira: "",
                                     descricao: (mv.guardar ? "Guardado: " : "Resgate: ") + mv.caixinha.nome,
                                     entrada: !mv.guardar))
                try? ctx.save()
            }
        }
    }

    private func apagar(_ c: Caixinha) {
        let nome = c.nome
        let copia = Caixinha(nome: c.nome, meta: c.meta, saldoInicial: c.saldoInicial, prazo: c.prazo, ordem: c.ordem)
        withAnimation {
            ctx.delete(c)
            try? ctx.save()
        }
        AppState.shared.oferecerDesfazer("Caixinha \(nome) apagada") {
            ctx.insert(copia)
            try? ctx.save()
        }
    }
}

struct CartaoCaixinha: View {
    let caixinha: Caixinha
    let saldo: Double
    var guardar: () -> Void
    var resgatar: () -> Void
    var editar: () -> Void
    var apagar: () -> Void

    var body: some View {
        let meta = caixinha.meta
        let p = meta > 0 ? saldo / meta : 0
        let falta = max(0, meta - saldo)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
                Text(caixinha.nome).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    Button { editar() } label: { Label("Editar", systemImage: "pencil") }
                    Button(role: .destructive) { apagar() } label: { Label("Apagar caixinha", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.cartao2, in: Circle())
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(saldo.moeda).font(.system(size: 24, weight: .heavy))
                if meta > 0 {
                    Text("de \(meta.moedaInteira)").font(.system(size: 14)).foregroundStyle(.secondary)
                    Spacer()
                    Text(porcento(p)).font(.system(size: 14, weight: .semibold))
                }
            }
            if meta > 0 {
                BarraProgresso(p: p, cor: p >= 1 ? .green : .primary, altura: 5)
                Text(textoMeta(falta: falta))
                    .font(.system(size: 12)).foregroundStyle(p >= 1 ? Color.green : Color.secondary)
            }
            HStack(spacing: 10) {
                Button(action: guardar) {
                    Label("Guardar", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sobreDestaque)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Color.destaque, in: Capsule())
                }
                Button(action: resgatar) {
                    Label("Resgatar", systemImage: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Color.cartao2, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .cartao(18)
    }

    private func textoMeta(falta: Double) -> String {
        guard falta > 0 else { return "Meta alcançada! 🎉" }
        guard let prazo = caixinha.prazo else { return "Faltam \(falta.moeda) pra meta." }
        let meses = max(1, Mes.indice(prazo) - Mes.indice() + 1)
        return "Faltam \(falta.moeda) · guarde \((falta / Double(meses)).moeda) por mês até \(mesAno(Mes.indice(prazo)))"
    }
}

struct FormCaixinha: View {
    let caixinha: Caixinha?
    let ordem: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var transacoes: [Transacao]
    @State private var nome = ""
    @State private var metaTexto = ""
    @State private var guardadoTexto = ""
    @State private var temPrazo = false
    @State private var prazo = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now

    private var nomeLimpo: String { nome.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(caixinha == nil ? "Nova caixinha" : "Editar caixinha").font(.system(size: 21, weight: .bold))
                TextField("Nome (ex.: Reserva de emergência)", text: $nome).campo()
                HStack(spacing: 10) {
                    Text("Meta \(Moeda.atual.simbolo)").foregroundStyle(.secondary)
                    TextField("opcional", text: $metaTexto).mascaraDinheiro($metaTexto)
                }
                .campo()
                HStack(spacing: 10) {
                    Text("Já guardado \(Moeda.atual.simbolo)").foregroundStyle(.secondary)
                    TextField("0,00", text: $guardadoTexto).mascaraDinheiro($guardadoTexto)
                }
                .campo()
                Text("\"Já guardado\" é o que já está nessa caixinha hoje (não mexe no saldo da conta).")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                LinhaToggle(titulo: "Tem prazo", sub: "O app calcula quanto guardar por mês", ligado: $temPrazo)
                if temPrazo {
                    DatePicker("Até", selection: $prazo, in: Date.now..., displayedComponents: .date)
                        .environment(\.locale, ptBR)
                }
                Button("Salvar") { salvar() }
                    .buttonStyle(EstiloPrincipal(ativo: !nomeLimpo.isEmpty))
                    .disabled(nomeLimpo.isEmpty)
                    .padding(.top, 6)
            }
            .padding(28)
        }
        .folha([.large])
        .onAppear {
            guard let c = caixinha else { return }
            nome = c.nome
            metaTexto = textoDinheiro(c.meta)
            guardadoTexto = textoDinheiro(c.saldoInicial)
            if let p = c.prazo { temPrazo = true; prazo = p }
        }
    }

    private func salvar() {
        let meta = lerValor(metaTexto) ?? 0
        let guardado = lerValor(guardadoTexto) ?? 0
        if let c = caixinha {
            if c.nome != nomeLimpo {
                // leva o nome novo pros guardados/resgates antigos
                let antigo = Transacao.prefixoCaixinha + c.nome
                for t in transacoes where t.categoria == antigo { t.categoria = Transacao.prefixoCaixinha + nomeLimpo }
            }
            c.nome = nomeLimpo
            c.meta = meta
            c.saldoInicial = guardado
            c.prazo = temPrazo ? prazo : nil
        } else {
            ctx.insert(Caixinha(nome: nomeLimpo, meta: meta, saldoInicial: guardado, prazo: temPrazo ? prazo : nil, ordem: ordem))
        }
        try? ctx.save()
        dismiss()
    }
}
