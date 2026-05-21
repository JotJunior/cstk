# Skill-Anatomy Checklist: model-selector

**Purpose**: Quality gate para os REQUISITOS de conformidade com o
formato canonico de skill do toolkit — progressive disclosure
(`SKILL.md` enxuto + `references/` + `scripts/` + `examples/`),
secao Gotchas obrigatoria, `description` como trigger condition.
Items validam se a *spec* + *plan* exprimem com clareza suficiente
o que conta como "skill canonica", NAO se a skill implementada bate
nos limites.
**Created**: 2026-05-21
**Feature**: [`../spec.md`](../spec.md) | [`../plan.md`](../plan.md)
**Dominio**: skill (anatomia canonica + progressive disclosure)
**Soft cap**: 20 items
**Numeracao**: continua de CHK025 → CHK026..

---

## Limites de tamanho de SKILL.md (progressive disclosure)

- [ ] CHK026 - O requisito "SKILL.md <200 linhas" (SC-004) define EXATAMENTE o que conta como linha (linhas em branco? frontmatter YAML? code fences? comentarios?) ou e numero abstrato? [Ambiguity, Spec §SC-004]
- [ ] CHK027 - Sao os requisitos de exclusao "sem contar templates/exemplos/references" (SC-004) consistentes com a Project Structure do plan (que coloca esses em diretorios `references/`/`examples/`)? [Consistencia, Spec §SC-004, Plan §Project Structure]
- [ ] CHK028 - Pode "<200 linhas" ser objetivamente medido (`wc -l SKILL.md`) E o teste correspondente `test_model_selector_skill_lines.sh` define o threshold de falha (exatamente 200? >=200? 199?)? [Mensurabilidade, Spec §SC-004, Plan §Project Structure]

## Frontmatter description-as-trigger

- [ ] CHK029 - O requisito FR-014 ("description MUST ser trigger condition no formato 'Use quando X / NAO use quando Y'") define quantos triggers minimos e quantos anti-triggers minimos sao exigidos? [Gap, Spec §FR-014]
- [ ] CHK030 - Sao os requisitos de description-trigger verificaveis automaticamente (ex: regex `Use quando.*NAO use`) ou exigem revisao humana subjetiva? [Mensurabilidade, Spec §FR-014]
- [ ] CHK031 - O formato esperado do frontmatter YAML da skill (campos obrigatorios: `description`, `allowed-tools`, etc) esta declarado no spec, no plan, ou diferido para "convencao do toolkit" sem referencia explicita? [Gap, Spec §FR-014, Plan §Project Structure]

## Secao Gotchas obrigatoria (FR-013)

- [ ] CHK032 - Sao os 5 Gotchas listados em FR-013 (a-e) cada um redigido como REQUISITO (o que o gotcha deve cobrir) ou como TEXTO FINAL (a redacao exata)? Ambiguidade afeta o que /checklist consegue validar. [Ambiguity, Spec §FR-013]
- [ ] CHK033 - Pode o requisito "Gotchas obrigatorios cobrindo a-e" ser verificado automaticamente (ex: 5 sub-headings em `## Gotchas` da SKILL.md) ou e checagem manual? [Mensurabilidade, Spec §FR-013]
- [ ] CHK034 - Sao os Gotchas em FR-013 mutuamente exclusivos e coletivamente exaustivos (ex: gotcha "score 3 exige evidencia" duplica FR-002b)? [Consistencia, Spec §FR-013, Spec §FR-002]
- [ ] CHK035 - O requisito de Gotchas tem criterio de "qualidade minima" (cada gotcha cita um sintoma OBSERVAVEL + acao corretiva) ou aceita texto vago? [Clareza, Spec §FR-013]

## Estrutura de diretorios (references/scripts/examples)

- [ ] CHK036 - Sao os requisitos de existencia de `references/sinais.md` declarados no spec (FR-004) E o requisito de existencia de `scripts/classify.sh` + `scripts/report.sh` declarados explicitamente (apenas no plan §Project Structure)? [Gap, Spec §FR-004, Plan §Project Structure]
- [ ] CHK037 - O requisito de `examples/` esta marcado como obrigatorio ou opcional MVP no spec? Plan diz "NOVO (opcional MVP)" — spec nao referencia. [Consistencia, Plan §Project Structure]
- [ ] CHK038 - Sao os 3 exemplos do plan (`good-haiku.md`, `good-sonnet.md`, `good-opus.md`) suficientes ou ha gap de "bad examples" (anti-padroes) recomendados por outras skills do repo? [Cobertura, Plan §Project Structure]

## Catalogo de sinais (FR-004)

- [ ] CHK039 - O requisito "15 sinais minimos MVP — 5 por faixa" (FR-004 / dec-004) define o que conta como sinal valido (verbo unico vs. expressao multi-palavra vs. ferramenta)? [Ambiguity, Spec §FR-004]
- [ ] CHK040 - Sao os requisitos do formato da tabela markdown de `references/sinais.md` (3 colunas: termo, faixa, peso) consistentes entre spec (FR-004) e research (Decision 1)? [Consistencia, Spec §FR-004, Plan §Summary]
- [ ] CHK041 - O requisito "operadores extendem localmente sem patch" (FR-004) define mecanismo (edicao direta vs. arquivo overlay vs. variavel de ambiente) ou e afirmacao generica? [Ambiguity, Spec §FR-004]
- [ ] CHK042 - Sao os requisitos de validacao do catalogo (peso default = 1, linhas malformadas ignoradas, encoding UTF-8) declarados ou diferidos para `contracts/skill-io.md`? [Gap, Spec §FR-004]

## Outputs e contratos

- [ ] CHK043 - Sao os 4 atributos do SugestaoDeModelo (FR-002 a-d: modelo + score + justificativa + alternativa) consistentes entre spec (Key Entities), plan (Summary "4 secoes fixas") e research (Decision 4)? [Consistencia, Spec §FR-002, Spec §Key Entities]
- [ ] CHK044 - O requisito "rotulo abstrato, NUNCA versao concreta" (FR-002a / dec-005) tem criterio de verificacao (grep de strings tipo `claude-*-4-*` na skill)? [Mensurabilidade, Spec §FR-002]
- [ ] CHK045 - Sao os requisitos de score (escala 0..3, teto pratico 2 para auto-invocacao, score 3 reservado para evidencia historica) explicitos no SKILL.md como Gotcha (FR-013d) ou apenas no spec? [Consistencia, Spec §FR-002, Spec §FR-013]

## Notes

- Marcar items concluidos com `[x]`
- Numeracao continua de shell.md (terminou em CHK025) — proximo dominio (security) inicia em CHK046
- Rastreabilidade: 20/20 items com referencia explicita = 100%
- Dimensoes cobertas: Ambiguity (5), Consistencia (5), Mensurabilidade (4), Gap (3), Cobertura (1), Clareza (2)
