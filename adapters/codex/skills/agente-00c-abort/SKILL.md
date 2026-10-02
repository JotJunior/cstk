---
name: agente-00c-abort
description: Abortar a execução de projeto agente-00c no Codex com encerramento da onda, estado terminal atômico, preservação de artefatos e relatório auditável. Use para agente-00c-abort e aborto da pipeline do projeto.
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
