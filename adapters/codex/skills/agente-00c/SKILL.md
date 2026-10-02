---
name: agente-00c
description: Conduzir um projeto pela pipeline CSTK desde briefing até review-features com decisões justificadas, estado retomável e execução supervisionada na sessão Codex atual.
---

# Pipeline de projeto no Codex

Leia primeiro `../feature-00c/SKILL.md` para os contratos de segurança,
decisões, evidências, lock, conhecimento e recuperação. Reutilize os scripts
de `../feature-00c/scripts/`; não crie um segundo modelo nem scheduler.
Para continuar ou abortar estado existente, use agente-00c-resume ou
agente-00c-abort e leia ../feature-00c/references/lifecycle.md.

Use `--kind project` em context.py, session.py, phase.py e controller.py.
`--short-name` é a identidade canônica kebab-case do projeto e deve coincidir
com `--canonical-project` no bootstrap. O estado fica em
`.claude/agente-00c-state`; os artefatos de desenvolvimento ficam em
`docs/specs/<canonical-project>/`. Não renomeie diretórios existentes sem
reconciliação explícita.

Um projeto novo não precisa de briefing nem constitution prévios. O bootstrap
começa em briefing. Antes da primeira onda, obtenha respostas reais do operador
para `atomic_commit`, `roadmap_mode` e `delivery_tier` e registre cada resposta
com `optins.collect(..., field=...)`. Ausência de resposta não autoriza assumir
valores. Os helpers canônicos persistem essas escolhas; o gate I-2 exige as
três respostas. Para delivery_tier use local, internal-network, cloud-internal
ou cloud-public. Uma escolha explícita inicial permite ajustar o valor restritivo
inicial; alterações posteriores exigem reconciliação.

A pipeline padrão contém briefing, constitution, specify, clarify, plan,
checklist, create-tasks, execute-task, converge, review-task e review-features.
Com roadmap_mode explicitamente true, use briefing, constitution e roadmap.
Leia a skill e a referência retornadas pelo descritor antes de executar cada
fase. Roadmap não tem skill dedicada: leia a referência root e use
roadmap-write.sh para persistir entradas e auditar seu resultado. Na constitution, o controlador aplica o pre-flight canônico e bloqueia
conflitos até resposta humana autorizadora. Não responda em nome do operador.

Ao concluir briefing e constitution, o controlador registra hashes dos
artefatos de governança. Mudanças posteriores exigem reconciliação. Cada
conclusão exige arquivos reais, justificativa e os gates compartilhados.
O relatório de projeto é `.claude/agente-00c-report.md`.

O plugin registra o servidor `cstk_pipeline`. Selecione a raiz absoluta da
sessão com `cstk_select_execution`, `kind=project` e `short_name` igual à
identidade canônica; informe knowledge_db absoluto quando configurado.
As demais chamadas seguem a entrada feature-00c, com os três opt-ins reais.
O transporte stdio e o lock entre chamadas foram validados pelo app-server;
isso não certifica cobertura de hooks em um turno de modelo. Mantenha
`autonomous_ready=false` até a validação real dessas condições.
