---
name: agente-00c-resume
description: Use quando o usuário solicitar explicitamente agente-00c-resume no Codex para retomar a execução de projeto pela pipeline CSTK compartilhada.
---

# Retomar projeto no Codex

Leia ../agente-00c/SKILL.md e ../feature-00c/references/lifecycle.md.
Use kind=project e a identidade execution.canonical_project do estado
existente como short_name. Selecione a raiz absoluta da sessão e confirme
knowledge_db. cstk_resume abre a onda persistida quando não houver pendências.
Conduza as etapas pela skill e referência do descritor até conclusão ou
bloqueio concreto. Respeite roadmap_mode e delivery_tier já registrados.

Responda cada bloqueio pelo ID com answer e response_source reais. Aspectos
legados ainda ausentes podem ser inicializados com init_aspects,
technical_aspects e operational_aspects fornecidos pelo operador; não
sobrescreva aspectos existentes. Recuperação, handoff e reconciliação de
governança seguem o contrato de ciclo de vida, sem reinicializar a execução.

## Gotchas

- Use a identidade e o kind do estado existente; não faça bootstrap para retomar.
- Dono vivo ou desconhecido nunca é roubado; recuperação exige PID registrado comprovadamente morto.
- Origem Claude/desconhecida exige handoff autorizado com proveniência preservada.
- Respostas humanas são reais, identificadas e imutáveis; várias pendências exigem block_id.
- Deriva de governança bloqueia retomada até revisão dos dois hashes atuais.
