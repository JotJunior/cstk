---
name: feature-00c-resume
description: Retomar uma feature CSTK existente no Codex e continuar sua pipeline, responder bloqueios humanos ou recuperar uma interrupção. Use para feature-00c-resume; preserva identidade, opt-ins e auditoria.
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
