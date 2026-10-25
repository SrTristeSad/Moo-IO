# Moo-IO — Servidor privado V2: mods e personalizacao

## Acesso público direto com HTTPS/WSS verificados

**Novo:** o cliente reconhece convites de salas publicados pelo gateway Caddy, no formato `https://normal.jogo.seudominio.com/CODIGO`. Ao entrar em uma sala V2, a página de autenticação abre no navegador; as solicitações da API, o ticket, o protocolo e o WebSocket passam por uma ponte TLS validada. Para partidas públicas, não existe fallback para HTTP/WS.

O certificado do servidor é verificado pelo mecanismo confiável da plataforma: `tls.connect` do Node 22 já distribuído no **Windows**, ou `SSLSocketFactory`/`SSLParameters.setEndpointIdentificationAlgorithm("HTTPS")` no **Android**. Ambos validam autoridade certificadora, validade, hostname SNI e TLS 1.2+. Certificados vencidos, autoassinados não confiáveis ou de outro domínio impedem a conexão. Não há opção de ignorar certificados.

No Windows, o jogo inicia sob demanda um relay Node oculto, em `127.0.0.1:8469`, usando `runtime/node/node.exe` + `scripts/tls-relay.mjs`. O filho é encerrado ao sair do jogo. No Android, `MooIOActivity` inicia a ponte Java no processo normal do app, sem iniciar o servidor Node de hospedagem e sem notificação persistente. A comunicação local requer um token aleatório privado, e a ponte só permite destinos DNS e porta 443.

O jogador deve informar o convite HTTPS completo na tela **Jogar**. O backend da VPS precisa estar configurado com Caddy, DNS e TLS válidos; as portas internas da sala e do painel administrativo continuam privadas. Em redes LAN/VPN, convites por IP continuam usando o modo anterior.

Esta versão muda o **código-fonte** Android e Windows. O Windows exige reconstrução do ZIP; o Android exige um novo APK nativo com `MooIOTlsBridge.java`. Instalações antigas não ganham TLS até receberem um pacote atualizado. O teste do transportador no GitHub não substitui uma validação real em dispositivos Android conectados a uma VPS.


Esta e a **primeira etapa funcional de mods de dados** para um servidor independente, instalado pelo dono na propria maquina/VPS. **Nao e um novo cliente.** Reutiliza o motor autoritativo de `windows/server/src/`, os dados de referencia `windows/shared/` e o protocolo existente.

## Login hospedado no navegador — serviço central V2

O servidor privado V2 agora inclui um **serviço de contas compartilhadas por todas as salas da mesma VPS**, com página web própria de login e cadastro. O cliente não transmite nem armazena a senha.

Fluxo PKCE S256: o aplicativo gera um `verifier` aleatório e envia o respectivo SHA-256/base64url como `challenge` a `POST /v1/authorize/start` via HTTPS. Abre no navegador externo o `verificationUri` devolvido pelo servidor. A página valida a senha e solicita a autorização; o aplicativo consulta `POST /v1/authorize/token` com `id` e `verifier` até receber um token de sessão de uso protegido. A autorização expira em 5 minutos e a troca é de uso único.

Para entrar numa sala, o aplicativo usa `POST /api/auth/browser` dessa sala com o token central. A sala consulta o hub exclusivamente em localhost, usando um segredo privado, e emite seu JWT próprio de 15 minutos. O ticket de `/api/join` e a partida continuam usando o protocolo original; as salas preservam seus banimentos e controles independentes.

### Instalar na VPS

```bash
git pull origin main
node servidor/v2/identity.mjs configure --origin https://auth.jogo.seudominio.com
bash servidor/v2/deploy/install-ubuntu.sh
systemctl --user status mooio-v2-identity.service
```

O instalador cria `mooio-v2-identity.service` e somente o ativa automaticamente se a origem HTTPS já estiver configurada. O hub fica restrito a `127.0.0.1:8788`, independente dos serviços de salas e do painel.

Gere o gateway HTTPS para as salas e o login:

