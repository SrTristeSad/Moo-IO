# NOTICE — Origem e alteracoes

## Servidor reconstruido por al007ex

https://github.com/al007ex/moomoo-clone
Commit: 06f7c1ca965a7628671676c8d9a7efd3997bb5e7
Licenca: Apache License 2.0 — consultar licenses/upstream-server-APACHE-2.0.txt.

Pastas importadas: server/src, server/package.json e shared.
A configuracao server/src/anticheat/config.js foi criada separadamente porque o upstream nao publicou essa dependencia.
O shared/config.js ajustou os valores de recursos/sandbox para jogabilidade normal.
O server/src/index.js foi adaptado com convite para ingressar e endpoint publico de protocolo.
O modulo novo server/src/mooio/invite.js implementa validacao de convites.

## Cliente Lua

Origem: https://github.com/SrTristeSad/Moo-Quest
Snapshot: 5ad8c32d1889dcb94e5645982acc2a0f2d570e09.
Adaptacoes no Moo IO: host remoto, convite, busca de constantes do protocolo pela rede, lancador local.
**Nenhuma pasta server-v2 nem modulo exclusivo da API V2 foi incorporado.**

Mudancas Moo IO licenciadas AGPL-3.0-only, respeitadas as licencas e avisos preexistentes.

O Moo IO nao e afiliado a FRVR ou ao jogo MooMoo.io oficial.
