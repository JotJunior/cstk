# UX Checklist: cstk-jira

**Purpose**: validar a qualidade dos requisitos do fluxo de instalacao e
configuracao guiada (US4, FR-007/008/009, SC-004) e da experiencia de
sincronizacao/board (US2/US3) antes de `create-tasks`.
**Created**: 2026-09-24
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [quickstart.md](../quickstart.md)

## Instalacao e Setup Guiado

- [x] CHK001 - E' o fluxo de instalacao pelo marketplace (Quickstart Cenario 1) identico ao padrao ja usado pelos demais plugins (`cstk`, `cstk-language-go`), sem passo extra ou diferente que quebre a expectativa do usuario? [Consistencia, Quickstart Cenario 1 + "padrao de README.md L339-342"] {auto}
- [x] CHK002 - Esta definida a ORDEM exata de perguntas que o setup guiado faz ao operador (site -> PROJECT_KEY -> credencial em terminal proprio -> mapeamento de status -> confirmacao de tipo de issue -> filtro/board), de forma que o usuario nunca precise voltar/repetir um passo ja respondido? [Clareza, Quickstart Cenario 3 passos 1-5 (apos edicao desta onda)] {auto}
- [x] CHK003 - E' explicito, para o passo de credencial, que o operador NUNCA deve digitar o token no chat — e a skill orienta um comando concreto num terminal separado, em vez de so avisar "cuidado"? [Clareza/Seguranca, Quickstart Cenario 3 passo 2: "Em um terminal PROPRIO (nunca no chat...)"] {auto}
- [ ] CHK004 - Quando o mapeamento `fail == pass` e rejeitado (Error case 3a), o diagnostico pede um status ESPECIFICO e distinto, ou so informa "invalido" sem orientar a correcao concreta (qual status escolher)? [Qualidade de mensagem, Quickstart Error case 3a: "setup recusa com diagnostico pedindo um status distinto no workflow"] {auto} — Parcialmente satisfeito: o texto ja diz "pedindo um status distinto", mas nao especifica se o diagnostico lista os status DISPONIVEIS do workflow (descobertos no mesmo fluxo) para o operador escolher, ou so recusa genericamente. `[Gap]` pequeno -> `/create-tasks` MUST detalhar que o diagnostico de erro reutiliza a lista de status ja descoberta via `listJiraIssueTransitions`/R5.
- [ ] CHK005 - Quando o token e invalido (Error case 3b), fica claro para o usuario o PROXIMO PASSO concreto (onde gerar novo token, como reconfigurar), ou so "token invalido" sem acao sugerida? [Qualidade de mensagem, Quickstart Error case 3b: "diagnostico de credencial rejeitada; nenhum config parcial marcado como valido"] {humano} — o texto atual garante SO a nao-corrupcao de estado (config parcial), nao a qualidade acionavel da mensagem de erro em si; especificar o texto exato do diagnostico e uma decisao de copy/produto, nao uma correcao mecanica.
- [x] CHK006 - E' garantido que, apos o setup falhar parcialmente (config incompleta), NENHUM estado parcial fica marcado como valido — evitando que o usuario acredite que a integracao esta ativa quando nao esta? [Consistencia, FR-007 "MUST falhar com diagnostico claro... em vez de pular a sincronizacao silenciosamente" + Quickstart Error case 3b] {auto}

## Transparencia de Inatividade

- [x] CHK007 - E' o comportamento de "plugin instalado e inativo" (Quickstart Cenario 2) 100% transparente ao usuario — sem NENHUMA mensagem nova, arquivo criado ou mudanca de comportamento perceptivel nas demais funcionalidades do toolkit? [Mensurabilidade, FR-017/SC-006 + Quickstart Cenario 2 "Expected: hooks saem em no-op... nenhum arquivo... nenhuma rede... nenhuma mensagem nova"] {auto}

## Board e Terminologia (US2, US3)

- [x] CHK008 - O board (US2) usa terminologia de coluna que corresponde ao estagio do pipeline SDD local (specify/plan/execute-task/etc) — essa correspondencia e definida pelo mapeamento `pending/in_progress/pass/fail` que o operador configura no setup, evitando ambiguidade sobre "o que cada coluna significa"? [Clareza, Spec US2 + Quickstart Cenario 3 "pede o mapeamento pending/in_progress/pass/fail"] {auto}
- [x] CHK009 - E' consistente a nomenclatura das 3 skills (`jira-setup`, `jira-convert`, `jira-sync`) com o padrao de nomenclatura de skills ja usado no toolkit (kebab-case, verbo/substantivo-objeto)? [Consistencia, Plan.md Project Structure] {auto}
- [x] CHK010 - Existe criterio de aceite que confirma que o usuario completa TODO o setup NUMA UNICA sessao guiada (SC-004), sem precisar sair para editar arquivo manualmente — testavel objetivamente pelo Cenario 3 sem passos ocultos fora do fluxo? [Mensurabilidade, SC-004 + Quickstart Cenario 3 (5 passos apos edicao desta onda, todos dentro da skill)] {auto}

## Resolucao de Divergencias pelo Operador

- [x] CHK011 - Ao detectar conflito (card editado manualmente no Jira), existe um comando/skill claro que o operador usa para VER e RESOLVER o conflito (`jira-sync status`/`resolve`), documentado no fluxo de UX e nao so no data-model interno? [Completude, Quickstart Error case 5a "jira-sync status lista o conflito" + data-model.md ConflictRecord] {auto}
- [x] CHK012 - O card orfao (task local removida/renumerada) tem um caminho de UX claro para o operador decidir o destino (religar/manter) — `jira-sync relink` esta descoberto pela skill correspondente, nao so citado no state-diagram interno? [Completude, data-model.md SyncMapping "orphan --> active: operador religa (jira-sync relink)" + Quickstart Error case 5d] {auto}

## Feedback de Progresso (nao especificado)

- [ ] CHK013 - Existe algum ponto de interacao (setup, convert, sync) em que o usuario recebe feedback de PROGRESSO durante uma operacao potencialmente demorada (criar dezenas de issues numa `jira-convert` de feature grande), ou a spec/plan sao silenciosos sobre isso? [Gap, nenhum artefato menciona feedback de progresso durante criacao em lote] {humano} — o Success Criteria (SC-001/SC-005) so mede o resultado final, nao a experiencia durante a espera; decidir se vale a pena exigir feedback incremental (ex.: contagem "N/M issues criadas") e trade-off de escopo/produto para uma feature P1 que ja tem MVP fechado (D1: sem bulk create, criacao item a item) — nao e uma lacuna que o agente deva fechar sozinho.

## Notes

- Items `{auto}` resolvidos pelo agente (`[x]` com citacao) ou marcados `[Gap]` com destino explicito.
- CHK004 (`[Gap]` pequeno) -> `/create-tasks`: detalhar que o diagnostico de status invalido no setup reaproveita a lista de status ja descoberta.
- CHK005 e CHK013 (`{humano}`) -> decisao do dono do produto: qualidade de copy do diagnostico de token invalido, e se feedback de progresso incremental e exigido nesta versao ou fica para uma iteracao futura.
- 10 items resolvidos `{auto}`, 1 `[Gap]` pequeno com destino a `/create-tasks`, 2 `{humano}` aguardando decisao do dono do produto (13 items totais).
