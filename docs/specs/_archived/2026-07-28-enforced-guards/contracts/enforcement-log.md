# Contract: `enforcement-log.jsonl` (auditoria — FR-016, SC-005)

Arquivo `<projeto-alvo>/.claude/enforcement-log.jsonl`. Formato JSONL
(uma linha = um objeto JSON completo, sem array envolvente) — permite append
via `>>` sem reescrever o arquivo inteiro. [PROPOSTA] desta feature; nenhum
contrato externo preexistente.

## Escritores

- `pretooluse-bash-guard.sh` (US1) — uma linha por comando Bash interceptado
  dentro do escopo (Decision 3), ver `pretooluse-hook.md`.
- `cli/lib/serve.sh` (US2) — uma linha quando ha bypass explicito de
  integridade (`unverifiable-bypassed`) ou bloqueio (`unverifiable-blocked`,
  `mismatch-blocked`) — ver Decision 6/`data-model.md::IntegrityVerificationOutcome`.
  `verified` (sucesso silencioso, caminho ja existente) NAO gera linha — ruido
  desnecessario para o caso feliz ja coberto pelo `printf` informativo
  existente em `serve.sh:211`.

## Leitores

- Operador humano, via `grep`/`jq` manual (nenhuma skill de leitura dedicada
  nesta v1 — fora do escopo declarado da spec; FR-016 exige "revisavel", nao
  "com dashboard proprio").
- [PROPOSTA, fora do escopo desta feature] futura integracao com
  `cstk recall`/knowledge.db, analoga ao que ja existe para `state.json` —
  registrado como sugestao, nao implementado aqui.

## Schema por linha (union discriminada por `source`)

```json
{"source":"pretooluse-bash-guard","timestamp":"2026-07-05T13:00:00Z","outcome":"blocked-by-rule","command":"git push origin main","reason":"REGRA_VIOLADA: categoria=git-push — push bloqueado por padrao","category":"git-push","detected_execution":"feature-00c","detected_execution_path":"/repo/.claude/feature-00c-state/enforced-guards/state.json"}
{"source":"serve-integrity","timestamp":"2026-07-05T13:05:00Z","outcome":"unverifiable-bypassed","package_url":"https://github.com/JotJunior/cstk-panel/releases/download/v0.3.0/panel.tar.gz","expected_sha256":null,"actual_sha256":"a1b2c3...","bypass_method":"flag"}
```

| Field | Presente em | Tipo |
|-------|-------------|------|
| `source` | ambos | `"pretooluse-bash-guard"` \| `"serve-integrity"` |
| `timestamp` | ambos | ISO 8601 UTC |
| `outcome` | ambos | ver enums em `data-model.md` (por entidade) |
| `command`, `reason`, `category`, `detected_execution`, `detected_execution_path` | so `pretooluse-bash-guard` | ver `EnforcementDecisionLog` |
| `package_url`, `expected_sha256`, `actual_sha256`, `bypass_method` | so `serve-integrity` | ver `IntegrityVerificationOutcome` |

## Garantias

- **Append-only**: nenhum escritor faz seek/truncate; sempre `>>` no fim do
  arquivo.
- **Uma linha = um JSON valido**: nenhuma linha e multi-line; parseavel via
  `jq -c` linha a linha ou `jq -s` para o array completo.
- **Sem rotacao/retencao nesta v1**: fora do escopo da spec (nao ha FR sobre
  tamanho maximo ou expiracao) — registrado como possivel debito tecnico
  futuro caso o arquivo cresca sem limite.
- **`command` MUST passar por `secrets-filter.sh scrub` antes do append**
  (Decision 10, achado do gate `owasp-security` — MUST, nao mais adiavel):
  `printf '%s' "$CMD" | global/skills/agente-00c-runtime/scripts/secrets-filter.sh scrub`
  antes de compor a linha JSONL. Reusa o mecanismo ja usado hoje por backups
  de `state.json` e por `suggestions.sh`/`issue.sh` — sem dependencia nova.
  Motivo: comandos Bash interceptados frequentemente carregam credenciais em
  texto puro (URLs com userinfo, `Authorization: Bearer`, flags `-p`/`--token`);
  sem filtro, o log se torna um vetor de vazamento persistente.
- **Ordem OBRIGATORIA (CHK020 [Ambiguity], task 1.4): `scrub` PRIMEIRO,
  truncagem a 500 chars DEPOIS.** Nunca a ordem inversa. Truncar antes de
  escrubar pode CORTAR um token/secret no meio (ex: um `Authorization:
  Bearer <token-de-600-chars>` truncado em 500 chars deixa os primeiros ~480
  chars do token intactos no log, e o regex de `secrets-filter.sh` que
  dependeria de casar o padrao inteiro do token nunca roda sobre o
  fragmento que sobrou fora do corte — o pedaco do secret que ficou DENTRO
  dos 500 chars permanece exposto, exatamente o inverso do que o MUST
  acima exige). Pipeline correto:
  `printf '%s' "$CMD" | secrets-filter.sh scrub | cut -c1-500` (scrub opera
  sobre o comando INTEIRO, sem truncagem previa; o corte a 500 chars so
  acontece DEPOIS, sobre o resultado ja limpo).
  Caso de teste adversarial obrigatorio (consumido por 2.6): comando cujo
  token secreto atravessa a posicao 500 (ex: prefixo de ~450 chars +
  `--token=SECRETXYZ...` que so termina apos o char 500) — o resultado
  filtrado-e-truncado NUNCA MUST conter o valor do secret, nem parcial.