```bash
node servidor/v2/gateway.mjs generate --domain jogo.seudominio.com --auth
```

Configure o DNS de `auth.jogo.seudominio.com` e dos subdomínios das salas, certificados HTTPS do Caddy e firewall expondo somente portas 80/443. **Nunca exponha 8787, 8788, portas internas do motor, `/internal/introspect` ou seus arquivos de segredo.** O Caddy gerado aceita somente rotas públicas explicitamente permitidas.

### Limites atuais

- Contas antigas armazenadas em cada sala não são migradas automaticamente. A identidade central funciona apenas entre salas da mesma VPS.
- O cadastro ainda não verifica a propriedade do e-mail e ainda não fornece recuperação de senha por e-mail; não trate o endereço como verificado.
- O token central pode ser revogado, mas JWTs de sala já emitidos podem continuar válidos até expirar (até 15 minutos).
- **Windows/Android Lua agora possuem a ação Entrar na conta V2 (navegador) para LAN e VPN privadas**, com PKCE encaminhado pelo servidor da sala. O token central de sete dias fica no backend; o jogo recebe somente um JWT da sala de até 15 minutos. Ainda falta transporte HTTPS/WSS nativo e certificado validado para acessar IPs públicos diretamente; não use o modo privado em redes públicas não confiáveis.
- O cliente LAN e o login legado para salas locais permanecem separados e não foram removidos.

### Login pelo navegador no cliente LAN/VPN

Com o serviço de identidade e o Caddy configurados na VPS, conecte o dispositivo à rede privada/VPN do proprietário. Na tela **Jogar**, informe o IP privado ou virtual da sala, porta e código de convite; em seguida clique em **Entrar na conta V2 (navegador)**. O navegador abre a página HTTPS do servidor; após autorizar, volte ao jogo. O cliente consulta a sala periodicamente e entra automaticamente quando recebe a autorização.

A sala oferece `/api/auth/v2/start` e `/api/auth/v2/token`, protegidos pelo convite. Esses endpoints encaminham apenas PKCE ao hub em localhost. A sessão central é validada e revogada pelo próprio servidor; **somente o JWT temporário da sala volta para o Lua**. O navegador mantém um cookie seguro HttpOnly para permitir aprovar outras salas sem redigitar a senha.

**Atenção:** o cliente Lua usa HTTP e WS para jogar. Esse fluxo é exclusivamente para IPs privados LAN/VPN; prefira VPN criptografada (como Tailscale) para proteger o JWT temporário e a partida. Não significa que o cliente já suporta HTTPS/WSS de ponta a ponta em uma VPS pública. Não exponha diretamente portas internas no firewall.
## Banimento temporario, historico e permissoes do painel (novo)

O painel agora permite banir por **5, 15, 60, 360, 1440 ou 10080
minutos** (ate sete dias), consultar banimentos ativos, revoga-los
antes do vencimento e consultar um historico das ultimas 50 acoes.
O historico e armazenado no disco privado de cada sala (ate 200
registros) e permanece apos reiniciar o processo. Dados brutos
de IP e dispositivo **nao sao mostrados** no painel.

Na VPS:

```bash
node servidor/v2/manager.mjs ban normal ID_DA_SESSAO 60
node servidor/v2/manager.mjs bans normal
node servidor/v2/manager.mjs history normal
node servidor/v2/manager.mjs unban normal ID_DO_BANIMENTO
```

Banimentos atuam na identidade persistente da conta ou dispositivo
reconhecido pelo motor. Nao sao aplicados por IP compartilhado neste
controle; convidados sem identificacao persistente podem ser expulsos,
mas nao banidos por prazo. Moderadores e administradores dentro do
jogo nao podem ser banidos por este painel. Expulsar nao e banir.

**Permissoes para o painel:**
- **Proprietario**: administra salas, mods, jogadores, banimentos e
  configuracoes. Continua entrando com sua senha atual, sem email.
- **Moderador**: consulta salas e jogadores; expulsa, bane e revoga
  banimentos. Nao pode criar, alterar, iniciar, parar ou reiniciar salas.
