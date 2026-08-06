# Security Checklist: loose-usage-capture

**Purpose**: validar a QUALIDADE dos requisitos de seguranca/privacidade da
captura de consumo avulso — protecao de dados, opt-in/consentimento,
superficie de rede, auditabilidade e ciclo de vida dos dados locais
persistidos. Dominio adicional (nao-primario) justificado pelo design: hook
que le telemetria e escreve um sidecar local novo fora de qualquer
repositorio versionado.
**Created**: 2026-08-06
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) |
[research.md](../research.md) | [data-model.md](../data-model.md) |
[contracts/hook-loose-usage.md](../contracts/hook-loose-usage.md)
**Numeracao**: CHK019–CHK031 (IDs unicos por feature; continuam de
`requirements.md`)

## Protecao de Dados / Privacidade

- [x] CHK019 - O vazamento de PII (`user_id`, `user_email`,
  `user_account_uuid`, `user_account_id`, `organization_id`) e impedido
  por construcao antes de qualquer dado alcancar o sidecar local, com
  defesa em profundidade (nao apenas um unico ponto de filtro)? [Protecao
  de Dados, contracts/hook-loose-usage.md §Privacidade] {auto} — "Os
  labels de PII ... sao descartados por construcao no parse do
  `otel-usage.sh` (allowlist de 4 labels) e reconferidos por defesa em
  profundidade antes de o snapshot ser publicado (linhas 276-281, que
  APAGAM o arquivo e falham alto se algum vazar)".
- [x] CHK020 - Os artefatos persistidos (sidecar TSV, tabela
  `loose_usage`) contem apenas metadados de custo/token/modelo, sem campo
  de conteudo de prompt/conversa? [Protecao de Dados, data-model.md
  §LooseUsageRecord] {auto} — schema de `LooseUsageRecord` lista apenas
  `project`, `project_path`, `process_key`, `segment_id`, `model`,
  `cost_usd`, `total_tokens`, `segment_open`, `captured_at`,
  `ingested_at`; nenhum campo de texto livre de conteudo de sessao.
