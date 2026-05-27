# Requirements Checklist: Show Tips

**Purpose**: Quality gate de requisitos — valida clareza, completude e consistencia
dos requisitos escritos para a feature `show-tips`. Nao e checklist de implementacao.
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)

---

## Completude de Requisitos

- [ ] CHK001 - Cada FR (001–010) tem criterio de aceite mensuravel ou cenario de teste associado? [Completude, Spec §Requirements + §User Scenarios]
- [ ] CHK002 - O comportamento exato de "exibicao sob demanda" (FR-009) esta especificado: quem invoca, quais parametros e qual saida esperada? [Completude, Spec §FR-009]
- [ ] CHK003 - O formato de saida do `tip block` (FR-004) esta descrito com delimitadores concretos (ex: linha de `---`, cabecalho `##`)? [Completude, Spec §FR-004]
- [ ] CHK004 - Estao especificados os limites de tamanho do campo `text` (max 2 frases) para exemplos (`examples`) no catalogo? [Completude, Spec §FR-001, §Key Entities]
- [ ] CHK005 - A spec define o que acontece quando o catalogo tem entradas sem campo `category` valido (valor fora do enum `uso|gotcha|avancado`)? [Completude, Gap]
- [ ] CHK006 - Ha requisito explicitando o encoding esperado do catalogo (UTF-8?) e como caracteres especiais de Markdown nos exemplos sao tratados? [Completude, Spec §Edge Cases]

---

## Clareza de Requisitos

- [ ] CHK007 - `[CONFLICT]` FR-003 cita `$RANDOM % N` (bash-ism) como mecanismo de selecao pseudoaleatoria, mas o plan.md (Summary + Constitution Check §II) substitui por `/dev/urandom` + `awk srand` (POSIX). Essas duas descricoes sao inconsistentes: a spec nao reflete a decisao tecnica ratificada no plan (dec-012). A spec DEVE ser atualizada para descrever o mecanismo POSIX, eliminando a referencia a `$RANDOM`. [Conflict, Spec §FR-003, Plan §Summary + §Constitution Check]
- [ ] CHK008 - "Bloco visualmente destacado" (FR-004, US1 cenario 1) esta quantificado? Ou seja: ha especificacao do tipo de delimitador (linhas `---`, caixa `> `, prefixo `TIP:`)? [Clareza, Spec §FR-004]
- [ ] CHK009 - "Varia entre execucoes" (US1 cenario 2, FR-003) e mensuravel? Ha criterio para afirmar que a variacao e suficiente sem estado persistente? [Clareza, Spec §FR-003, §Edge Cases]
- [ ] CHK010 - "Menos de 5 minutos" (SC-005) esta contextualizado com o perfil do mantenedor (familiaridade com YAML/Markdown)? A medida de tempo e verificavel? [Clareza, Spec §SC-005]
- [ ] CHK011 - FR-006 usa "saida silenciosa (string vazia)": o comportamento e identico para falha de catalogo inacessivel, catalogo vazio e skill inexistente no catalogo? Ou cada caso tem comportamento diferente? [Clareza, Spec §FR-006, §US3 cenario 2]
- [ ] CHK012 - O parametro `fase-corrente` de FR-005/FR-007 esta descrito: e obrigatorio, opcional, ignorado silenciosamente se desconhecido? A spec e o contrato CLI concordam? [Clareza, Spec §FR-005, contracts/cli-show-tip.md]

---

## Consistencia de Requisitos

- [ ] CHK013 - `[CONFLICT]` FR-003 (spec) descreve `$RANDOM % N` enquanto plan.md describe `/dev/urandom + awk srand`. Alem de FR-003, a secao de Clarifications da spec (Session 2026-05-26, Q2) registra `$RANDOM % N` como resposta ratificada — ha tres fontes divergentes (spec.md FR-003, spec.md Clarifications, plan.md). Qual e a fonte de verdade para o mecanismo RNG? [Conflict, Spec §FR-003, §Clarifications, Plan §Summary]
- [ ] CHK014 - O campo `examples` de Key Entities descreve "lista de exemplos com texto e comando/resultado opcional", mas FR-001 diz "pelo menos 1 exemplo de uso concreto". A definicao de "exemplo" e consistente entre Key Entities e FR-001? [Consistencia, Spec §FR-001, §Key Entities]
- [ ] CHK015 - SC-001 exige "100% das skills (global + language-related)"; FR-002 exige "todas as skills do projeto". Ha definicao fechada de "todas as skills"? O plano cita 38 skills (23+7+8) — a spec tem este numero fixado? [Consistencia, Spec §FR-002, §SC-001, Plan §Technical Context]
- [ ] CHK016 - US4 (P4) descreve o orquestrador "recebendo um bloco de texto pronto para exibicao"; FR-005 descreve o script como invocavel com parametros. Os dois sao consistentes com o contrato CLI? [Consistencia, Spec §US4, §FR-005, contracts/cli-show-tip.md]

---

## Qualidade de Criterios de Aceite

- [ ] CHK017 - SC-002 ("menos de 1 segundo") e SC-003 ("taxa de interrupcao 0%"): ha metodo definido para medir cada uma delas em ambiente de CI? [Mensurabilidade, Spec §SC-002, §SC-003]
- [ ] CHK018 - SC-004 descreve um "script automatizado que verifica cobertura" — este script esta definido como artefato a entregar (em tasks.md futuramente)? [Mensurabilidade, Spec §SC-004]
- [ ] CHK019 - Os cenarios de aceite de US1 (3 cenarios), US2 (3), US3 (3), US4 (2) sao independentemente verificaveis sem execucao completa do pipeline? [Mensurabilidade, Spec §User Scenarios]
- [ ] CHK020 - FR-002 exige ">= 2 entradas por skill cobrindo ao minimo as categorias `uso` e `gotcha`". Ha cenario de aceite que valida a distribuicao categorica minima (nao apenas contagem)? [Mensurabilidade, Spec §FR-002]

