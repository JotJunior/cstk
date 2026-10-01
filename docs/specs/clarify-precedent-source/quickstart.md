# Quickstart: clarify-precedent-source

Cenarios 1-7 sao deterministicos (fixture `knowledge.db` sintetica em
`tests/cstk/test_recall.sh`; textos sinteticos, sem copiar dado real de
outros projetos). Cenario 8 e o eval nao-gateante sobre a base real.

## Scenario 1: Par re-perguntado recuperado acima do limiar (SC-001)

1. Fixture com dois bloqueios respondidos cujas perguntas tem Jaccard >= 0.7
   entre si (mesma estrutura dos pares medidos 108/112) e ruido de Jaccard
   < 0.2.
2. `cstk recall --precedents "<pergunta do bloqueio A>" --db <fixture>`
   com o registro A excluido da fixture.
3. **Expected**: exit 0; uma entrada `ref=` do bloqueio B com
   `similarity=` >= 0.550; nenhuma entrada de ruido.

## Scenario 2: Duplicata de ingestao colapsada (research Decision 3)

1. Fixture com o MESMO bloqueio (mesma question/answer/answered_at) sob dois
   `project` distintos, como 242/251.
2. Consultar com pergunta semelhante.
3. **Expected**: exatamente UMA entrada para o par duplicado.

## Scenario 3: Elegibilidade e etapa de origem (FR-002, FR-016)

1. Fixture com um bloqueio `aguardando`, um `respondido` com `answer` vazio
   e um `respondido` valido com `decision_id` apontando para uma decisao de
   `stage='plan'`.
2. Consultar.
3. **Expected**: so o valido aparece, com `stage=plan`; sem join resolvido
   → `stage=-`.

## Scenario 4: Tetos (FR-011)

1. Fixture com 6 candidatos acima do limiar e campos com 1000 bytes
   (incluindo caracteres acentuados na fronteira de 300 bytes).
2. Consultar com defaults; depois com `--limit 1` e `--max-bytes 400`.
3. **Expected**: <= 3 entradas e stdout <= 2400 bytes no default; campos
   <= 300 bytes sem sequencia UTF-8 quebrada; com `--max-bytes 400`
   nenhuma entrada cortada no meio.

## Scenario 5: Degradacao graciosa (FR-010, SC-004 — parte deterministica)

1. Rodar `--precedents` com: (a) `--db` inexistente; (b) arquivo nao-SQLite;
   (c) `sqlite3` fora do PATH (PATH interno desacoplado — ver gotcha do
   harness sobre binarios em /usr/bin); (d) pergunta `"ok?"`.
2. **Expected**: exit 0 e stdout vazio nos quatro casos.

## Scenario 6: Erros de uso

1. `--precedents` sem pergunta; com `--min-similarity 1.5`; com
   `--limit 0`; com `--type block`.
2. **Expected**: exit 2, stdout vazio, mensagem em stderr.

## Scenario 7: Prosa dos orquestradores e answerers (FR-001, FR-018, FR-009)

1. Teste estatico (interno) sobre `plugins/cstk/agents/*-clarify-answerer.md`
   e `references/orchestrators/{feature,root}/clarify.md`.
2. **Expected**: ambos os answerers descrevem a 4a fonte com as regras 1-7
   do contrato — incluindo a regra de suporte positivo (precedente so soma
   com +1 de `briefing` ou da terceira fonte; o +1 de constitution nao conta,
   dec-027) — e mantem `tools: Read, Bash`; ambas as referencias invocam
   `cstk recall --precedents` antes do spawn do answerer, registram
   `precedent_consulted` e omitem `precedents` quando vazio; blocos de
   paridade identicos entre as duas referencias.

## Scenario 8: Recalibracao sobre a base real (eval nao-gateante)

1. `tests/eval/eval_precedent-calibration.sh` (pula com aviso se
   `~/.claude/cstk/knowledge.db` ausente).
2. Reapresenta as perguntas dos pares 108/112 e 242/251 ao modo
   `--precedents`, excluindo o proprio registro.
3. **Expected**: cada pergunta recupera o bloqueio par; imprime a
   distribuicao de Jaccard corrente para comparar com research Decision 2.

## Scenario 9: Clarify ponta a ponta com precedente (manual/eval)

1. Numa execucao feature-00c com base de conhecimento contendo um
   precedente aplicavel, rodar a etapa clarify.
2. **Expected**: evento `precedent_consulted` por pergunta em `.events[]`;
   Decisao com `block_ref` na justificativa quando o precedente pontua;
   bloqueio humano com secao "Precedentes" quando pausa.
3. Caso adicional (US1 cenario 3): opcao apoiada so por "constitution nao
   violada" + precedente concordante → item `precedent` com `scored: false`,
   sem decisao automatica causada pelo precedente; se pausar, o precedente
   aparece como `recommended_precedent`.
