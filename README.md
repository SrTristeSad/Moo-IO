# Moo IO

Moo IO e a base comunitaria para partidas locais e servidores privados de um jogo 2D em Lua/LÖVE, com backend Node.js reconstruido de al007ex/moomoo-clone.

**Projeto separado de Moo-Quest.** O backend privado `server-v2/` de Moo-Quest nao faz parte deste repositorio.

## Escopo da primeira etapa

- Cliente Lua/LÖVE anterior a migracao V2;
- Servidor Node.js reconstruido (upstream Apache-2.0, com atribuicao);
- Criacao de sala na rede local e ingresso por endereco + codigo de convite;
- Mundo e gameplay autoritativos no servidor;
- Nenhum bundle oficial FRVR nem sprites/sons de terceiros sao redistribuidos.

Documentacao e instaladores serao adicionados nesta etapa. Conexao pela Steam/Internet e comandos de administracao mais completos sao etapas posteriores; convite LAN nao equivale a relay/NAT traversal.

## Origem e licencas

A implementacao do servidor vem do codigo reconstruido publicamente por [al007ex/moomoo-clone](https://github.com/al007ex/moomoo-clone), commit `06f7c1ca965a7628671676c8d9a7efd3997bb5e7`, sob Apache-2.0. Respeite os avisos e consulte `licenses/`. O codigo novo do Moo IO destina-se ao licenciamento AGPL-3.0, sujeito a auditoria de direitos de cada componente.

Nao distribua imagens, pacotes de cliente oficial nem conteudo de terceiros sem licenca adequada.
