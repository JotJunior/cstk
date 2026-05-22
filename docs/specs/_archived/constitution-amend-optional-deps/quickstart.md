# Quickstart: Constitution Amendment 1.1.0 — Verification

Cenarios que validam a implementacao do amendment. Um por SC critico.

## Scenario 1: Aplicacao do amendment (happy path, SC-004, SC-005, SC-006)

**Pre-condicoes**: `docs/constitution.md` em 1.0.0 ratificado em 2026-04-20.

1. Snapshot do bloco MUST do Principio II (linhas entre `**MUST:**` e a proxima
   linha em branco) — guardar em tempfile para comparacao posterior.
2. Aplicar Insertion Points 1-4 conforme `contracts/amendment-text.md`.
3. Extrair novo bloco MUST do Principio II (mesmas linhas) e comparar com snapshot:
   `diff snapshot novo-bloco` deve retornar vazio.
4. Contar ocorrencias do marcador `(a)` `(b)` `(c)` na subsecao nova:
   exatamente 3.
5. Verificar Version footer: `grep 'Version.*1.1.0' docs/constitution.md` retorna
   a linha esperada; `grep 'Last Amended.*2026-04-24'` tambem retorna.
6. **Expected**:
   - Bloco MUST original preservado byte-a-byte (SC-005 ✓)
   - Exatamente 3 condicoes cumulativas (SC-006 ✓)
   - Version footer == `**Version**: 1.1.0 | **Ratified**: 2026-04-20 | **Last Amended**: 2026-04-24` (SC-004 ✓)

## Scenario 2: Re-analise de cstk-cli pos-amendment (SC-002)

**Pre-condicoes**: Scenario 1 concluido. `docs/specs/cstk-cli/plan.md` tem
§Complexity Tracking ainda em forma antiga ("Violacao: Principio II...").

1. Aplicar Edit A do contract (reescrita de §Complexity Tracking do cstk-cli).
2. Rodar `/analyze` em `docs/specs/cstk-cli/` (ou simular manualmente passando os
   artefatos).
3. Inspecionar findings reportados.
4. **Expected**:
   - Finding D1 (jq exception) NAO aparece mais como CRITICAL
   - Constitution Alignment mostra Principio II = PASS (nao mais FAIL)
   - Demais findings (E1/C1 resolvidos, E2/B2/F1 deferidos) permanecem com suas
     severidades anteriores

## Scenario 3: Verificacao de nao-regressao em outros principios (SC-003)

**Pre-condicoes**: Scenario 1 concluido.

1. Para cada feature ativa (hoje: `docs/specs/cstk-cli/`,
   `docs/specs/shell-scripts-tests/`, `docs/specs/fix-validate-stderr-noise/`,
   `docs/specs/constitution-amend-optional-deps/` — esta propria), rodar
   `/analyze` mental.
2. Comparar Constitution Alignment de cada uma antes vs depois do amendment.
3. **Expected**:
   - Nenhum principio MUST que estava PASS em 1.0.0 passa a FAIL em 1.1.0
   - Specs que nao invocam o carve-out nao tem mudanca alguma de conformidade
   - Apenas cstk-cli tem mudanca positiva (D1: CRITICAL → PASS)

## Scenario 4: Novo contribuidor avalia dep opcional hipotetica (SC-001)

**Pre-condicoes**: Amendment 1.1.0 aplicado. Contribuidor novo, sem contexto
previo das decisoes, le `docs/constitution.md` pela primeira vez.

1. Contribuidor tem proposta hipotetica: "quero usar `yq` opcionalmente em uma
   skill para parsear YAML, com fallback para `awk` puro".
2. Contribuidor le Principio II, incluindo nova subsecao.
3. Contribuidor avalia sua proposta contra as tres condicoes: (a) o fallback e
   graceful E testavel? (b) `yq` fica em um unico arquivo? (c) esta declarado
   na feature spec?
4. Contribuidor chega a conclusao binaria (passa ou nao passa) em menos de 5
   minutos.
5. **Expected**:
   - Tempo total de leitura + avaliacao < 5 min (SC-001)
   - Resposta inequivoca — contribuidor nao precisa consultar outros documentos
     para decidir
   - Se proposta viola qualquer condicao, contribuidor identifica qual

## Scenario 5: Tentativa de reabilitar ferramenta banida nominalmente (edge case)

**Pre-condicoes**: Amendment 1.1.0 aplicado. Hipotetica nova feature propoe usar
`ripgrep` "opcionalmente" com fallback para `grep`.

1. Contribuidor le Principio II, incluindo nova subsecao.
2. Contribuidor nota afirmacao "Ferramentas ja banidas nominalmente (`ripgrep`,
   `fd`, `bats`) permanecem vetadas inclusive como deps opcionais — este carve-out
   nao as reabilita".
3. Contribuidor entende que o amendment 1.1.0 NAO autoriza a proposta.
4. Para usar `ripgrep`, seria necessario novo amendment (dedicado a remover
   `ripgrep` do banimento nominal).
5. **Expected**:
   - Proposta e rejeitada pelo texto literal do amendment, sem ambiguidade
   - Esta rota alternativa (novo amendment) fica documentada implicitamente

## Scenario 6: Dep previamente opcional vira obrigatoria no futuro (edge case)

**Pre-condicoes**: Hipotetico: versao futura de `cstk-cli` remove o fallback
manual-paste, tornando `jq` obrigatorio.

1. Re-rodar `/analyze` na nova versao do cstk-cli.
2. `/analyze` detecta que condicao (a) da subsecao 1.1.0 nao e mais satisfeita
   (fallback foi removido).
3. Finding reaparece como CRITICAL (violacao de Principio II — agora dep
   obrigatoria, nao opcional).
4. **Expected**:
   - Amendment 1.1.0 nao protege retroativamente — se a feature deixa de
     satisfazer as condicoes, conformidade se perde
   - A feature precisa nova spec que justifique a dep obrigatoria (ou restaurar
     o fallback)
