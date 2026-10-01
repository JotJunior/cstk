# `tests/eval/` — evals de obediência (FORA do gate de release)

Estes scripts medem o que a suíte determinística **não** consegue medir: se
um agente real, lendo a prosa dos commands, **obedece** às cláusulas que
`tests/test_*.sh` apenas verifica estarem escritas.

## Por que ficam fora de `./tests/run.sh`

O runner descobre testes por `tests/test_*.sh`; os arquivos aqui usam o
prefixo `eval_` justamente para **não** serem coletados. Isso é
deliberado, por três razões:

1. **Não-determinismo.** A saída depende de um LLM. Um eval que gateia
   release transforma a suíte em flaky e treina todo mundo a ignorar
   vermelho.
2. **Custo.** Cada execução consome tokens reais e leva minutos.
3. **Credencial.** Exige `claude` autenticado no runner — o CI do repo
   não tem, e dar essa credencial ao CI é uma decisão de segurança
   separada.

Um eval vermelho é **sinal para investigar**, nunca um bloqueio automático.

## Quando rodar

- Depois de mexer nos blocos de prompt de `plugins/cstk/commands/*.md`.
- Depois de mudar a resolução de tier em `delivery-tier.sh`.
- Antes de uma release que toque qualquer um dos dois.

## Evals disponíveis

| Script | O que mede | Origem |
|---|---|---|
| `eval_noninteractive-tier.sh` | `/agente-00c` headless: não trava no warm-up **e** resolve `cloud-public` sem operador | quickstart Cenário 17 |
| `eval_roadmap-wave-frontier.sh` | `/roadmap-wave` headless: (A) sem `--yes` obedece o fail-safe FR-014 (nada lançado, fim silencioso); (B) com `--yes` e fronteira vazia roda o frontier de verdade e reporta o vazio sem lançar | Camada C do plano de e2e da leva paralela (complementa `tests/test_e2e_roadmap_wave.sh`) |
| `eval_precedent-calibration.sh` | `cstk recall --precedents` sobre a base REAL (`~/.claude/cstk/knowledge.db`, somente leitura): (A) reapresenta a pergunta dos pares medidos na calibracao (108/112, 242/251 — `blocks.id`, sobrescreva com `EVAL_PAIRS`) e reporta se o par foi recuperado ou colapsado por dedup; (B) imprime o histograma de Jaccard dos vizinhos de uma amostra (`EVAL_SAMPLE`, default 60) para comparar com a research Decision 2. Pula (exit 2) sem `sqlite3` ou sem `knowledge.db` | clarify-precedent-source, quickstart Cenario 8 |

## Cenario 9 manual: clarify ponta a ponta com precedente (`clarify-precedent-source`)

Nao ha script: o comportamento do `clarify-answerer` (LLM) com a 4a fonte so
e observavel numa execucao real. A parte deterministica ja e gateada por
`tests/cstk/test_recall.sh` (contrato do `--precedents`) e por
`tests/test_clarify-precedent-prose.sh` (prosa dos answerers e das
referencias). O que ESTE cenario cobre e o que aqueles nao conseguem:

1. Numa execucao `/feature-00c` (ou `/agente-00c`) com a knowledge.db
   contendo um bloqueio respondido aplicavel, rode a etapa `clarify`.
2. Esperado: evento `precedent_consulted` por pergunta em `.events[]`
   (`stage=clarify question=<Qn> hits=<K>`); quando o precedente pontua,
   Decisao com o `block_ref` na justificativa e sem copiar o texto do
   precedente (Regra S-2); quando a pergunta pausa, o bloqueio humano traz a
   secao "Precedentes" (recomendado ou divergentes) com origem e a frase
   "recomendacao derivada de historico, nao verificada".
3. **Caso adicional (US1 cenario 3, dec-027)**: opcao apoiada APENAS por
   "constitution nao violada" + precedente concordante (briefing e terceira
   fonte silenciosos). Esperado: item `precedent` com `scored: false`, nenhuma
   decisao automatica causada pelo precedente; se a pergunta pausar, o
   precedente aparece como `recommended_precedent`. Um vermelho aqui (o
   answerer decidiu so por precedente + constitution) e o sinal mais grave
   desta feature — registre e reforce a regra P1 nos dois answerers.
4. SC-004 (saida identica sem precedente): rode a mesma pergunta com e sem o
   campo `precedents` (K=0) e compare as respostas do answerer. Diferencas
   sao sinal para investigar, nao reprovacao automatica (saida de LLM).

## Ensaio geral supervisionado (`rehearsal_*`)

`rehearsal_roadmap-wave.sh` é a Camada D do mesmo plano: o fluxo COMPLETO
com sessões-filha **reais** (tmux + `claude` de verdade rodando
`/feature-00c`). Não é um eval automático — é um runbook executável com
bookends mecânicos: `setup` monta o projeto de brinquedo e imprime os
passos do operador; `status` dá o snapshot mecânico mid-flight; `verify`
faz as asserções finais (worktrees zeradas, states preservados, roadmap
100% concluído, main limpa). Rodar 1x por release que toque orquestração
paralela. Custa tokens reais e horas de parede — jamais em CI.

## Como rodar

```sh
./tests/eval/eval_noninteractive-tier.sh
```

Exit `0` = comportamento conforme. Exit `1` = divergência (investigar).
Exit `2` = não foi possível avaliar (sem `claude` no PATH, etc.) — **não**
é reprovação.

## Histórico: por que este diretório existe

O Cenário 17 do quickstart ficou marcado `[ACEITAÇÃO MANUAL]` por toda a
feature `delivery-tier` porque ninguém sabia como testá-lo. Quando
finalmente foi executado à mão (2026-08-15), achou **dois** defeitos reais
que a suíte de 2966 cenários não pegava:

1. `/agente-00c` abortava no warm-up de permissões sem criar state-dir —
   nenhuma execução agendada conseguia iniciar.
2. Com o warm-up vencido, o agente **inferiu** o tier do briefing e gravou
   `local`, em vez do `cloud-public` que o FR-003 exige.

Ambos viraram correção + cobertura determinística (a decisão saiu da prosa
e virou `delivery-tier.sh resolve-initial`; o lint de classe cobre a
cláusula em todos os commands). O resíduo — obediência em runtime — é o
que estes evals cobrem.

**Armadilha registrada**: na primeira inspeção do spike, `delivery-tier.sh
get` devolveu `cloud-public` e parecia confirmar sucesso. Era o fail-safe
de *state-dir inexistente* — o command havia abortado antes de criar
qualquer estado. **Sempre confirme que o state-dir existe** antes de dar
um eval por aprovado; um valor correto pelo motivo errado é pior que um
vermelho.