---

## Cobertura de Cenarios

- [ ] CHK021 - Existe cenario de aceite para quando o usuario invoca `cstk show-tip` sem argumento de skill? (US3 cenario 3 cobre "dica aleatoria" mas nao o comportamento CLI concreto) [Cobertura, Spec §US3, §FR-010]
- [ ] CHK022 - O fluxo de integracao dos orquestradores (agente-00c / feature-00c) invocando `show-tip.sh` no inicio de onda esta coberto por cenario de aceite com pre/pos-condicoes? [Cobertura, Spec §US1, §US4]
- [ ] CHK023 - Existe cenario cobrindo a exibicao quando a skill alvo existe no catalogo mas nao tem entradas da categoria solicitada? [Cobertura, Gap]
- [ ] CHK024 - O cenario de "catalogo vazio" (0 entradas) esta coberto alem de "catalogo inacessivel"? [Cobertura, Spec §US1 cenario 3, §FR-006]

---

## Cobertura de Edge Cases

- [ ] CHK025 - O comportamento quando `N=1` (catalogo com exatamente 1 dica para a skill) esta formalmente descrito nos requisitos alem do Edge Cases informal? [Cobertura, Spec §Edge Cases]
- [ ] CHK026 - O que acontece com entradas no catalogo que tenham campos YAML malformados (frontmatter invalido)? A spec define o comportamento esperado (ignorar, falha silenciosa, erro de parsing)? [Cobertura, Gap]
- [ ] CHK027 - Ha requisito para o comportamento quando `tips/catalog.md` existe mas esta vazio (0 bytes vs "sem entradas validas")? [Cobertura, Gap]
- [ ] CHK028 - O Edge Case "dica com caracteres especiais de Markdown" esta coberto por requisito formal, nao apenas como nota informal? [Cobertura, Spec §Edge Cases]

---

## Requisitos Nao-Funcionais

- [ ] CHK029 - Ha requisito de portabilidade explicitando as versoes minimas de `awk`, `grep`, `od` e `sed` alvo (POSIX.1-2017? POSIX.1-2008?)? [Nao-Funcional, Assumption]
- [ ] CHK030 - SC-002 ("<1s") e valido para catalalogos com 76+ entradas em hardware de referencia (ex: GitHub Actions ubuntu runner)? Ha dado empirico ou assumpcao documentada? [Nao-Funcional, Spec §SC-002, Assumption]
- [ ] CHK031 - Ha requisito de compatibilidade para o script `show-tip.sh` em ambientes onde `/dev/urandom` esta indisponivel (ex: containers minimalistas)? [Nao-Funcional, Gap]
- [ ] CHK032 - A acessibilidade da saida (UX de terminal) esta especificada? Por ex: delimitadores legives em terminais sem cor/formatacao Markdown renderizada? [Nao-Funcional, Gap]

---

## Dependencias e Premissas

- [ ] CHK033 - A premissa "38 skills cobertas" (plan.md Technical Context) esta documentada na spec? Se o numero de skills mudar, o requisito FR-002 atualiza automaticamente? [Assumpcao, Plan §Technical Context, Spec §FR-002]
- [ ] CHK034 - A dependencia de `cli/lib/common.sh` e `cli/lib/ui.sh` (referenciadas no plano) para logging e bloco visual esta documentada como pre-requisito ou premissa? [Dependencia, Plan §Project Structure]
- [ ] CHK035 - Existe premissa documentada de que `tips/catalog.md` sera mantido em sync com o conjunto de skills do projeto (nao ha mecanismo automatico de sincronizacao)? [Assumpcao, Spec §FR-008]

---

## Ambiguidades e Conflitos

- [ ] CHK036 - `[AMBIGUITY]` FR-005 menciona "parametro skill-alvo (opcional)" mas nao define o comportamento quando o valor passado nao coincide com nenhuma skill no catalogo. Deve retornar dica aleatoria ou string vazia? (US3 cenario 2 sugere "mensagem amigavel", mas FR-006 sugere "saida silenciosa") [Ambiguity, Spec §FR-005, §FR-006, §US3]
- [ ] CHK037 - `[AMBIGUITY]` US3 cenario 2 descreve "mensagem amigavel" para skill inexistente, mas FR-006 exige saida silenciosa em qualquer falha. Ha tensao entre esses dois requisitos? Qual prevalece? [Ambiguity, Spec §US3 cenario 2, §FR-006]
- [ ] CHK038 - O escopo de "invocavel pelos orquestradores" (US4) implica que `show-tip.sh` deve estar disponivel no PATH do ambiente CI (via `cstk`)? Ou apenas como path absoluto? [Ambiguity, Spec §US4, §FR-005]

---

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
- `[CONFLICT]` = inconsistencia entre dois artefatos (CHK007, CHK013)
- `[AMBIGUITY]` = requisito interpretavel de mais de uma forma (CHK036, CHK037, CHK038)
- `[Gap]` = aspecto nao coberto pela spec atual
- `[Assumption]` = premissa implicita nao documentada formalmente
- Rastreabilidade: 38/38 items (100%) referenciam spec, plan ou marcador de qualidade
