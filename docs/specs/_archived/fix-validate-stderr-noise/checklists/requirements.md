# Requirements Checklist: fix-validate-stderr-noise

**Purpose**: validar qualidade dos requisitos antes de decompor em tarefas.
Feature cirurgica (2 linhas de fix + 1 scenario), checklist proporcionalmente
compacto.
**Created**: 2026-04-20
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [ ] CHK001 - A spec lista as ocorrencias exatas do padrao defeituoso em `validate.sh`, ou apenas pede "todas" sem quantificar? [Completude, Spec §FR-001]
- [x] CHK002 - O criterio de "stderr limpo" define a lista exata de strings proibidas (ex: "integer expression expected", "`[: `")? [Clareza, Spec §FR-003]
- [x] CHK003 - Existe requisito cobrindo o que acontece se os numeros de ERRO/AVISO no stdout MUDAREM apos o fix (hipotese: a aritmetica quebrada podia estar silenciando contagens reais)? [Gap, Spec §Edge Cases, §FR-006]

## Clareza e Mensurabilidade

- [x] CHK004 - "Mesmas fixtures de docs-site" (FR-003) esta enumerado (4 fixtures) ou deixado implicito? [Clareza, Spec §FR-003]
- [x] CHK005 - Pode SC-002 ser objetivamente verificado num passo unico (ex: loop sobre fixtures + grep)? [Mensurabilidade, Spec §SC-002]
- [x] CHK006 - SC-003 usa grep -cE no source para provar ausencia do padrao — essa metrica e suficiente, ou precisa complemento (ex: shellcheck)? [Clareza, Spec §SC-003]
- [x] CHK007 - "Mensagem clara apontando o sintoma exato" (US2 AS2) e quantificavel sem subjetividade? [Ambiguity, Spec §US2]

## Consistencia

- [x] CHK008 - FR-007 (preservar contrato externo) e SC-002 (stderr limpo) sao compativeis — o fix nao altera exit code/stdout, apenas stderr? [Consistency, Spec §FR-007, §SC-002]
- [x] CHK009 - O quickstart (Scenario 4) e a spec (FR-007) concordam que "broken-mermaid" deve continuar reportando 2 ERROs apos o fix? [Consistency, Spec §FR-007; Quickstart §Scenario 4]
- [ ] CHK010 - Edge case §3 (numeros ja observados podem mudar) conflita ou complementa FR-007? A leitura atual e ambigua. [Conflict, Spec §Edge Cases, §FR-006, §FR-007]

## Cobertura de Cenarios

- [ ] CHK011 - A regressao exigida por FR-004 especifica o fixture e o sinal esperados (ex: `valid/` + grep em stderr) ou deixa aberto? [Clareza, Spec §FR-004]
- [ ] CHK012 - Ha cobertura para o caso em que o fix e aplicado em UMA linha mas nao na outra (estado parcialmente corrigido)? [Gap, Spec §Edge Cases]
- [ ] CHK013 - Ha cobertura para o caso em que validate.sh e invocado em um unico arquivo `.md` (nao um diretorio), caminho documentado no script header? [Gap]

## Requisitos Nao-Funcionais

- [x] CHK014 - SC-005 herda o budget de <30s da spec shell-scripts-tests (SC-003 daquela); essa herança esta explicita ou implicita? [Clareza, Spec §SC-005]
- [ ] CHK015 - Nao ha requisito de compatibilidade retroativa (ex: versoes antigas do `validate.sh` instaladas em `~/.claude/` apos `cp`)? Deveria haver? [Gap]

## Premissas e Dependencias

- [x] CHK016 - Esta explicita a premissa de que o fix validado em `ead1b68` (metrics.sh) funciona tambem em `validate.sh` — mesma semantica de `grep -c`? [Assumption, Spec §Contexto]
- [ ] CHK017 - Esta documentado que o `${VAR:-0}` da linha 246-247 de `validate.sh` e redundante apos o fix (ou deve ser removido)? [Gap]

## Ambiguidades e Gaps Residuais

- [ ] CHK018 - Edge case §2 ("fix aplicado incompletamente") merece ser FR explicito ou basta a verificacao via SC-003 (grep no source)? [Ambiguity, Spec §Edge Cases, §SC-003]
- [x] CHK019 - "auditoria EXAUSTIVA" (Edge Cases §2) e quantificada por algum criterio alem do SC-003, ou depende de confianca no executor? [Ambiguity, Spec §Edge Cases]

