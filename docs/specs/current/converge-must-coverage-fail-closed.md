# Capability: converge-must-coverage-fail-closed

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-001

Quando a verificação de cobertura de `MUST` da etapa de convergência reportar que a constituição do projeto-alvo contém pelo menos uma ocorrência da palavra MUST e nenhuma linha de regra reconhecida (`N > 0` e `M == 0`), o sistema MUST registrar isso como um achado estruturado no relatório de convergência (não apenas como observação textual para o agente seguir).

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-002

O achado descrito na FR-001 MUST ser classificado com o mesmo tipo usado hoje para "comportamento existente que contradiz o que foi pedido" e com a severidade mais alta reservada a esse tipo de achado quando associado a uma prioridade alta — refletindo que uma verificação de obrigatoriedade que não rodou de fato é, na prática, uma contradição entre o que a constituição exige e o que o gate confirma.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-003

O achado da FR-001 MUST citar a constituição do projeto-alvo como o artefato afetado e identificar como origem a própria verificação de cobertura de MUST (não uma tarefa/requisito pré-existente do backlog da feature em convergência), para que fique rastreável de onde o achado veio.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-004

O achado da FR-001 MUST contar na contagem de pendências acionáveis usada para decidir se a feature está convergida — o resultado "convergido, sem pendências" MUST NOT ser produzido enquanto essa condição de cobertura zero persistir.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-005

