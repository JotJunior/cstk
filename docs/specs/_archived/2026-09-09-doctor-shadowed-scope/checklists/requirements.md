# Requirements Checklist: Doctor Shadowed Scope

**Purpose**: Validar a qualidade dos requisitos da feature `doctor-shadowed-scope`
antes de `/create-tasks` — com foco nos pontos onde esta feature pode falhar em
silencio: cobertura medida contra o arquivo (nao contra o parser), robustez do
denominador a ausencia de newline final, gating correto do rotulo `[OK]`,
invariante `section_rc == 0` por construcao, preservacao do fluxo de copia local
nao-gerenciada, e verificabilidade do teste adversarial.
**Created**: 2026-08-27
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - O gate deterministico de cobertura FR-vs-cenario roda limpo (0 findings) sobre o spec.md? [Completude, Gate requirement-coverage.sh] {auto}
  Evidencia: `requirement-coverage.sh docs/specs/doctor-shadowed-scope/spec.md` → `RESULT|...|requirements=10|covered=10|errors=0`, exit 0.
- [x] CHK002 - Requisitos nao-funcionais de seguranca (fronteira de confianca do manifesto de projeto) estao cobertos, alem dos funcionais de US1-US3? [Completude, Spec Clarifications + contracts/doctor-shadowed-scope-output.md §7] {auto}
  Evidencia: a spec (Clarifications) cita explicitamente o gate `owasp-security` e o achado HIGH que motivou `block-001`/`dec-020`; o contrato §7 ("Fronteira de confianca — o manifesto de projeto e UNTRUSTED") formaliza R1-R6 como requisito de implementacao, nao apenas nota de plano.
- [x] CHK003 - A declaracao "fora-de-escopo" (retrofit de outros mecanismos de saude) esta documentada explicitamente, e nao apenas implicita? [Completude, Spec §Clarifications Session 2026-08-27] {auto}
  Evidencia: a pergunta/resposta de sessao registra literalmente "sem retrofit imediato de mecanismos ja existentes (ex.: demais secoes do doctor, `guard-hooks-status.sh`) dentro desta feature".

## Clareza de Requisitos

- [x] CHK004 - A cobertura de FR-006/FR-007 e medida contra o que o ARQUIVO contem, e nao contra o que o PARSER reconhece — o criterio de aceite duro da feature esta especificado em artefato citavel, nao apenas implicito no texto do FR? [Clareza, Spec FR-007 + plan.md "Metade 2" + research.md Decision 6] {auto}
  Evidencia: FR-007 e explicito ("independente de quantas o interpretador da ferramenta reconhece... MUST NOT ser medida contra quantos registros o proprio interpretador conseguiu reconhecer"); plan.md nomeia o denominador (`manifest_count_data_lines`, criterio puro de linha, "Nao chama `read_manifest`") e o numerador (contagem por uso, decomposto em campos) como dois caminhos deliberadamente desacoplados — nao ha ambiguidade sobre qual dos dois mede "o arquivo".
- [x] CHK005 - O denominador de cobertura esta especificado como robusto a arquivo SEM newline final, com evidencia empirica registrada (nao apenas alegacao)? [Clareza, research.md Decision 6 "MEDIDO"] {auto}
  Evidencia: research.md documenta medicao literal — `grep -cv` retorna `0` onde `awk` (forma do parser) retorna `1` para `printf 'a\tb\tc\td' > m2.tsv` (sem `\n` final) — e conclui "o denominador MUST ser robusto a ausencia de newline final (forma awk)". A escolha de implementacao (`awk`, nao `grep -c`) esta fixada por esse achado, nao deixada em aberto.
- [x] CHK006 - O rotulo `[OK]` da linha de veredito da secao tem as TRES condicoes de que depende (cobertura integral, zero `shadowed`, zero `nao_comparado`) especificadas de forma exaustiva, com contra-exemplo do defeito que a ausencia de uma delas causaria? [Clareza, contract §3.5 + quickstart Cenario 20] {auto}
  Evidencia: contrato §3.5 lista as tres condicoes textualmente ("`[OK]` MUST NOT ser impresso quando R < F, quando F < 2, quando qualquer fonte estiver em partial/unreadable/inconsistent, quando count_shadowed >= 1, ou quando count_nao_comparado >= 1 — mesmo que zero divergencias tenham sido encontradas") e explica o defeito historico que motivou a 3a condicao (dec-023: `[OK]` podia sair ao lado de `[indeterminate]`/`[unmanaged-upstream]`). Cenario 20 do quickstart e a tabela-verdade executavel das 6 combinacoes.
- [x] CHK007 - `count_nao_comparado` esta especificado como DERIVADO (soma de `count_indeterminate` + `count_unmanaged_upstream`), com a justificativa de por que nao pode ser um contador independente? [Clareza, data-model.md tabela de campos] {auto}
  Evidencia: data-model.md documenta a formula (`= count_indeterminate + count_unmanaged_upstream`) e a nota "Por que `count_nao_comparado` e derivado e nao acumulado a parte" — ambos os estados componentes sao "houve registro mas nao houve comparacao", e nenhum afeta a cobertura por si so.

