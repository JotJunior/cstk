# Contract: integracao orquestrador ↔ model-routing helper

Contrato declarando como os agents `agente-00c-orchestrator.md` e
`agente-00c-feature-orchestrator.md` consomem o helper `model-routing.sh`
no caminho pre-spawn da fase clarify.

Esta feature NAO altera contrato externo de nenhuma skill ja
publicada. Define um contrato INTERNO entre orquestradores e o novo
helper.

---

## Sequencia pre-spawn obrigatoria

Cada spawn de subagente via tool Agent na fase clarify segue a
sequencia exata (FR-010, FR-011):

```
1. spawn-tracker.sh check --max-depth 3 --state-dir DIR
   exit 0 -> ha depth disponivel; segue
   exit 1 -> abortar spawn (sem invocacao da skill)

2. ONDA_ID=$(state-ondas.sh current-id --state-dir DIR)

3. EXISTING=$(model-routing.sh idempotent-check \
       --state-dir DIR --onda-id "$ONDA_ID" --subagent-type T)
   se exit 0 com dec-NNN -> pula 4-6, segue para 7 com decisao_id existente
   se exit 1 -> prossegue para 4

4. JSON=$(model-routing.sh invoke --subagent-type T --etapa clarify)
   # JSON contem: modelo, score_runtime, fallback, sinais_text, etc.

5. DEC_ID=$(state-decisions.sh register \
       --state-dir DIR \
       --agente <orchestrator-id> \
       --etapa clarify \
       --contexto "Selecao de modelo para subagente T" \
       --opcoes '["haiku","sonnet","opus","manter-atual","fallback-default"]' \
       --escolha "<modelo do JSON>" \
       --justificativa "<sinais_text + nota truncagem se aplicavel>" \
       --score <score_runtime do JSON> \
       [--evidencia "<sinais_text>"])

6. state-ondas.sh record-skill --state-dir DIR \
       --skill model-selector --decisao-id "$DEC_ID"

7. spawn-tracker.sh increment --state-dir DIR

8. <invocacao tool Agent com subagent_type=T>
```

---

## Mapeamento de campos JSON → state-decisions.sh

| Campo do JSON do helper | Flag de `state-decisions.sh register` |
|-------------------------|----------------------------------------|
| `modelo` | `--escolha` |
| `score_runtime` | `--score` |
| `sinais_text` + nota | `--justificativa` |
| `sinais_text` (se score=3) | `--evidencia` |
| (constante) | `--opcoes '["haiku","sonnet","opus","manter-atual","fallback-default"]'` |
| (do orquestrador) | `--agente <orchestrator-id>` |
| (do orquestrador) | `--etapa clarify` |
| (formato fixo) | `--contexto "Selecao de modelo para subagente <T>"` |

Quando `fallback: true` no JSON, o orquestrador:

- `--escolha "fallback-default"`
- `--score 0`
- `--justificativa "fallback: <fallback_reason>; stderr: <fallback_stderr_first_200>"`
- omite `--evidencia` (nao aplicavel a score=0)

---

## Invariantes consumidas por `review-task`

`review-task` agrega via jq sobre `.decisoes[]`. Query base (FR-018):

```sh
jq -r '
  [.decisoes[]
   | select(.contexto | test("^Selecao de modelo para subagente "))
   | {subagent_type: (.contexto | capture("subagente (?<s>[a-z0-9-]+)") | .s),
      etapa: .etapa,
      escolha: .escolha,
      score: .score,
      fallback: (.escolha == "fallback-default"),
      timestamp: .timestamp}]
  | group_by(.subagent_type)
  | map({subagent_type: .[0].subagent_type,
         total: length,
         fallbacks: ([.[] | select(.fallback)] | length),
         distribuicao: (group_by(.escolha) | map({escolha: .[0].escolha, count: length}))})
' state.json
```

Esta query e a interface contractual entre o registro persistido
nesta feature e o agregador consumido por review-task. Mudancas no
formato do `contexto` (FR-018) ou no enum de `escolha` (entidade
Decisao §invariantes) sao BREAKING e exigem nova feature.

---

## Compatibilidade com agente-00c-artifact-cache

Quando a feature `agente-00c-artifact-cache` esta ATIVA (cache de
resumo de briefing/constitution em state.json), o helper
`model-routing.sh` NAO interage com o cache — o input passado a
skill model-selector e gerado puramente do template estatico
(`template --subagent-type T`), nao do conteudo de briefing nem de
constitution.

Logo, a invariante SC-004 e satisfeita por construcao: invocacao do
helper e independente de qualquer estado de cache.

---

## Allowed-tools dos orquestradores

A feature exige que os 2 agents tenham permissao para invocar
`model-routing.sh` via Bash (ja existem permissoes para outros scripts
do runtime). NENHUMA nova tool e requerida — Bash + Skill ja estao
nos `allowed-tools` de ambos.

Especificamente:

- `agente-00c-orchestrator`: ja tem Bash. Patch documental apenas.
- `agente-00c-feature-orchestrator`: ja tem Bash. Patch documental apenas.

Subagentes (asker, answerer) NAO precisam de nada — eles sao
folha (FR-021 do orchestrator). A invocacao da skill acontece sempre
no orquestrador pai.
