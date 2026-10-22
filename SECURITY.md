# Seguranca — LAN somente

A API herdada possui login/CAPTCHA emulado, sem validacao real de usuarios. A configuracao de anti-cheat e local e a rede nao usa criptografia TLS/WSS.

**Nao publique este servidor na internet, VPS, tunel publico ou proxy reverso.**

Codigo de convite nao substitui autenticacao, isolamento de redes, controle de abuso e analise de seguranca. Outros endpoints herdados nao exigem o convite.

Compartilhe a porta TCP 8080 apenas com amigos na rede local confiavel. Nao utilize senhas reais como convite.

Hospedagem externa exige refazer os fluxos inseguros da API, criar autenticacao verdadeira, aplicar limitacoes de acesso, TLS/WSS e controles de abuso e realizar uma auditoria de seguranca.
