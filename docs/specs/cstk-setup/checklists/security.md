# Security Checklist: cstk-setup

**Purpose**: Validar a qualidade dos requisitos de seguranca de `spec.md`
(FR-016 autenticidade, FR-017 escopo global, FR-018 ausencia de override de
catalogo) apos o re-review `owasp-security` que gerou os achados
SEC-01..SEC-07 — 3 corrigidos nesta onda (contrato/data-model), 4
registrados para `create-tasks`.
**Created**: 2026-08-07
**Feature**: [spec.md](../spec.md)

## Autenticacao / Autorizacao

- [x] CHK001 - Ha superficie de autenticacao/autorizacao de usuario nesta feature, e se nao houver, isso esta implicitamente correto (nao e um requisito esquecido)? [AuthN/Z] {auto}
  - Evidencia: `cstk setup` e um subcomando CLI local, sem usuarios/sessoes/tokens — `plan.md` Technical Context nao lista nenhuma dependencia de auth. O requisito mais proximo de "autorizacao" e FR-016 (verificar que o que esta REGISTRADO e de fato o script autorizado do catalogo, nao um substituto), coberto abaixo.

## Protecao de Dados

- [x] CHK002 - Ha algum dado sensivel (segredo/token/credencial) manipulado por esta feature? [Protecao de Dados] {auto}
  - Evidencia: nenhum. As 4 areas leem/escrevem apenas paths locais (`settings.json`, `.mcp.json`, `$HOME/.claude/cstk/config`) sem credenciais. Unico vetor de "supply chain" considerado e a origem do catalogo (FR-018), coberto abaixo.
- [x] CHK003 - Existe requisito explicito proibindo escrita fora do escopo declarado (projeto-alvo), com a unica excecao marcada como tal? [Protecao de Dados, Spec §FR-012, §FR-017] {auto}
  - Evidencia: FR-012 proibe escrita fora do projeto para a area `telemetry`; FR-017 declara EXPLICITAMENTE a unica excecao (`state-backend`, escopo global) com rotulo obrigatorio antes de aplicar, inclusive em `--dry-run` (`quickstart.md` Scenario 16).

## Input Validation

- [x] CHK004 - O requisito de validacao de `--project-path` esta especificado com o gate exato (o que conta como "diretorio valido") e o efeito de falha (exit code, zero escrita)? [Input Validation, Spec §FR-011] {auto}
  - Evidencia: FR-011 + `contracts/cli-setup.md` §Pre-condicoes item 1 (`[ -e "$PATH/.git" ]`, exit 3, "zero escrita").

## Fail-Safe Defaults / Ambiguidade de Verificacao

- [x] CHK005 - Em caso de ambiguidade na verificacao de autenticidade do registro (5a coluna `indeterminate`), o requisito garante fail-closed — nunca reportar `configured`? [Seguranca, Spec §FR-016] {auto}
  - Evidencia: pos-hardening SEC-02 — `data-model.md` invariante I5 mapeia `indeterminate` → `unavailable` explicitamente (nunca `configured`, nunca herda o exit 0/1 da chamada baseline).
- [x] CHK006 - `unavailable` (impossibilidade de verificar) e distinto de `divergent` (confirmacao positiva de subversao), evitando que uma verificacao inconclusiva seja relatada com o mesmo peso de uma deteccao real? [Seguranca, Spec §FR-016] {auto}
  - Evidencia: `data-model.md` invariante I5 reescrita nesta onda distingue as duas classes de ambiguidade e seus destinos no enum fechado, com a justificativa de custo (falso `unavailable`/`divergent` = aviso; falso `configured` = a garantia que a feature existe para eliminar).

## Resistencia a Decoy / Bypass Trivial

- [x] CHK007 - O requisito de autenticidade (FR-016) resiste a uma tentativa barata de satisfazer a verificacao textual sem ser o registro real — ex. uma linha decorativa citando o basename e o fragmento canonico sem ser a atribuicao `"command"`? [Seguranca, Spec §FR-016] {auto}
  - Evidencia: pos-hardening SEC-01 — `contracts/cli-setup.md` §2.3 agora exige o token literal `"command"` na mesma linha; `quickstart.md` Scenario 17 (novo) exercita exatamente esse caso.
  - Residual declarado (nao um gap silencioso): a regra continua sendo co-ocorrencia textual por linha, nao parse estrutural — nao confirma que a linha esta de fato dentro do objeto de hook correto sob `PreToolUse`/`matcher`. Ver CHK019 do checklist `requirements.md` (decisao `{humano}` sobre aceitar esse residual).

## Disponibilidade da Verificacao de Seguranca (nao mascarar o veredito basico)

- [x] CHK008 - Uma extensao de verificacao (`--verify-registration`) que falha em runtime desatualizado (exit 2) preserva o veredito basico dos hooks obrigatorios em vez de o perder/mascarar? [Seguranca, Spec §FR-009, §FR-016] {auto}
  - Evidencia: pos-hardening SEC-03 — `data-model.md` exige 3 chamadas SEPARADAS (baseline nunca combinada com extensoes); `quickstart.md` Scenario 18 (novo) assertaria explicitamente que a chamada baseline roda e retorna exit 0 independente do exit 2 da extensao.

