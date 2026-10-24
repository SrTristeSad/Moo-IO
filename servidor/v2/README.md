# Moo-IO — Servidor privado V2: mods e personalizacao

Esta e a **primeira etapa funcional de mods de dados** para um servidor independente, instalado pelo dono na propria maquina/VPS. **Nao e um novo cliente.** Reutiliza o motor autoritativo de `windows/server/src/`, os dados de referencia `windows/shared/` e o protocolo existente.

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
