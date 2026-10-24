# Moo-IO — Servidor dedicado V2 (fase 1)

Implementacao funcional **independente dos clientes Windows e Android**. Reutiliza o motor de partida autoritativo de `windows/server/src` e a referencia `windows/shared`, sem criar uma segunda simulacao de combate, mapa ou recursos.

## Executar a partir do repositório

Requisitos: Node.js 20+ e dependencias do motor instaladas **durante a preparacao**:

```bash
npm install --prefix windows/server --no-audit --no-fund
node servidor/v2/cli.mjs init --host 127.0.0.1 --port 8080 --bots 0
node servidor/v2/cli.mjs doctor
node servidor/v2/cli.mjs start
```

Por padrao, a sala so aceita conexoes do proprio computador. Para jogar com amigos, escolha **o IPv4 privado atribuido ao anfitriao** (como `192.168.1.10`) no `init`:

```bash
node servidor/v2/cli.mjs init --host 192.168.1.10 --port 8080 --bots 3
```

O comando `init` cria `servidor/v2/instance/server.json` **uma unica vez**, com codigo de convite aleatorio. Nunca sobrescreve o codigo existente. Para trocar configuracoes, edite o arquivo e reinicie a sala, ou crie outro `--config` em uma pasta separada. **Nao publique o codigo da sala nem o JSON de configuracao.** Dados persistentes (contas, moderacao, protocolo) ficam isolados em `instance/data/`.

## Distribuicao sem dependencias baixadas pelo jogador

O workflow do GitHub Actions prepara as dependencias e monta `Moo-IO-Servidor-V2`. Para empacotar localmente apos `npm install --prefix windows/server`:

```bash
node servidor/v2/tools/package.mjs
```

A saida esta em `servidor/v2/dist/Moo-IO-Servidor-V2/`. No Windows, tambem podem ser usados `CRIAR-SERVIDOR.cmd`, `INICIAR-SERVIDOR.cmd` e `DIAGNOSTICAR-SERVIDOR.cmd` (duplo clique); os arquivos `.sh` fazem o mesmo no Linux. O pacote inclui `LICENSE`, `NOTICE.md` e os avisos de licenca do servidor original. Copie **a pasta inteira** para outra maquina com Node.js 20+. Ela contem o motor, configuracoes compartilhadas, dependencias e launcher; nao exige os clientes Lua nem npm durante a execucao.

## Conectar

Clientes Windows e Android compativeis: **Jogar > Entrar em outra sala**, digite IP privado, porta e codigo de convite. O servidor oferece `GET /ping`, `GET /mooio/status`, `GET /mooio/protocol`, `POST /api/join` e o WebSocket `/s/LC`. O servidor nao depende de um navegador para atender ao cliente Lua. Os bots (0 a 8) usam a mesma logica do motor existente.

## Status de seguranca e limites

**Somente rede local/hotspot ou VPN privada confiavel.** O motor atual ainda usa autenticacao de teste (inclusive codigo de email e senha sem verificacao real) e nao oferece TLS/WSS. Nao use port forwarding, servidor publico ou VPS diretamente, mesmo com codigo de convite. O convite limita a emissao de tickets, mas nao representa autenticacao de producao.

Esta primeira etapa cria **uma instancia de processo/sala com codigo privado**, sem orquestrador de multiplas salas, painel web, login seguro, atualizador nem hospedagem publica. Nao modifica o servidor embutido dos aplicativos nem o protocolo.