## Consistencia de Requisitos

- [x] CHK008 - `section_rc` esta especificado como PRODUZIDO POR CONSTRUCAO (a funcao termina em `return 0`) e nao como um valor ACUMULADO a partir das contagens de estado — com o motivo explicito de por que a distincao importa? [Consistencia, data-model.md invariante INV-RC] {auto}
  Evidencia: data-model.md, secao "Invariante estrutural do `section_rc`": "o valor nao deve ser acumulado a partir das contagens. A implementacao MUST produzir 0 por construcao... em vez de calcular um rc a partir de count_shadowed/coverage_state e por acaso sempre dar zero — um acumulador e uma linha de `\|\|` de distancia de voltar a gatear." Isto e requisito de IMPLEMENTACAO, nao so de comportamento observavel — mas esta explicitamente registrado como consequencia direta do requisito de qualidade (INV-RC), nao um detalhe deixado ao acaso.
- [x] CHK009 - A tabela exaustiva de combinacoes secao×section_rc (contrato §4.1) cobre TODAS as combinacoes de estado sem deixar nenhuma implicita, incluindo a execucao sob `--fix`? [Consistencia, contract §4.1] {auto}
  Evidencia: contrato §4.1 lista 11 linhas nomeadas (`shadowed`, `indeterminate`, `unmanaged-upstream`, `shadow-current`, `partial`, `unreadable`, `inconsistent`, `absent`, `F=0`, mistura, `--fix`) e fecha com "Nao ha decima-segunda linha. Nao existe entrada... que faca esta secao retornar valor diferente de `0`" — redacao deliberadamente exaustiva, nao amostral.
- [x] CHK010 - A postura report-only (esta secao nunca gateia) e reconciliada explicitamente com FR-008/FR-009 (que exigem NAO reportar sucesso sobre cobertura parcial), evitando a leitura de que "nao gatear" e "nao reportar sucesso" sejam a mesma obrigacao? [Consistencia, contract §4.3] {auto}
  Evidencia: contrato §4.3 ("Por que isto NAO viola FR-008/FR-009") e explicito por leitura literal: "Nenhum FR desta feature menciona exit code... Sao requisitos sobre o que a saida AFIRMA" — distinto de "o exit code decide". A obrigacao de FR-008 e cumprida pela linha de veredito `[PARCIAL]`/proibicao de `[OK]` (texto), nao pelo rc.
- [x] CHK011 - `unmanaged-upstream` NAO gatear o exit code (herdado do precedente ORPHAN) esta reconciliado com FR-010 (exige NAO contabilizar como saudavel) sem contradicao entre "nao gateia" e "nao pode ser chamado de saudavel"? [Consistencia, contract §3.5 + §4.4] {auto}
  Evidencia: contrato §3.5 declara os dois como canais distintos — "nao gatear e sobre acionabilidade, nao poder ser chamado de saudavel e sobre veracidade" — e §4.4 mostra que o precedente ORPHAN (pre-existente no codigo) ja tratava esse mesmo caso, sendo generalizado (nao inventado) pela postura report-only.

## Qualidade de Criterios de Aceite / Mensurabilidade

- [x] CHK012 - SC-004 ("a declaracao de cobertura NUNCA apresenta esse escopo como 100%/totalmente coberto") tem um cenario de teste que verifica isso contra um mecanismo REAL de leitura parcial (nao apenas contra o caso trivial de arquivo vazio)? [Mensurabilidade, Spec SC-004 + quickstart Cenario 19 linha 6] {auto}
  Evidencia: quickstart Cenario 19, linha 6 da matriz, exercita "linha sem TAB / com 5 campos / sha malformado" → `partial`; a Decision 6/7 do research.md documenta o par denominador-por-linha/numerador-por-uso que torna essa distincao mensuravel (nao apenas afirmada).
- [x] CHK013 - Existe cenario de teste que prova que o teste do invariante `section_rc == 0` (INV-RC) tem PODER DE DETECCAO — ou seja, que ele de fato falharia se a implementacao voltasse a gatear? [Mensurabilidade, quickstart Cenario 19 "Teste de mutacao"] {auto}
  Evidencia: quickstart Cenario 19 exige mutation testing explicito: alterar temporariamente a implementacao para `return 1` quando `count_shadowed >= 1`, rodar o cenario, confirmar que a linha 1 da matriz FALHA, depois reverter — com a nota "um teste que so afirma exit 0 passa trivialmente contra uma implementacao que nao emite a secao".