- **Observador (viewer)**: consulta salas, jogadores e historico de
  moderacao; nao pode realizar alteracoes.

Somente o proprietario da VPS configura as credenciais da equipe, pelo
terminal da conta Linux que executa o servico. O email nunca aparece
em listas de jogadores:

```bash
read -rsp "Senha do moderador: " SENHA; echo
printf '%s\n' "$SENHA" | node servidor/v2/panel.mjs staff moderador@exemplo.com moderator
unset SENHA

# Observador: substitua moderator por viewer
# Revogar acesso (sem enviar senha):
node servidor/v2/panel.mjs staff moderador@exemplo.com revoke

# Recarregar credenciais de login da equipe:
systemctl --user restart mooio-v2-panel.service
```

A senha exige 12 a 128 caracteres, protegida por scrypt, com
armazenamento em arquivo 0600. Mudancas de cargo e revogacao
invalidam sessoes existentes assim que sao verificadas. O painel
continua **somente localhost/SSH**; nao exponha a porta 8787.

## Administrar jogadores conectados (novo)

A V2 agora permite visualizar **os jogadores conectados a cada sala**
e expulsar apenas uma sessao, pelo painel ou pelo terminal do servidor.

```bash
node servidor/v2/manager.mjs players normal
node servidor/v2/manager.mjs kick normal ID_DA_SESSAO
```

No painel local da VPS, use **Jogadores** na sala escolhida. A lista
exibe nome, funcao (convidado, jogador, moderador ou administrador) e
um identificador de sessao. **Nao expõe IP, e-mail, senha, convite nem
token de autenticacao.** O botao **Expulsar** requer confirmacao e
atua exclusivamente na sessao selecionada. Contas classificadas como
moderador ou administrador nao podem ser expulsas por este controle.

A expulsao desconecta a sessao, mas **nao e um banimento**. O jogador
pode entrar novamente se continuar autorizado. A interface nao concede
cargos ou altera permissoes de contas nesta etapa; somente a senha
administrativa do painel permite esses controles. A operacao passa
pelo socket privado ja autenticado do supervisor e por um segundo
canal IPC entre supervisor e motor, sem criar qualquer endpoint
HTTP publico para expulsao.

## Encerramento individual e eventos operacionais (novo)

O painel agora oferece **Encerrar sala** e **Eventos**. O encerramento
afeta apenas a partida escolhida: quem estiver nela sera desconectado
e o supervisor **nao a reiniciara automaticamente**. Outras salas
continuam em execucao. Para reabrir a partida use **Iniciar sala** ou
o comando `start-room`.

```bash
node servidor/v2/manager.mjs stop-room lobos
node servidor/v2/manager.mjs events lobos
node servidor/v2/manager.mjs start-room lobos
```

O historico mostra os ultimos 20 eventos estruturados por sala
(inicio, parada, reinicio, watchdog e falha), em memoria. Ele nao
mostra saida bruta do motor, tokens, senhas ou codigos de convite.
O supervisor guarda no maximo 40 eventos por sala e perde esse
historico ao reiniciar; para historico persistente do servico use
`journalctl --user -u mooio-v2.service` no SSH com acesso autorizado.

Os comandos passam pelo socket de controle privado da VPS; nenhuma
nova porta administrativa e aberta. No painel, a parada requer
confirmacao e a autenticacao/CSRF ja existentes.

## Painel administrativo da VPS (novo)

O painel V2 funciona **no navegador**, sem WebView nos clientes, para
administrar salas tradicionais e personalizadas e seus mods. Ele tem
visao geral das salas online/offline, jogadores e capacidade, criacao
de salas, edicao de nome, bots, limite de jogadores e escolha de mods,
alem do botao de reiniciar apenas uma sala.

Por seguranca, **o painel nunca abre uma porta publica**. Escuta
somente `127.0.0.1:8787` e usa uma senha administrativa independente
das contas dos jogadores, hash scrypt com salt, cookies HttpOnly,
SameSite=Strict, tokens anti-CSRF e verificacao de Origin e Host.

