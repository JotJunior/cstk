---
name: agente-00c-abort
description: Use quando o usuário solicitar explicitamente agente-00c-abort no Codex para encerrar a execução de projeto pela pipeline CSTK compartilhada.
---

# Abortar projeto no Codex

Leia ../feature-00c/references/lifecycle.md, seção Aborto.
Use kind=project e execution.canonical_project do estado existente como
short_name. Se a conexão MCP possuir a onda autorizada, aborte diretamente
com cstk_abort. Caso contrário selecione o projeto absoluto da sessão,
confira cstk_status e execute cstk_abort com o motivo recebido.

purge_backups somente quando explicitamente solicitado. Confira status,
relatório .claude/agente-00c-report.md e commit_status. Preserve documentos,
código, histórico e commits existentes. Respeite o lock de outro dono vivo
e a proveniência da execução. Aborto não representa conclusão da pipeline.

## Gotchas

- Use a identidade e o kind do estado existente; não faça bootstrap para abortar.
- Dono vivo ou desconhecido nunca é roubado; recuperação exige PID registrado comprovadamente morto.
- Origem Claude/desconhecida exige handoff autorizado com proveniência preservada.
- Purge de backups requer pedido explícito; artefatos e histórico são preservados.
- Aborto não significa conclusão; execução concluída não é reclassificada.