- [x] CHK014 - O teto de recursos (R5 — 10.000 linhas / 4.096 bytes por linha) tem criterio de aceite que distingue "checagem a posteriori" de "imposicao por leitura limitada", com cenario dedicado para o caso que so a segunda forma resolve? [Mensurabilidade, contract §7 R5 + quickstart Cenario 19 linhas 14-15] {auto}
  Evidencia: contrato §7 exige textualmente que o teto "MUST ser imposto por leitura limitada, nunca por checagem a posteriori" e explica por que um teto post-hoc e derrotado por um unico registro de varios GB sem `\n`. Cenario 19 tem DUAS linhas para isso (14: 10.001 linhas; 15: 1 linha de 50MB sem `\n`) justamente porque uma prova o teto de contagem e a outra prova que o teto e por leitura, nao por tamanho materializado.

## Cobertura de Cenarios

- [x] CHK015 - Existe um caso de teste NOMEADO que comprove que a skill local `.claude/skills/release-wave` (sem `.cstk-manifest`) continua fora do alcance desta feature em qualquer modo de invocacao do `cstk doctor`? [Cobertura, quickstart Cenario 4 + plan.md "Metade 1"] {auto}
  Evidencia: quickstart Cenario 4 e explicitamente rotulado "CASO NOMEADO" e usa `release-wave` como fixture; plan.md precisa a afirmacao correta ("a secao nova nao lhe atribui problema em nenhum modo de invocacao" — nao "continua ORPHAN", que so vale sob `--scope project` explicito), evitando uma alegacao mais forte do que o codigo garante.
- [x] CHK016 - O criterio de aceite do gate deterministico da lib nova (`manifest-coverage.sh`) esta amarrado ao mecanismo de enforcement do repo (`./tests/run.sh --check-coverage`), e nao apenas descrito em prosa? [Cobertura, plan.md linha "consequencia aceita" + quickstart Cenario 14] {auto}
  Evidencia: plan.md declara "consequencia aceita e planejada: o test file novo e obrigatorio (`./tests/run.sh --check-coverage` sai com exit 1 em orfao)"; quickstart Cenario 14 roda esse comando como parte do teste, tornando o requisito verificavel e nao apenas aspiracional.

## Edge Cases

- [x] CHK017 - O caso "registro referenciado no manifesto de projeto ja nao existe no catalogo" (FR-010) e distinguido, na saida, do caso "conteudo identico ao catalogo" por um rotulo proprio (nao um estado generico de erro)? [Edge Case, Spec FR-010 + contract §3 estado `unmanaged-upstream`] {auto}
  Evidencia: FR-010 exige relato "de forma distinguivel de conteudo identico ao catalogo"; o contrato nomeia o estado `unmanaged-upstream` especificamente para esse caso, distinto de `shadowed` (que exige as duas pontas presentes para comparar).
- [x] CHK018 - O caso "manifesto de projeto existe mas so parcialmente interpretavel" (edge case da spec) tem tratamento textual distinto de "nada divergente encontrado" — e essa distincao e a propria declaracao de cobertura, nao um rotulo adicional solto? [Edge Case, Spec §Edge Cases + contract §3.4/§3.5] {auto}
  Evidencia: a spec formula o requisito ("a checagem MUST distinguir nada divergente encontrado de leitura parcial... a declaracao de cobertura e o mecanismo que torna essa distincao visivel"); o contrato materializa isso no par estado `partial`/rotulo `[PARCIAL]`, que e mutuamente exclusivo de `[OK]`.

## Ambiguidades e Conflitos

- [x] CHK019 - A ambiguidade original sobre "onde/como o novo estado aparece na saida (texto e/ou `--json`)" (deixada deliberadamente em aberto na spec para o `/plan`) foi de fato resolvida no plan/contrato, sem permanecer como `[NEEDS CLARIFICATION]` residual? [Ambiguity, Spec §Clarifications + contract §3] {auto}
  Evidencia: a spec registra a decisao de adiar essa escolha explicitamente para `/plan`; o contrato §3 ("Formato de saida") especifica o formato textual completo (cabecalho, linhas de achado, bloco de remediacao, declaracao de cobertura, veredito) — a ambiguidade foi fechada, nao apenas herdada.
- [x] CHK020 - O ajuste de postura registrado em `dec-020`/`dec-022`/`dec-023` (report-only + rotulo `[ACHADOS]`) foi propagado a TODOS os artefatos afetados (spec permanece intacta por nao mencionar exit code; plan/contrato/data-model/quickstart emendados), sem nenhum artefato desatualizado remanescente? [Conflict, dec-022 rationale] {auto}
  Evidencia: dec-022 lista explicitamente os artefatos emendados ("plan.md, contracts/doctor-shadowed-scope-output.md, data-model.md, quickstart.md e research.md — Decision 13 nova; Decision 5 marcada supersedida") e justifica por que a spec nao precisou mudar ("NENHUM FR desta feature menciona exit code"); research.md D5 confirmada marcada como supersedida (grep desta sessao).

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`)
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
- Gate `requirement-coverage.sh` sobre `spec.md`: 0 findings (10/10 FRs com cenario associado) — nenhum `[Gap]` adicional gerado por esta via.
