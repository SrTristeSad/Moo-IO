# Moo-IO — Servidor privado V2: mods e personalizacao

Esta e a **primeira etapa funcional de mods de dados** para um servidor independente, instalado pelo dono na propria maquina/VPS. **Nao e um novo cliente.** Reutiliza o motor autoritativo de `windows/server/src/`, os dados de referencia `windows/shared/` e o protocolo existente.

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
Essa implementacao NAO inclui ainda cadastro integrado ao cliente,
recuperacao de senhas nem gateway HTTPS/WSS. Ela e base de seguranca,
**nao autoriza publicar portas na Internet**. Clientes so poderao
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

O instalador nao exige sudo nem mexe no firewall. **Importante:** esta etapa NAO transforma a V2 em servidor publico:
autenticacao real por senha na V2 ja existe, mas faltam HTTPS/WSS,
seguranca de proxy, protecao contra abuso e gateway publico. Uso de loopback/VPN privada
e adequado apenas para testes controlados. Para acesso publico,
faltam autenticacao de producao, gateway e protecao contra abuso.

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
- Autenticacao segura de producao, TLS/WSS e hospedagem publica pronta. O motor herdado inclui autenticacao de **teste** e bloqueia vinculo direto com IPv4 publico.

**VPS:** esta etapa roda no loopback da VPS. Para acesso externo real ainda precisamos de proxy WebSocket seguro + nova autenticacao. Nao publique este servidor na internet por port forwarding. Os mods sao declarativos sem execucao de scripts externos: mais seguros para comecar a personalizacao.