**1. Configure a senha no terminal da VPS, usando a conta que executa
o servidor e sem colocar a senha na linha de comando:**

```bash
read -rsp "Senha do painel (12+ caracteres): " SENHA; echo
printf '%s\n' "$SENHA" | node servidor/v2/panel.mjs password
unset SENHA
```

**2. Para VPS Ubuntu/Debian com systemd:** rode novamente o instalador
atualizado (na conta Linux que hospeda o servidor). Ele configura os
**dois servicos separados**, sem reinstalar ou sobrescrever as salas:

```bash
bash servidor/v2/deploy/install-ubuntu.sh
systemctl --user status mooio-v2.service
systemctl --user status mooio-v2-panel.service
```

O servico `mooio-v2-panel.service` so e ativado quando a senha
administrativa foi cadastrada; caso contrario, fica instalado mas
desativado. Para ativar apos definir a senha, rode:

```bash
systemctl --user enable --now mooio-v2-panel.service
```

Alternativamente, inicie o painel manualmente:
```bash
node servidor/v2/panel.mjs serve
```
Para verificar a senha configurada, sem exibí-la:
`node servidor/v2/panel.mjs check`.

**3. No seu computador Windows, estabeleca um tunel SSH ate a VPS:**

```bash
ssh -L 8787:127.0.0.1:8787 ubuntu@IP_DA_VPS
```

Abra **http://127.0.0.1:8787** no seu proprio navegador.
Substitua `ubuntu` pelo usuario real da VPS. Para salas em outro
diretorio, use `--rooms /caminho/salas` ao configurar a senha e iniciar
o painel. Se a porta 8787 do seu computador estiver ocupada, escolha outra porta
no comando `panel.mjs serve --port NUMERO` e use o mesmo numero no
encaminhamento SSH e no endereco do navegador.

As configuracoes sao salvas e verificadas contra as definicoes reais
do jogo. Depois de editar uma sala existente, clique em **Reiniciar sala**
para aplicar as alteracoes sem derrubar as demais. **Salas novas sao
iniciadas automaticamente** pelo controlador privado em execucao; as
outras salas continuam conectadas. Se o controlador estiver offline,
a nova configuracao sera salva e o painel mostrara **Iniciar sala** para
tentar novamente quando o controlador voltar.

Tambem pode iniciar uma sala recem-criada pelo terminal:
`node servidor/v2/manager.mjs start-room ID`.
Esse comando valida portas e mods e nao altera o processo das salas
existentes. O gateway Caddy precisa ser reconfigurado separadamente
para expor um novo subdominio; a criacao da sala nao publica portas.

**Nao** adicione a porta 8787 ao firewall publico, nao a exponha no
Caddy nem use redirecionamento publico de portas no roteador. O painel nao oferece
administracao HTTP publica, recuperacao de senha, edicao de scripts
arbitrarios ou alteracao de portas de salas existentes. Se alterar a
senha, reinicie tambem o processo do painel; as sessoes antigas sao
mantidas apenas na memoria do processo.

## Reiniciar uma sala sem derrubar as outras (novo)

A V2 permite aplicar configuracoes e mods de uma sala **individualmente**
enquanto as demais continuam online. O controlador abre apenas um **socket
local privado**, nao uma API HTTP: o acesso administrativo precisa de
permissoes no sistema e um token aleatorio salvo em
`servidor/v2/rooms/.control/admin.token` (0600 no Linux).
No Linux o controle usa um socket Unix 0600; no Windows, um named pipe
local mais autenticacao por token. Ele nao passa por Caddy, nao exige
IP publico e nunca revela o token na linha de comando.

```bash
# 1. Personalize mods ou configuracoes de uma sala ja existente:
node servidor/v2/cli.mjs enable colheita-farta --file servidor/v2/rooms/lobos.json

# 2. Valide antes de aplicar:
node servidor/v2/cli.mjs preview --file servidor/v2/rooms/lobos.json

# 3. Reinicie SOMENTE a sala chamada lobos:
node servidor/v2/manager.mjs restart lobos
```