## Escopo Declarado da Verificacao (transparencia)

- [ ] CHK009 - O `summary` final declara explicitamente o escopo real do que foi verificado (so os 3 hooks obrigatorios de `_GH_HOOKS`), evitando que o usuario infira uma garantia mais ampla (ex. sobre outras entradas do `settings.json`)? [Seguranca/Transparencia, Spec §FR-010, §FR-016] {auto} [Gap]
  - Nao satisfeito ainda: este e exatamente o achado **SEC-07** do re-review, registrado em `plan.md` §Re-check de Constitution para virar tarefa explicita no `create-tasks` — nao alterava contrato/data-model, por isso nao foi fechado nesta onda. Destino: `/create-tasks`.

## Least Privilege / Superficie de Escrita

- [x] CHK010 - A feature delega toda escrita a comandos ja existentes e dedicados, sem implementar uma segunda via de escrita em `setup.sh`? [Seguranca] {auto}
  - Evidencia: `plan.md` Summary — "`cli/lib/setup.sh` e uma camada de orquestracao pura... Nao implementa nenhuma deteccao nem nenhuma escrita propria".

## Confused Deputy (resolucao de path do MCP)

- [x] CHK011 - A verificacao de autenticidade do MCP evita falso-positivo entre as camadas legitimas de resolucao de path, sem abrir brecha para aceitar um path arbitrario como legitimo? [Seguranca, Spec §FR-016] {auto}
  - Evidencia: `contracts/cli-setup.md` §4.1 enumera as 3 camadas aceitas de `_mcp_runtime_script_path` (PATH / repo / catalogo instalado) com justificativa de por que aceitar o conjunto (evita `divergent` espurio em maquina de dev) sem aceitar qualquer path fora dele.
- [ ] CHK012 - Os "paths candidatos" aceitos (item acima) sao restritos a caminhos com o sufixo esperado (`/skills/agente-00c-runtime/scripts/mcp-launch.sh`) **e** que de fato existem em disco no momento da verificacao, ou a regra e mais permissiva do que isso? [Seguranca, Spec §FR-016] {auto} [Gap]
  - Nao satisfeito ainda: este e o achado **SEC-05** do re-review — a redacao atual de §4.1 (candidato 1: `command -v mcp-launch.sh` via PATH) e mais ampla do que "sufixo esperado + existente em disco", registrado em `plan.md` para virar tarefa explicita no `create-tasks`, sem impacto no contrato aditivo desta onda (`_mcp_registration_status` continua **[PROPOSTA]**, ainda nao implementada).

## Tratamento de Resposta Vazia/Indeterminada

- [ ] CHK013 - Uma resposta vazia de `_mcp_registration_status` (stdout sem nenhuma das 3 palavras esperadas) e tratada como indeterminado, nunca como uma das respostas validas por omissao? [Seguranca, Spec §FR-016] {auto} [Gap]
  - Nao satisfeito ainda: achado **SEC-06** do re-review, mesma classe do SEC-02 (fail-open por ausencia de mapeamento explicito) mas para o helper de MCP em vez do de hooks; `contracts/cli-setup.md` §4.1 hoje so enumera 3 saidas possiveis sem declarar o que fazer se a saida NAO for nenhuma delas. Registrado para `create-tasks`.

## Auditabilidade / Rastreabilidade

- [x] CHK014 - A ausencia de persistencia (FR-013 proibe flag de "setup ja rodou") compromete a capacidade de auditar depois o que uma execucao concluiu? [Auditabilidade, Spec §FR-013, §FR-010] {auto}
  - Evidencia: e uma escolha deliberada (idempotencia por re-checagem viva, nao por estado persistido) — FR-010 garante que o `SetupRunSummary` e sempre impresso na propria execucao; nao ha promessa de log persistido em `spec.md`, entao a ausencia nao e um requisito quebrado, apenas um limite conhecido do design (CLI stateless).

## Secure Defaults

- [x] CHK015 - O default nao-interativo (`--yes`) evita aplicar a escolha de maior superficie/privacidade por padrao, quando existe uma alternativa mais conservadora? [Seguranca, Spec §FR-008] {auto}
  - Evidencia: `data-model.md` `loose_usage_choice` default em `--yes` = `skip` — unica area cujo default e "nao aplicar" (`plan.md` §Analise Principio IV), preservando o opt-in explicito ja existente de `--with-loose-usage`.

## Decisao do Dono do Produto

- [ ] CHK016 - O escopo de auditoria declarado no summary (uma vez que SEC-07 seja corrigido) deve incluir tambem uma varredura best-effort de OUTRAS entradas do `settings.json`/`.mcp.json` fora das 3 obrigatorias, ou permanece deliberadamente limitado aos 3 hooks de `_GH_HOOKS`? [Risco/Escopo] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- 3 Gaps (CHK009/SEC-07, CHK012/SEC-05, CHK013/SEC-06) tem destino ja registrado: `/create-tasks` deve consumi-los como tarefas explicitas — nao sao debito silencioso, so nao alteravam contrato/data-model o suficiente para justificar fechar nesta mesma onda.
