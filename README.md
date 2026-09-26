# The Box App

App de contas e gastos para iPhone (iOS 17 ou mais recente), instalado pelo AltStore, sem App Store e sem Mac.

## 1. Gerar o app (.ipa) no GitHub

1. Crie uma conta grátis em github.com.
2. Crie um repositório novo (botão **New**). O nome pode ser `thebox`.
   - **Public**: compilações ilimitadas e grátis.
   - **Private**: cerca de 200 minutos de Mac por mês no plano grátis. Cada compilação leva de 5 a 10 minutos.
3. No repositório, clique em **Add file → Upload files** e arraste **todo o conteúdo** desta pasta, incluindo a pasta `.github`. Clique em **Commit changes**.
4. Abra a aba **Actions**. A compilação "Gerar IPA" começa sozinha. Espere ficar verde ✅.
5. Clique na compilação e, em **Artifacts**, baixe **TheBox-ipa**. Descompacte para obter o `TheBox.ipa`.

Sempre que você alterar algum arquivo no GitHub, um `.ipa` novo é gerado.

## 2. Instalar o AltStore (uma vez só, no PC Windows)

1. Instale o **iTunes** e o **iCloud** baixados do site da Apple, e **não** da Microsoft Store. Se tiver a versão da Microsoft Store, desinstale antes.
2. Baixe o **AltServer** em altstore.io, instale e abra. Aparece um ícone de losango perto do relógio.
3. Ligue o iPhone no PC pelo cabo e toque em **Confiar** no iPhone.
4. Clique no ícone do AltServer → **Install AltStore** → escolha seu iPhone e entre com seu Apple ID.
5. No iPhone, vá em **Ajustes → Geral → VPN e Gerenciamento de Dispositivos**, toque no seu Apple ID e em **Confiar**.
6. Ative **Ajustes → Privacidade e Segurança → Modo de Desenvolvedor** e reinicie o iPhone.

## 3. Instalar o The Box App

1. Passe o `TheBox.ipa` para o iPhone, por exemplo pelo iCloud Drive, e salve no app **Arquivos**.
2. Abra o **AltStore → My Apps → +** e escolha o `TheBox.ipa`.
3. Abra o The Box App e permita as notificações.

**Renovação a cada 7 dias:** deixe o AltServer aberto no PC com o iPhone no mesmo Wi-Fi. O AltStore renova sozinho em segundo plano, ou você pode tocar em **Refresh All**. Se passar dos 7 dias, o app para de abrir, mas os dados não se perdem: é só renovar.

## 4. Automação da maquininha

No app, vá em **Config → Automação da maquininha → Como configurar**. Resumindo:
Atalhos → Automação → + → **Transação** → escolha os cartões → **Executar Imediatamente** → ação **Registrar gasto** (The Box App).
- **Valor**: use a variável da transação que traz o valor da compra.
- **Descrição, Categoria e Tipo de pagamento**: escolha **Perguntar Sempre**.

## 5. Amigos

Mande o `TheBox.ipa` para eles. Cada um precisa fazer o passo 2 no próprio PC (ou Mac) com o próprio Apple ID. Os dados de cada pessoa ficam só no iPhone dela.