Use `--rooms caminho` quando o controlador foi iniciado com outra pasta
de salas. A ordem dos comandos de modificacao e reinicio e importante:
`restart` relê o JSON da sala, valida todos os mods e so entao encerra
o processo antigo e abre o novo. **Se o mod for invalido, o processo
antigo nao e parado.** Uma sala nao pode reiniciar outra, pois IDs sao
validados e so o supervisor tem o canal de controle. Reinicios
administrativos nao consomem o limite de falhas automáticas.

**Limitacao deliberada:** mudancas de host, porta ou modo de rede
exigem parar o controlador, ajustar o Caddy/DNS quando aplicavel e
iniciar novamente. Um reinicio individual desconecta os jogadores
daquela sala. Os jogadores das outras partidas continuam conectados.
O comando responde quando o novo processo e iniciado; consulte
`manager.mjs health` para confirmar que ele ficou pronto.

## Monitoramento e recuperacao de salas na VPS (novo)

O controlador suporta multiplas salas independentes e agora disponibiliza
diagnosticos somente pelo terminal, sem criar interface administrativa
HTTP publica:

```bash
# Relatorio simples: salas online, jogadores atuais e capacidade:
node servidor/v2/manager.mjs status

# Dados JSON para ferramentas externas (sem codigo de convite):
node servidor/v2/manager.mjs status --json

# Health check: codigo de saida 0 quando todas online; 1 quando alguma falha
node servidor/v2/manager.mjs health
node servidor/v2/manager.mjs health --json

# Acompanhar mudancas sem inundar logs com relatorios repetidos
node servidor/v2/manager.mjs watch --interval 15
```

O JSON informa total de salas, quantas estao online/offline, jogadores
e lotacao, assim como a disponibilidade e o numero de mods de cada sala.
Os codigos privados de convite, hashes de senha e tokens nao aparecem.
O comando `health` serve para verificacoes locais do systemd, scripts
de administracao e diagnosticos via SSH; **nao publique sua saida
indiscriminadamente como API**.

O processo controlador agora executa um watchdog: depois de uma janela
de inicializacao de 20 segundos, confere as salas a cada 15 segundos.
Ao detectar **tres falhas consecutivas de resposta**, encerra e reinicia
somente aquela sala. Se um processo parar de responder a sinais normais,
pode ser encerrado forcosamente apos mais 5 segundos. Salas saudaveis
continuam funcionando. Falhas sucessivas de inicializacao ainda respeitam
o limite de reinicios do supervisor; o watchdog nao substitui monitoramento
da VPS nem garante recuperacao em falta de RAM ou CPU.

## Gateway HTTPS/WSS para VPS (novo)

O gateway publica **cada sala com um subdominio** usando o proxy Caddy.
O motor de jogo continua em portas **exclusivamente loopback** (127.0.0.1);
nao alteramos os clientes nem abrimos as portas internas. O proxy gerencia
certificados HTTPS e upgrades para WebSocket (WSS).

Exemplo: com duas salas `normal.json` e `lobos.json` e dominio base
`jogo.exemplo.com`, os jogadores usariam
`https://normal.jogo.exemplo.com` e `https://lobos.jogo.exemplo.com`.
O WebSocket usa `wss://normal.jogo.exemplo.com/s/LC` e o jogo continua
protegido por codigo de convite **e** conta/senha V2.

**Etapas do administrador da VPS:**

1. Ter um dominio real. Criar registros DNS A (e AAAA somente se a VPS
   aceita IPv6) para cada subdominio apontando para o IP publico da VPS.
2. Manter `servidor/v2/rooms/*.json` com `"host": "127.0.0.1"` e
   `"network": "lan"`, usando uma porta diferente por sala.
3. Instalar Caddy pelo gerenciador de pacotes/distribuicao (fora deste
   programa). Gerar e conferir o arquivo:

