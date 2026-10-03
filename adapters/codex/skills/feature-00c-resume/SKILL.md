---
name: feature-00c-resume
description: Use quando o usuário solicitar explicitamente feature-00c-resume no Codex para retomar a execução da feature pela pipeline CSTK compartilhada.
---

# Retomar feature no Codex

Leia ../feature-00c/SKILL.md e ../feature-00c/references/lifecycle.md.
Identifique a raiz da sessão e o short-name da feature existente.
Selecione kind=feature no MCP e confira cstk_status e knowledge_db.
Chame cstk_resume; leia os arquivos do descritor e conduza as fases até
conclusão ou bloqueio/pausa concreta, conforme os contratos compartilhados.
Respostas humanas são aplicadas com block_id, answer e response_source reais.
Não reinicialize estado, repita opt-ins resolvidos ou invente respostas.

Para onda órfã, use recuperação explícita antes de retomar. Se a execução
pertencer ao Claude, apresente a origem e faça handoff somente quando
solicitado pelo operador. Drift exige revisão e reconciliação autorizada,
com hashes observados, antes de abrir onda. Leia o resultado terminal antes
de declarar a feature concluída.

## Gotchas

- Use a identidade e o kind do estado existente; não faça bootstrap para retomar.
- Dono vivo ou desconhecido nunca é roubado; recuperação exige PID registrado comprovadamente morto.
- Origem Claude/desconhecida exige handoff autorizado com proveniência preservada.
- Respostas humanas são reais, identificadas e imutáveis; várias pendências exigem block_id.
- Deriva de governança bloqueia retomada até revisão dos dois hashes atuais.
