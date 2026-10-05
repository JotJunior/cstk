---
name: feature-00c-abort
description: Use quando o usuário solicitar explicitamente feature-00c-abort no Codex para encerrar a execução da feature pela pipeline CSTK compartilhada.
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

## Gotchas

- Use a identidade e o kind do estado existente; não faça bootstrap para abortar.
- Dono vivo ou desconhecido nunca é roubado; recuperação exige PID registrado comprovadamente morto.
- Origem Claude/desconhecida exige handoff autorizado com proveniência preservada.
- Purge de backups requer pedido explícito; artefatos e histórico são preservados.
- Aborto não significa conclusão; execução concluída não é reclassificada.