```bash
node servidor/v2/gateway.mjs plan --domain jogo.seudominio.com
node servidor/v2/gateway.mjs write --domain jogo.seudominio.com
caddy adapt --config servidor/v2/deploy/Caddyfile.generated --adapter caddyfile
```

4. **Depois de revisar** os dominios e as portas, copiar o arquivo
   validado para a configuracao real do Caddy (em uma VPS dedicada):
```bash
sudo install -m 644 servidor/v2/deploy/Caddyfile.generated /etc/caddy/Caddyfile
sudo systemctl reload caddy
```
   Isso substitui a configuracao existente do Caddy; se voce ja hospeda
   sites na VPS, incorpore os blocos de salas a configuracao atual em vez
   de substitui-la. Nunca instale Caddy diretamente com permissao de root
   para rodar o motor de jogo.
5. Liberar **somente portas TCP 80 e 443** para o Caddy e manter fechadas
   as portas internas 8080, 8083, etc. O motor nao deve aceitar conexoes
   publicas diretas.

`gateway.mjs generate --domain ...` imprime o Caddyfile sem gravar;
`write` cria `Caddyfile.generated` sem sobrescrever, a menos que voce
peça `--force`. Use `--rooms pasta` caso as salas fiquem em outro
diretorio. O arquivo gerado bloqueia rotas administrativas, limpa
cabecalhos de proxy falsificados e preserva o Host, necessario ao
handshake WebSocket. Mods continuam separados por sala.

**Limites atuais:** e uma primeira etapa de gateway, nao uma plataforma
publica endurecida. Ainda sao necessarios protecao contra DDoS,
monitoramento/cotas, rotacao de tokens, cadastro/redefinicao de senhas
e testes E2E com clientes Windows/Android apontando para WSS.
O `gateway.mjs` nao instala Caddy nem modifica o firewall;
TLS so funciona depois de configurar dominio/DNS e iniciar o Caddy.
Nao configure CDN na frente do proxy sem revisar confianca de IPs.

## Autenticacao de jogadores na V2 (nova)

Salas V2 agora **exigem conta e senha real** antes de emitir tickets de
ingresso. O sistema de login de teste (qualquer senha/codigo de seis digitos)
fica exclusivamente no servidor LAN antigo e esta **desabilitado** na V2.
A V2 armazena hashes scrypt com salt aleatorio e nao grava senhas em
texto puro. Cada sala tem sua propria base de jogadores e credenciais.

**Por enquanto o cadastro e administrado pelo dono do servidor**, sem
registro publico, envio de email ou recuperacao automatica de senha.
O jogador autenticado usa a rota de login por senha ja existente.
Para criar uma conta, rode na VPS como usuario dono das salas:

```bash
# Leia a senha sem mostra-la no terminal e encaminhe apenas pelo stdin:
read -rsp "Senha do jogador (12+ caracteres): " SENHA; echo
printf '%s\n' "$SENHA" | node servidor/v2/accounts.mjs set-password \
  --file servidor/v2/rooms/principal.json --email jogador@example.org
unset SENHA

# Reinicie a sala se ela ja estiver executando, para carregar nova credencial.
systemctl --user restart mooio-v2.service
```

O comando nunca aceita `--password` na linha de comandos e nao imprime
a senha. **Nao envie arquivos de credenciais nem senhas ao Git**.
As tentativas de login sao limitadas; `/api/auth/code` e
`/api/auth/verify` retornam 410 em salas V2. Entrar como convidado,
inclusive mandando `captcha:true`, nao emite um ticket na V2.

O modo `traditional` preserva a jogabilidade original; agora tambem
exige autenticacao por senha como qualquer outra sala privada V2.
Essa implementacao NAO inclui cadastro integrado ao cliente ou
recuperacao de senhas. O gateway HTTPS/WSS e gerado pela V2, mas
**precisa ser configurado e ativado pelo administrador antes do acesso publico**. Clientes so poderao
autenticar diretamente se tiverem suporte ao fluxo de login por senha.