O sistema MUST NOT gerar o achado da FR-001 quando a constituição do projeto-alvo não contiver a palavra MUST em lugar nenhum **e** não houver nenhum princípio emitido só por rótulo de heading (`N == 0` **e** `Q == 0`) — nessa combinação não há obrigação declarada, em nenhum dos dois vocabulários, e a ausência total não é tratada como lacuna de cobertura. Quando `Q > 0`, esta garantia não se aplica: prevalece a FR-010, e o achado É gerado por desenho, ainda que `N == 0` — comportamento validado pela fixture de referência `N = 0`, `M = 0`, `Q = 1` → `cobertura de MUST: cobertura-parcial`, `exit=4` (esta combinação não é a medida na issue #188; o caso-bandeira medido nessa issue é `M > 0` **e** `Q > 0` — ver FR-010 e Apêndice A).

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-006

O sistema MUST NOT gerar o achado da FR-001 quando pelo menos uma linha de regra MUST já for reconhecida na constituição do projeto-alvo **e** não houver nenhum princípio emitido só por rótulo de heading (`M > 0` **e** `Q == 0`) — nessa combinação o comportamento anterior a esta feature é preservado sem mudança, e a cobertura mista de formato dentro do corpo dos princípios permanece fora de escopo (ver Edge Cases). Quando `Q > 0`, esta garantia não se aplica: prevalece a FR-010, e o achado É gerado por desenho, ainda que `M > 0`.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-007

A orientação seguida pela skill de criação/atualização de constituição MUST apresentar, como forma esperada de escrever uma obrigação de princípio, o formato de regra reconhecido pela verificação de cobertura de MUST — substituindo ou complementando a orientação atual, que hoje resulta em prosa corrida não reconhecida.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-008

O texto-semente do princípio-base obrigatório de Veracidade de Dados que a skill de constituição sempre inclui MUST, ele próprio, seguir o formato de regra reconhecido pela verificação de cobertura de MUST — servindo de exemplo vivo já na primeira constituição gerada por qualquer projeto.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-009

Esta feature MUST NOT alterar nem exigir alteração de constituições de projetos já existentes — o efeito da FR-007/FR-008 é sobre orientação consumida em gerações/edições futuras da constituição, nunca uma migração automática de arquivos já ratificados.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-010

Quando a verificação de cobertura de `MUST` identificar pelo menos um princípio emitido sem nenhuma regra `MUST` legível — isto é, emitido só pelo rótulo do heading (`Q > 0`, na notação de contagens desta capability: `N` = ocorrências da palavra `MUST` no arquivo, `M` = linhas de regra `MUST` reconhecidas pelo parser, `Q` = princípios emitidos só por rótulo de heading) — o sistema MUST classificar esse resultado com um veredito distinto de `ok` e de `sem-must-declarado`, mesmo quando outras regras `MUST` da mesma constituição já tiverem sido reconhecidas (`M > 0`) e mesmo quando a palavra `MUST` não ocorrer em lugar nenhum do arquivo (`N == 0`). O token literal desse veredito (exposto na linha `cobertura de MUST: <veredito>`) MUST ser `cobertura-parcial`, com a única exceção da regra de precedência a seguir. Precedência de `zero-reconhecida` (deliberada, ratificada — `research.md` Decision 11): quando os DOIS conjuntivos valerem ao mesmo tempo — (a) `M == 0` **e** (b) `N > 0` — a guarda de `zero-reconhecida` tem precedência sobre esta FR-010 e o veredito emitido MUST permanecer `zero-reconhecida` (exit 3), não `cobertura-parcial`. Basta faltar UM dos dois conjuntivos para a precedência não entrar em jogo, e nesse caso o veredito MUST ser `cobertura-parcial` (exit 4) sempre que `Q > 0`; os dois ramos complementares são `M == 0` **e** `N == 0` (falta (b)) e `M > 0` (falta (a)). A precedência não reduz a acionabilidade: o achado estruturado emitido pela FR-012 é o mesmo `Gap` nos dois vereditos (`contracts/must-coverage-finding.md` §3.2). O comportamento aqui descrito já está validado por `tests/test_extract-must.sh :: scenario_coverage_r02_precedencia_zero_reconhecida_vence` — esse teste e a ordem das guardas em `extract-must.sh` MUST NOT ser alterados por esta feature.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-011

O veredito `cobertura-parcial` — o que o corpo da FR-010 fixa, não o `zero-reconhecida` do ramo de precedência — MUST ser exposto por um sinal de saída (exit code) que um consumidor automatizado da verificação de cobertura consiga distinguir, sem inspecionar texto, dos sinais já usados para `ok`, `zero-reconhecida` e `sem-must-declarado`. Este exit code MUST ser `4`. No ramo de precedência da FR-010 o sinal de saída permanece o já usado por `zero-reconhecida`.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-012

Quando a etapa de convergência observar o veredito descrito na FR-010, o sistema MUST registrar um achado estruturado no relatório de convergência com os mesmos campos fixos (artefato afetado = constituição do projeto-alvo; origem = a própria verificação de cobertura de `MUST`; classificação e severidade calculadas pela mesma regra determinística já usada para o veredito `zero-reconhecida`) usados para aquele veredito. O achado desta FR-012 MUST também contar na contagem de pendências acionáveis usada para decidir se a feature está convergida — o resultado "convergido, sem pendências" MUST NOT ser produzido enquanto essa condição persistir.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-013

Quando houver pelo menos um princípio classificado conforme a FR-010 (`Q > 0`), a verificação de cobertura de `MUST` MUST identificar nominalmente, na sua saída, qual(is) princípio(s) da constituição do projeto-alvo carecem de uma regra `MUST` legível — hoje a saída informa apenas a contagem, sem nomear os princípios afetados. A forma exata de onde essa identificação nominal aparece na saída (por exemplo: linhas adicionais de um relatório já existente, ou um canal de saída separado) é uma decisão técnica deferida para o plano técnico, não fixada por esta especificação; seja qual for a forma escolhida, ela MUST NOT alterar a saída no caso `Q == 0` (FR-014).

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

### FR-014

Quando NÃO houver nenhum princípio classificado conforme a FR-010 (`Q == 0`), a saída da verificação de cobertura de `MUST` MUST permanecer byte-idêntica ao formato hoje validado para esse caso, sem nenhum conteúdo adicional — a identificação nominal da FR-013 só se aplica quando há pelo menos um princípio a nomear.

*Introduzida por: converge-must-coverage-fail-closed (2026-09-09)*

