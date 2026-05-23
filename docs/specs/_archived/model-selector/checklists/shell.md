# Shell Checklist: model-selector

**Purpose**: Quality gate para os REQUISITOS relacionados a portabilidade
POSIX sh, dependencias de runtime, comportamento determinista de scripts
e metas de performance. Items validam se a *spec* + *plan* exprimem com
clareza suficiente o que conta como conformidade POSIX, NAO se o codigo
implementado passa em shellcheck.
**Created**: 2026-05-21
**Feature**: [`../spec.md`](../spec.md) | [`../plan.md`](../plan.md)
**Dominio**: shell (POSIX sh + deps + performance)
**Soft cap**: 25 items

---

## Portabilidade POSIX (lingua + shebang + opcoes do shell)

- [ ] CHK001 - Sao os requisitos de "POSIX sh puro" definidos com criterio verificavel (ex: shellcheck `-s sh` zero warnings) e nao apenas como adjetivo? [Clareza, Spec §FR-010, Plan §Technical Context]
- [ ] CHK002 - O spec lista explicitamente quais constructos sao considerados "bash-isms" vetados (arrays, `[[ ]]`, `${var,,}`, `<( )` process substitution, `local`, `function` keyword)? [Gap, Spec §FR-010]
- [ ] CHK003 - Sao os requisitos de shebang uniformes em todos os scripts da skill (`#!/bin/sh` para `classify.sh` e `report.sh`) e nao apenas mencionados no plan? [Consistencia, Plan §Technical Context]
- [ ] CHK004 - O requisito de `set -eu` (ou equivalente fail-fast) esta declarado no spec ou e apenas convencao implicita do toolkit? [Gap, Spec §FR-010]
- [ ] CHK005 - Sao os requisitos de portabilidade declarados para AMBAS as plataformas alvo (macOS BSD coreutils + Linux GNU coreutils) ou apenas mencionados no Technical Context? [Cobertura, Plan §Technical Context]

## Dependencias e ferramentas externas

- [ ] CHK006 - A lista de deps obrigatorias (`find`, `grep`, `awk`, `sed`, `tr`, `cut`, `sort`, `printf`, `cat`, `date`, `mkdir`) esta declarada no spec ou apenas no plan? [Gap, Spec §FR-010, Plan §Technical Context]
- [ ] CHK007 - E o requisito "deps POSIX canonicas" mensuravel (ex: cada chamada externa rastreavel a uma flag listada no POSIX.1-2017) e nao apenas uma afirmacao geral? [Mensurabilidade, Spec §FR-010]
- [ ] CHK008 - Sao os requisitos de uso opcional de `jq` consistentes entre spec (FR-010a), plan (Technical Context "Deps opcionais") e research (Decision 5)? [Consistencia, Spec §FR-010a, Plan §Conformidade detalhada]
- [ ] CHK009 - O requisito de confinamento de `jq` em UM unico arquivo (`scripts/report.sh`) define verificacao operacional (ex: `grep -rn '\bjq\b'` retornar 1 arquivo) ou apenas a regra textual? [Clareza, Spec §FR-010a (b)]
- [ ] CHK010 - Esta o veto a `ripgrep`/`fd`/`bats` declarado explicitamente como requisito (nao apenas mencionado na constitution)? Spec referencia, mas falta criterio "como detectar tentativa de uso". [Gap, Spec §FR-010a]
- [ ] CHK011 - Sao os requisitos de versao minima de `jq` (`>=1.6` no plan) justificados (qual feature do 1.6 e usada?) ou e numero arbitrario? [Ambiguity, Plan §Technical Context]

## Fallback graceful do carve-out 1.1.0

- [ ] CHK012 - O requisito "fallback awk linha-a-linha produz MESMO output da tabela markdown" define EXATAMENTE quais campos devem ser identicos (whitespace, ordering de linhas, casas decimais, separadores)? [Clareza, Spec §FR-010a (a), Plan §Conformidade detalhada]
- [ ] CHK013 - Sao os requisitos de teste do fallback `awk` (`test_report_without_jq.sh`) especificos sobre o mecanismo de bloqueio do `jq` (mascarar via `PATH` minimizado, `command -v` stub, ou outro)? [Ambiguity, Plan §Conformidade detalhada]
- [ ] CHK014 - Pode o requisito "fallback graceful" ser objetivamente medido (ex: ambos os caminhos produzem byte-identical output OR diff <= N linhas) ou e apenas afirmacao qualitativa? [Mensurabilidade, Spec §FR-010a]

## Performance e responsividade

- [ ] CHK015 - Sao os requisitos de performance da classificacao explicitos no spec (Plan menciona "<50ms p95" como SC implicito)? Caso nao, classificar como gap. [Gap, Plan §Technical Context]
- [ ] CHK016 - O SC-003 ("relatorio <500ms para 20 state.json") define hardware base (CPU/disco) ou e medido em qualquer ambiente? [Ambiguity, Spec §SC-003]
- [ ] CHK017 - Sao os requisitos de medicao do SC-003 reproduziveis (qual comando exato? quantas runs? mediana ou pior caso?) ou apenas "verificavel via `time` no shell"? [Clareza, Spec §SC-003]
- [ ] CHK018 - O requisito de fixture `tests/fixtures/state-dirs-20/` define o tamanho/conteudo minimo de cada state.json mockado (afeta o tempo medido) ou e arbitrario? [Gap, Plan §Project Structure]

## Determinismo e fail-safe dos scripts

- [ ] CHK019 - Sao os requisitos de tratamento de input vazio/curto (`<3 tokens` → manter-atual score 0) consistentes entre spec (Edge Cases) e plan (Decision 7)? [Consistencia, Spec §Edge Cases, Plan §Summary]
- [ ] CHK020 - O requisito "input rejeita null-byte" (Plan §Security) tem criterio de mensuracao (exit code? stderr message? silencioso?) ou apenas mencao? [Ambiguity, Plan §Technical Context]
- [ ] CHK021 - Sao os requisitos de exit codes documentados (sucesso vs ambiguo vs erro de input vs erro de catalogo ausente) declarados no spec ou diferidos para `contracts/skill-io.md`? [Cobertura, Plan §Observability]
- [ ] CHK022 - O requisito "sem `eval`; sem `find` sobre paths derivados do input" (Plan §Security) e auditavel via grep estatico ou e apenas regra de revisao humana? [Clareza, Plan §Technical Context]

## Cobertura de testes shell

- [ ] CHK023 - Sao os 10 testes shell listados em `tests/cstk/test_model_selector_*.sh` rastreaveis 1:1 aos SCs/FRs (cada teste cita o SC/FR que valida)? [Cobertura, Plan §Project Structure, Spec §SC-001..SC-006]
- [ ] CHK024 - O requisito "suite shell-scripts-tests" (FR-017) define o framework/runner concretamente (`tests/run.sh`?) ou e nome abstrato em construcao? [Ambiguity, Spec §FR-017, Plan §Test]
- [ ] CHK025 - Sao os requisitos de cobertura minima (3 faixas + ambiguo + contraditorios + input vazio) listados como teste discreto ou agregados (perdendo rastreabilidade)? [Cobertura, Spec §FR-017]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente — proximos checklists (skill, security) continuam em CHK026+
- Rastreabilidade: 25/25 items com referencia explicita ([Spec §...] ou [Plan §...] ou [Gap]/[Ambiguity]/[Consistencia]/[Cobertura]) = 100%
- Dimensoes cobertas: Clareza (5), Gap (4), Consistencia (3), Mensurabilidade (3), Cobertura (4), Ambiguity (6)