## Instalacao em VPS Ubuntu/Debian (nova)

A V2 ganhou um assistente para instalar o motor com Node.js 22+ e criar
uma sala tradicional privada por padrao (`127.0.0.1:8080`), se nao
existirem outras salas configuradas. Execute como **usuario normal**, nunca
como root:

```bash
bash servidor/v2/deploy/install-ubuntu.sh
```

O instalador instala as dependencias em `windows/server`, valida todas
as salas/mods, cria `~/.config/systemd/user/mooio-v2.service` e habilita
o controlador para iniciar suas salas com o systemd de usuario. Se ja
existirem salas, nenhuma sera sobrescrita. Os arquivos com codigos
de convite continuam protegidos com permissao 0600.

Diagnostico ou preparacao manual, sem ativar o servico:

```bash
node servidor/v2/vps.mjs setup
node servidor/v2/vps.mjs doctor
node servidor/v2/vps.mjs unit   # imprime a configuracao de systemd, sem instalar
```

Comandos de manutencao:

```bash
systemctl --user status mooio-v2.service
journalctl --user -u mooio-v2.service -f
node servidor/v2/manager.mjs status
systemctl --user restart mooio-v2.service
systemctl --user stop mooio-v2.service
```

Para continuar funcionando **apos desconectar do SSH**, habilite
explicitamente o linger da conta (administrador da VPS):
`sudo loginctl enable-linger "$(id -un)"`.

O instalador nao exige sudo nem mexe no firewall. **Importante:**
autenticacao real por senha ja existe na V2, mas o acesso externo
exige configurar DNS, Caddy com TLS valido e regras de firewall.
O gerador do gateway esta documentado acima; ele nao ativa acesso publico
sozinho. Ainda faltam monitoramento de ataques, mitigacao de DDoS
e um fluxo de cadastro/recuperacao de senha para uma hospedagem publica madura.

## Comece sem programar

Requisitos: Node.js 22+, codigo completo do repo, dependencias preparadas no `windows/server` (`npm install --prefix windows/server` em Linux; `cd windows/server && npm install` no Windows).

```bash
# Uma sala igual ao jogo original (sem mods)
node servidor/v2/cli.mjs init --name "Servidor Tradicional" --preset traditional

# OU crie outra configuracao, separada, ja preparada para mods:
node servidor/v2/cli.mjs init --name "Minha sala especial" --preset custom --file servidor/v2/rooms/especial.json --port 8083

# Veja mods disponiveis e o catalogo de indices de armas/animais/construcoes
node servidor/v2/cli.mjs mods
node servidor/v2/cli.mjs catalog

# Altere configuracoes sem editar arquivos JSON (ex.: bots e capacidade)
node servidor/v2/cli.mjs configure --file servidor/v2/rooms/especial.json --bots 3 --capacity 40 --name "Mundo dos Animais"

# Ative um mod na sala personalizada
node servidor/v2/cli.mjs enable colheita-farta --file servidor/v2/rooms/especial.json
node servidor/v2/cli.mjs enable mais-lobos --file servidor/v2/rooms/especial.json

# Veja exatamente o que sera modificado, sem alterar o motor
node servidor/v2/cli.mjs preview --file servidor/v2/rooms/especial.json

# Inicie: um processo por sala
node servidor/v2/cli.mjs start --file servidor/v2/rooms/especial.json
```

Se ja executou `init`, ele nao substituira sua sala nem alterara o codigo de convite. Edite o JSON de sua sala para mudar nome, porta, bots (0–8), capacidade (1–40), preset ou lista de mods. O arquivo pode ser salvo e versionado sem colocar segredos reais no Git; **nao publique o roomCode**.

## Gerenciar varias salas na mesma VPS (novo)

Uma sala e um arquivo `rooms/<id>.json` e um processo Node independente.
Cada processo carrega seu proprio conjunto de mods, mapa, jogadores e dados.
O controlador valida **todas** as salas antes de abrir qualquer uma, impede
portas repetidas, inicia-as em paralelo, mostra seus logs com o ID da sala,
tenta reiniciar uma sala que cair (com espera progressiva e limite de falhas)
e para todas quando voce encerra o controlador. **Sem administrador HTTP publico.**

