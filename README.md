# LBO Finanças

App de contas, gastos e receitas para iPhone (iOS 17 ou mais recente). SwiftUI + SwiftData, login pelo Supabase com código de confirmação por e-mail. Compilado no GitHub Actions e instalado pelo AltStore, sem Mac.

## Estrutura

- `TheBox/` — código do app (o nome da pasta/target ficou `TheBox`; o nome que aparece no iPhone é **LBO Finanças**)
- `project.yml` — projeto do XcodeGen (bundle `com.lbofinancas.app`, pacote `supabase-swift`)
- `.github/workflows/build.yml` — gera o `LBO-Financas.ipa` a cada push na `main`
- `supabase/` — modelos de e-mail e SQL pra configurar o projeto no Supabase

## Configurar o Supabase (uma vez)

1. Em **Project Settings → API Keys**, copie a Project URL e a chave pública (anon/publishable) para `TheBox/Configuracao.swift`.
2. Em **Authentication → Emails → Templates**:
   - **Confirm signup**: assunto `Seu código do LBO Finanças` e corpo = conteúdo de `supabase/email-confirmar-cadastro.html`.
   - **Reset password**: assunto `Código para trocar sua senha` e corpo = conteúdo de `supabase/email-recuperar-senha.html`.
3. Em **SQL Editor**, rode `supabase/excluir-conta.sql` (habilita o "Excluir conta" do app).
4. O envio de e-mail padrão do Supabase tem limite baixo (poucos e-mails por hora). Antes de ter usuários de verdade, configure um SMTP próprio (ex.: Resend) em **Authentication → Emails → SMTP Settings**.

## Gerar e instalar

1. Push na `main` → aba **Actions** → "Gerar IPA" → artefato **LBO-Financas-ipa**.
2. No PC: AltServer aberto, iPhone no cabo, **Shift + clique no ícone do AltServer → Install AltStore → iPhone → Sideload .ipa** e escolha o `LBO-Financas.ipa`.
3. Renovação a cada 7 dias: AltServer aberto no PC e iPhone no mesmo Wi-Fi (ou **Refresh All** no AltStore).

## Automações (app Atalhos)

- **Toque duplo nas costas:** atalho com a ação **Novo registro** → Ajustes → Acessibilidade → Toque → Tocar Atrás → Toque Duplo.
- **Maquininha:** Automação → **Transação** → Executar Imediatamente → ação **Registrar gasto** (Valor = Quantia da transação).

O passo a passo completo está dentro do app em **Config → Automação**.