## Notes

- Marque items com `[x]` quando validados.
- Items `[Gap]` e `[Ambiguity]` sao candidatos a `/clarify` se criticos.
- Feature e pequena — se 15+ items passam facilmente, pode ir direto para `/create-tasks` sem ciclo de clarificacao.

## Revisao — 2026-04-20

### Passam sem ressalva (11/19)

| ID | Evidencia na spec |
|----|-------------------|
| CHK002 | FR-003 enumera "integer expression expected" e "[:" como strings proibidas |
| CHK003 | FR-006 trata explicitamente "se numeros observaveis mudarem" |
| CHK004 | FR-003 lista os 4 fixtures pelo nome |
| CHK005 | SC-002 + Quickstart §5 fornecem loop operacional verificavel |
| CHK006 | SC-003 e direto: `grep -cE ... retorna 0`; shellcheck nao e requisito |
| CHK007 | SC-004 concretiza a "mensagem clara" via scenario reproduzivel |
| CHK008 | FR-007 (stdout/exit/severidades) e SC-002 (stderr) trabalham em camadas ortogonais |
| CHK009 | Quickstart §Scenario 4 diz "identico ao pre-fix", alinhado com FR-007 |
| CHK014 | SC-005 cita explicitamente "SC-003 daquela spec" (shell-scripts-tests) |
| CHK016 | Contexto cita "mesmo padrao defeituoso... em metrics.sh" + research.md Decision 1 formaliza |
| CHK019 | SC-003 (`grep -cE retorna 0`) quantifica "exaustivo" operacionalmente |

### Criticos — resolver antes de `/create-tasks` (1)

- **CHK001** — **bug descoberto na propria spec**: o `§Contexto` diz "linhas ~273-284" mas o audit durante `/plan` mostrou que as ocorrencias reais estao em **linhas 244-245**. O "273-284" corresponde as linhas que DISPARAM o erro (as comparacoes `[ "$VAR" -gt 0 ]`), nao as que contem o padrao defeituoso. Consertar a spec antes de executar para nao confundir o implementador.

### Medios — podem virar tarefas dedicadas se desejado (3)

- **CHK010** — Edge Case §3 vs FR-007 tem interpretacoes duas: "formato preservado, valores podem mudar" vs "tudo inalterado". Resolver via nota na spec: `FR-007 preserva estrutura (colunas, tipos de mensagem), nao garante que os VALORES numericos permanecam — mudancas sao esperadas e absorvidas por FR-006`.
- **CHK011** — FR-004 nao especifica qual fixture usar para o scenario de regressao. `research.md` Decision 2 resolve (escolhe `valid/`). Aceitavel delegar ao plan ou elevar a FR — preferencia de estilo.
- **CHK018** — Edge Case §2 ("fix aplicado incompletamente") coberto de fato por SC-003 (grep=0 no source). Pode virar FR-008 explicito se quiser redundancia defensiva; nao imprescindivel.

### Baixos — aceitaveis como gaps conhecidos (4)

- **CHK012** — Cobertura para fix parcial: SC-003 resolve via grep no source. OK.
- **CHK013** — Invocacao em arquivo unico `.md`: nao e o caso motivador; pode virar Edge Case futuro.
- **CHK015** — Compatibilidade com versoes instaladas: fora do escopo deste fix; ja tratado em CLAUDE.md §"Installed vs Source Drift".
- **CHK017** — `${VAR:-0}` redundante (linhas 246-247 apos fix): decisao de limpeza, nao de correcao. Pode ficar ou sair sem impacto funcional.

### Recomendacao

1. **Corrigir o erro de numeracao em `spec.md`** (§Contexto). Edicao de 5 segundos. Sem isso, o `execute-task` procura bug no lugar errado.
2. **Adicionar nota clarificatoria em FR-007** resolvendo CHK010 — uma linha tipo "valores numericos podem mudar; o que se preserva e a estrutura e o contrato de severidade".
3. Demais items sao aceitaveis como ficam. Pode ir para `/create-tasks`.

Rastreabilidade final: 17/19 items com `[Spec §X]`, `[Gap]`, `[Ambiguity]`, `[Conflict]` ou `[Assumption]` → ~90%.