- [x] CHK021 - Existe requisito de permissao de arquivo restritiva
  (least privilege) para o diretorio novo `~/.claude/cstk/loose-usage/`
  e seus arquivos, no MESMO padrao ja aplicado ao `knowledge.db`
  (`chmod 600`, `recall_normalize_db_perms`)? [Gap, cli/lib/recall.sh
  linhas ~669-685 vs spec.md/plan.md/data-model.md/contracts/*] {auto} —
  RESOLVIDO pela task 1.2: data-model.md §Permissao (CHK021) documenta
  `chmod 700` nos diretorios (raiz, `<process_key>/`, `seg-*/`) e
  `chmod 600` nos arquivos (`meta.tsv`, `otel-start.tsv`, `otel-end.tsv`),
  paridade com `recall_normalize_db_perms`.
  Precedente direto ja existe no proprio codebase para o arquivo irmao
  (`knowledge.db`) — a ausencia de requisito equivalente para o
  diretorio de sidecar (que tambem contem `project_path` — path absoluto
  do projeto do operador) e uma lacuna, nao uma decisao explicita.

## Opt-in / Consentimento (FR-006)

- [x] CHK022 - O requisito de opt-in e enforced por um mecanismo
  estrutural verificavel (provisionamento separado), nao apenas por
  documentacao/convencao? [Autorizacao, research.md Decision 10 +
  contracts/hook-loose-usage.md §Registro no harness] {auto} — "flag nova
  `cstk hooks install --with-loose-usage` `[PROPOSTA]`, default
  DESLIGADA, com snippet de registro em arquivo SEPARADO" — o hook so
  existe no harness se o operador rodar o comando explicito.
- [x] CHK023 - Ha garantia de que o hook de captura NUNCA e bundlado
  silenciosamente junto dos guard hooks obrigatorios (risco de opt-in
  implicito via `cstk hooks install` default)? [Autorizacao, plan.md
  §Project Structure + research.md Decision 10] {auto} — plan.md lista o
  novo `settings.loose-usage.snippet.json` como arquivo SEPARADO de
  `settings.snippet.json` (que registra os 3 hooks obrigatorios);
  research.md Decision 10: "O hook de captura NUNCA entra em
  `apply_guard_hooks()` por default".

## Superficie de Rede / Threat Modeling

- [x] CHK024 - A superficie de rede da feature esta confinada a loopback
  (`127.0.0.1`), sem introduzir nenhum destino remoto novo em relacao ao
  que ja esta em producao? [Threat Modeling, plan.md §Principio IV +
  contracts/hook-loose-usage.md §Privacidade] {auto} — plan.md: "Destino:
  `127.0.0.1` (loopback), servidor do proprio processo ... Nenhum pacote
  deixa a maquina"; reusa exatamente `otel-usage.sh`, sem endpoint novo.
- [x] CHK025 - Ha requisito cobrindo indisponibilidade temporaria do
  endpoint de telemetria durante uma janela de captura, com
  comportamento fail-open explicito (nunca bloqueia a sessao)? [Cobertura,
  Spec §Edge Cases item 4 + FR-007] {auto} — Edge Case 4: "a captura falha
  de forma silenciosa para aquela janela (nunca bloqueia a sessao do
  operador) e a lacuna fica visivel como dado ausente, nao como zero".
- [x] CHK026 - O design evita atribuicao cruzada de consumo entre
  processos/sessoes concorrentes (um processo sendo creditado com o
  consumo de outro)? [Threat Modeling / Integridade, research.md
  Decision 2 + Decision 5] {auto} — Decision 2 rejeita `session_id` como
  identidade justamente por esse risco documentado ("label ja observado
  apontando para outra sessao/projeto"); Decision 5 resolve estados
  indeterminados sempre para "nao captura" (subconta, nunca superconta).

## Logging e Auditabilidade

- [x] CHK027 - O contrato do hook garante que nenhum dado de consumo
  vaza para stdout/stderr/logs do harness? [Logging, contracts/hook-loose-usage.md
  §Saida] {auto} — "stdout: SEMPRE vazio | stderr: SEMPRE vazio (nenhuma
  falha e reportada ao operador) | exit: SEMPRE 0".
- [x] CHK028 - O trade-off de "falha sempre silenciosa, zero
  auditabilidade de falhas sistemicas do hook" e uma decisao deliberada e
  consistente com o precedente ja aceito no codebase (nao uma omissao
  desta feature)? [Consistencia / Risco aceito, contracts/hook-loose-usage.md
  §Saida "REGRA DURA (herdada do molde)"] {auto} — herda literalmente a
  mesma regra de `posttooluse-tool-call-tick.sh` (hook `PostToolUse` ja
  em producao com o mesmo contrato de silencio total); nao e um padrao
  novo introduzido por esta feature.

## Ciclo de Vida dos Dados (retencao/compliance)

- [x] CHK029 - Existe politica declarada de retencao/expurgo para os
  segmentos do sidecar (`~/.claude/cstk/loose-usage/<process_key>/seg-*/`)
  e para as linhas correspondentes em `loose_usage`, dado que a captura
  roda continuamente sem limite superior de volume declarado? [Gap,
  Compliance] {auto} — mesma raiz de CHK002 (requirements.md), vista pelo
  angulo de seguranca de dados: crescimento local ilimitado de um
  diretorio que contem `project_path` (path absoluto do operador) e um
  risco de superficie de dados que cresce sem controle declarado, nao
  apenas uma questao de completude funcional. RESOLVIDO pela task 1.1:
  data-model.md §Retencao (CHK002/CHK029) + contracts/cli-usage.md
  §`cstk usage prune`.

## Itens de julgamento humano

- [ ] CHK030 - E aceitavel, em ambiente multi-usuario (ex.: maquina
  compartilhada), que `~/.claude/cstk/loose-usage/` fique sem permissao
  restritiva explicita (ver CHK021), dado que o conteudo e limitado a
  paths de projeto + metricas de custo/token (sem PII, ja garantido por
  CHK019), ou isso deve virar requisito obrigatorio antes de
  `create-tasks`? [Risco, CHK021] {humano}
- [ ] CHK031 - A politica de retencao ausente (CHK002/CHK029) deve ser
  definida AGORA nesta feature (ex.: poda por idade/tamanho no proprio
  `cstk usage`/hook), ou aceita conscientemente como divida tecnica para
  uma iteracao futura, dado o volume estimado baixo ("dezenas por dia",
  plan.md §Scale/Scope)? [Risco, CHK002, CHK029] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]` quando a checagem em si e verificavel mas revela
  ausencia).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- CHK021/CHK029/CHK030/CHK031 sao os achados de seguranca centrais desta
  rodada — ver `## Follow-up` no relatorio da onda.
