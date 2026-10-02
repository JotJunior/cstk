---
name: feature-00c-abort
description: Abortar uma execução feature-00c existente no Codex, encerrando a onda, preservando código e histórico e emitindo relatório auditável. Use para feature-00c-abort, com motivo e purge-backups apenas se explicitamente solicitado.
---

# Abortar feature no Codex

Leia ../feature-00c/references/lifecycle.md, seção Aborto.
Identifique a raiz da sessão e o short-name autorizado. Se já houver onda
própria dessa execução no MCP, chame cstk_abort na mesma conexão.
Caso contrário selecione kind=feature, confira cstk_status e chame cstk_abort.
Use o motivo fornecido pelo operador ou aborto manual. Não transforme pedido
de pausa em aborto. purge_backups só recebe true se solicitado explicitamente.

Confira status abortada (ou o terminal já existente), report e commit_status.
Preserve os artefatos e commits anteriores. Dono vivo de outra conexão não
é removido; use a conexão proprietária. Origem Claude exige transferência
explícita ou aborto no runtime original, conforme o contrato compartilhado.