```bash
node servidor/v2/cli.mjs init --file servidor/v2/rooms/normal.json --name "Normal" --port 8080
node servidor/v2/cli.mjs init --file servidor/v2/rooms/lobos.json --name "Lobos" --preset custom --port 8083
node servidor/v2/cli.mjs enable mais-lobos --file servidor/v2/rooms/lobos.json

node servidor/v2/manager.mjs check
node servidor/v2/manager.mjs start
# em outro terminal, consultar numero de jogadores sem exibir codigos:
node servidor/v2/manager.mjs status
```

O controlador procura apenas arquivos regulares `<id>.json` na pasta
`servidor/v2/rooms/`; links simbolicos e portas repetidas sao recusados.
Limite operacional inicial: ate 32 configuracoes **por controlador**, sem
promessa de que a VPS aguente todas simultaneamente. Cada sala permite
ate 40 jogadores; desempenho depende de CPU e carga real. Para hospedar
continuamente, gerencie o controlador via systemd/servico do SO; ele nao faz
daemonizacao nem agenda atualizacoes. Configuracoes/mods sao lidos no inicio:
reinicie o controlador para aplicar mudancas.

**VPS publica:** nao conecte a porta do jogo diretamente a internet.
Esta versao ainda exige loopback/LAN/VPN privada e **nao oferece**
TLS/WSS, autenticacao publica robusta ou gateway de jogadores. Esses
itens sao trabalho separado para disponibilizar salas na Internet.

## Como criar mods

Cada mod e um **arquivo JSON** em `servidor/v2/mods/ID.json`. Copie `colheita-farta.json`, mude ID/nome e personalize os parametros. Em seguida, execute `enable ID` e `preview`. O `catalog` lista os indices usados pela versao real do jogo; nao chute os numeros.

Exemplo:
```json
{
  "schemaVersion": 1,
  "id": "vacas-gigantes",
  "name": "Vacas mais resistentes",
  "requiresClient": "base",
  "changes": {
    "animals": {"0": {"health": 1200}},
    "spawns": {"0": {"desired": 18}},
    "world": {"treesPerArea": 12}
  }
}
```

**Modificacoes nesta etapa, aplicadas de verdade no motor:**
- `world`: `treesPerArea`, `bushesPerArea`, `totalRocks`, `goldOres`.
- `animals`: `health`, `dmg`, `speed`, `killScore` quando ja existem no tipo escolhido.
- `spawns`: `desired` para animais com plano de spawn existente.
- `weapons`: `dmg` das armas existentes.
- `structures`: `health` e `dmg` para construcoes existentes.

Mods com alteracoes conflitantes sao recusados, nunca aplicados parcialmente. Referencias, validacoes e modos de partida sao preservados. Os valores sao ajustados **no processo da sala**, antes de carregar o motor autoritativo; outra sala roda isoladamente em outro processo.

`traditional` proibe mods, mantendo a configuracao de referencia. `custom` permite mods.

### O que AINDA nao e suportado

- Mods de codigo com scripts arbitrarios, hooks, Lua/JS executavel, ou download automatico.
- Novos sprites, armas ou tipos de animais nao definidos pelo cliente (exige protocolo e carregamento de assets).
- GUI/painel web de configuracao, autoatualizacao ou configuracao de proxies seguros. O controlador atual inicia multiplas salas, mas nao garante capacidade para 20+ partidas lotadas.
- Cadastro publico e recuperacao de senhas; TLS/WSS so depois de ativar Caddy com dominio e DNS. A V2 exige senha verificada, e o motor permanece vinculado apenas a IPv4 privado/loopback.

**VPS:** para conexoes externas, use somente o gateway Caddy gerado pela V2 e configure DNS/TLS; nao exponha as portas de jogo por port forwarding. Os mods continuam declarativos, sem executar scripts externos.
