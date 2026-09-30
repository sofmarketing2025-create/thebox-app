import SwiftUI
import SwiftData

/// Lança sozinhas as receitas fixas (ex.: salário) quando chega o dia
@MainActor
enum Recorrencias {
    static func gerar(_ ctx: ModelContext) {
        let lista = (try? ctx.fetch(FetchDescriptor<Recorrencia>())) ?? []
        let hoje = Mes.indice()
        let agora = Date.now
        var criou = false
        for r in lista where r.ativa {
            var m = r.ultimoMes + 1
            while m <= hoje {
                let dia = Mes.data(m, dia: r.dia, hora: 9)
                guard dia <= agora else { break }
                ctx.insert(Transacao(tipo: .receita, valor: r.valor, categoria: r.categoria, carteira: r.carteira,
                                     descricao: r.nome, data: dia))
                r.ultimoMes = m
                m += 1
                criou = true
                Notificacoes.agora("\(r.nome) entrou", "\(r.valor.moeda) registrado sozinho. Se não caiu, é só apagar.")
            }
        }
        if criou {
            try? ctx.save()
            Notificacoes.reagendar(ctx)
        }
    }
}

/// Config → Receitas fixas: ver, editar valor/dia, pausar e remover
struct ReceitasFixasSheet: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recorrencia.dia) private var lista: [Recorrencia]
    @State private var editandoValor: Recorrencia?
    @State private var editandoDia: Recorrencia?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Receitas fixas").font(.system(size: 21, weight: .bold))
                Text("Entram sozinhas todo mês no dia marcado. Pra criar uma, registre uma Receita e ligue \"Repete todo mês\".")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                if lista.isEmpty {
                    Vazio(icone: "arrow.triangle.2.circlepath", titulo: "Nenhuma receita fixa",
                          texto: "Ex.: salário. Registre como Receita com \"Repete todo mês\" ligado.")
                }
                ForEach(lista) { r in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.nome).font(.system(size: 16, weight: .semibold))
                                Text("todo dia \(r.dia) · \(r.categoria)")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(r.valor.moeda).font(.system(size: 16, weight: .bold)).foregroundStyle(.green)
                        }
                        HStack(spacing: 8) {
                            Button("Valor") { editandoValor = r }
                            Button("Dia") { editandoDia = r }
                            Button(r.ativa ? "Pausar" : "Ativar") {
                                r.ativa.toggle()
                                if r.ativa { r.ultimoMes = max(r.ultimoMes, Mes.indice() - 1) }
                                try? ctx.save()
                            }
                            Spacer()
                            Button(role: .destructive) {
                                ctx.delete(r)
                                try? ctx.save()
                            } label: { Image(systemName: "trash") }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.bordered)
                        if !r.ativa {
                            Text("Pausada: não entra nos próximos meses.").font(.system(size: 12)).foregroundStyle(.orange)
                        }
                    }
                    .padding(16)
                    .background(Color.cartao2.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(24)
        }
        .folha([.large])
        .sheet(item: $editandoValor) { r in
            EditarValorSheet(titulo: "Valor de \(r.nome)", subtitulo: "Vale a partir do próximo lançamento", valor: r.valor) {
                if $0 > 0 { r.valor = $0; try? ctx.save() }
            }
        }
        .sheet(item: $editandoDia) { r in
            DiaSheet(titulo: "Dia de \(r.nome)", dia: r.dia) { r.dia = $0; try? ctx.save() }
        }
    }
}

/// Escolher um dia do mês (1 a 31)
struct DiaSheet: View {
    let titulo: String
    let salvar: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dia: Int

    init(titulo: String, dia: Int, salvar: @escaping (Int) -> Void) {
        self.titulo = titulo
        self.salvar = salvar
        _dia = State(initialValue: dia)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titulo).font(.system(size: 21, weight: .bold))
            Picker("Dia", selection: $dia) {
                ForEach(1...31, id: \.self) { Text("Dia \($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Button("Salvar") {
                salvar(dia)
                dismiss()
            }
            .buttonStyle(EstiloPrincipal())
        }
        .padding(28)
        .folha([.height(380)])
    }
}
