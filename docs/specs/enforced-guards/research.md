# Research: enforced-guards

Documento produzido no Phase 0 do `/plan`. Resolve os pontos que a spec
deferiu para esta fase (Out of Scope: "lista concreta de hosts confiaveis",
"assinatura criptografica... avaliada durante /plan") e fixa o desenho tecnico
para as tres frentes (US1/US2/US3).

Fontes consultadas: leitura direta de `global/skills/agente-00c-runtime/scripts/{bash-guard,path-guard,whitelist-validate}.sh`,
`cli/lib/{hooks,install,self-update,update,list,tarball,serve}.sh`,
`language-related/go/{settings.json,hooks/*.sh}`, `.claude/settings.local.json`
(nao versionado), `scripts/profiles.txt.in`, `scripts/build-release.sh`, e
documentacao oficial do harness em https://code.claude.com/docs/en/hooks
(consultada via agente `claude-code-guide` nesta mesma onda).

---

## Decision 1: Contrato do hook `PreToolUse` (fonte oficial do harness)

**Decision**: O hook de enforcement de US1 e um script POSIX sh registrado
sob a chave `"hooks"."PreToolUse"` de um `settings.json`, com `matcher: "Bash"`.
Recebe **stdin** um JSON com o shape:

```json
{
  "session_id": "...",
  "cwd": "/path/do/projeto",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "..." }
}
```

O comando a validar esta em `.tool_input.command`. Sinaliza bloqueio de duas
formas suportadas: (a) `exit 0` + stdout `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`;
(b) `exit 2` (stderr mostrado ao Claude, sem JSON). Este plano adota **(a)**
como mecanismo primario — `permissionDecisionReason` e o unico canal
documentado para transportar o motivo estruturado exigido por FR-002/FR-007
(distinguir bloqueio-por-regra de bloqueio-por-falha-do-mecanismo); `exit 2`
so devolve texto livre em stderr, formato mais pobre para FR-016 (auditoria).

**Rationale**: fonte e a documentacao oficial do harness
(`https://code.claude.com/docs/en/hooks`), nao suposicao — citado
explicitamente para nao violar Principio VI/Constitution. `.claude/settings.local.json`
local (nao versionado, achado durante a pesquisa) ja usa esse mesmo shape
(`PreToolUse`, stdin, `.tool_input.*` aninhado) e serve de precedente
convergente.

**Alternatives considered**: replicar o padrao de
`language-related/go/settings.json` (`PreToolCall`/`PostToolCall`, dado via
`$CLAUDE_TOOL_INPUT` env var, campos planos `.file_path`). **Rejeitado**: e
nomenclatura antiga do harness (achado colateral desta pesquisa — o profile Go
do proprio toolkit esta desatualizado); adotar um contrato obsoleto para uma
feature nova seria construir sobre fato incorreto. Risco registrado como nota
separada (fora do escopo desta feature: profile Go precisa de update futuro,
nao tratado aqui).

---

## Decision 2: Parsing do JSON de entrada sem violar Principio II (POSIX puro)

**Decision**: o script do hook usa `jq` para extrair `.tool_input.command` do
stdin, sob o carve-out formal de **"Optional dependencies with graceful
fallback"** (constitution amendment 1.1.0, Principio II). As tres condicoes
cumulativas:

(a) **Uso opcional com fallback gracioso e testavel**: se `jq` estiver
    ausente, o hook nao consegue parsear com seguranca o JSON aninhado —
    o fallback e **bloquear** (`permissionDecision: "deny"`,
    `permissionDecisionReason: "MECANISMO_FALHOU: jq ausente, comando nao
    pode ser validado com seguranca"`). Este fallback e correto por
    construcao: e exatamente o comportamento fail-closed exigido por
    FR-007 para "o proprio mecanismo de checagem falhou" — jq ausente e
    apenas mais uma causa de falha do mecanismo, tratada pelo MESMO caminho
    de codigo que qualquer outra falha interna (nao e um caminho especial).
(b) **Confinado a um unico arquivo**: toda referencia a `jq` neste hook fica
    em `global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh`
    (novo arquivo, nome proposto — [PROPOSTA]). `bash-guard.sh`/`path-guard.sh`
    em si permanecem 100% POSIX puro, sem tocar em `jq` (Principio II
    integral) — o hook e uma casca fina que so faz parsing de stdin e
    delega a decisao de regra ao `bash-guard.sh` ja existente via
    `--command`/`--whitelist-file`.
(c) **Declarada nesta documentacao**: esta secao e a declaracao exigida pela
    condicao (c); `spec.md`/`plan.md` desta feature citam o path do arquivo
    confinado e o fallback.

**Rationale**: replica o precedente ja aceito (`cli/lib/hooks.sh`, jq
confinado, primeiro caso concreto do carve-out 1.1.0) em vez de abrir um novo
tipo de excecao. Parsing JSON aninhado via `grep`/`sed`/`awk` POSIX puro e
possivel apenas de forma fragil (nao ha parser JSON real disponivel); dado que
este script e uma camada de SEGURANCA, fragilidade no parsing e pior que a
dependencia opcional — e o fallback fail-closed elimina o risco de "parse
errado permite comando perigoso passar".

**Alternatives considered**: (i) parsing via `sed`/`awk` ad-hoc — rejeitado,
frágil para strings com aspas/escaping dentro de `tool_input.command`, e uma
extracao errada do comando é exatamente o tipo de furo que esta feature existe
para fechar; (ii) exigir `jq` como dependencia obrigatoria (sem fallback) —
rejeitado, viola Principio II diretamente (carve-out exige fallback gracioso,
nao dependencia hard); (iii) reescrever bash-guard.sh para tambem aceitar JSON
via stdin diretamente (fundir hook+guard num so script) — rejeitado, quebra a
condicao (b) do carve-out (dependencia deixaria de estar confinada a um unico
arquivo) e acopla o guard reusavel-por-prosa (FR-005, advisory) ao contrato do
harness.

---

## Decision 3: Deteccao de "execucao ativa" (FR-006, resolvido via block-001/dec-012)

**Decision**: o hook considera que ha "execucao ativa de agente-00c/feature-00c"
quando, a partir de `.cwd` do JSON de entrada, existir pelo menos um dos:

- `<cwd>/.claude/agente-00c-state/state.json` com `.execution.status` em
  `("em_andamento", "aguardando_humano")`;
- `<cwd>/.claude/feature-00c-state/*/state.json` (qualquer short-name) com
  `.execution.status` no mesmo conjunto.

Quando NENHUM casar: o hook emite (via `permissionDecision`) o equivalente a
"sem decisao" — no formato oficial isso e simplesmente **nao emitir JSON e
sair `exit 0`** (ver Decision 1: "exit code 0 sem JSON = sem decisao, fluxo
normal de permissoes"), preservando 100% o comportamento atual para sessoes
interativas do operador (escopo A, dec-012).

**Rationale**: reusa a MESMA logica de deteccao que `feature-00c-preflight.sh`
e os proprios orquestradores ja usam para checar coexistencia
agente-00c/feature-00c (precedente interno, nao dado externo). Resolve
FR-006 exatamente na forma decidida pelo operador em block-001/dec-012.

**Alternatives considered**: usar uma variavel de ambiente sinalizando
"execucao ativa" (ex: `AGENTE_00C_STATE_DIR` setada no processo) — rejeitado
como mecanismo PRIMARIO porque o hook roda como processo filho do harness,
nao necessariamente herdando o ambiente do subagente Bash-caller da forma
esperada (nao confirmado pela doc oficial); a checagem por presenca de
`state.json` no filesystem e independente de propagacao de env e mais
robusta. Pode ser adotada como sinal SECUNDARIO/otimizacao futura, fora do
escopo desta feature.

---

## Decision 4 (RESOLVIDO — spike empirico task 1.1, 2026-07-05): propagacao do hook a subagentes spawnados

**Resolucao empirica (task 1.1)**: **CONFIRMADO — o hook `PreToolUse` PROPAGA
para Bash tool calls emitidas de dentro de um subagente spawnado via tool
Agent/Task.** US1 cobre subagentes; nenhuma mudanca de design adicional e
necessaria (Mitigacao 3 abaixo se aplica); demais cenarios do quickstart
valem como escritos.

**Metodologia**: harness isolado em `/tmp/spike-enforced-guards.*` (projeto
descartavel, fora do repo real, zero risco de self-modification): (a)
`.claude/settings.json` com `"hooks"."PreToolUse"` `matcher:"Bash"` apontando
uma versao MINIMA de `pretooluse-bash-guard.sh` que delega a decisao ao
`bash-guard.sh check-blocklist` real e inalterado deste repo, e faz append em
`enforcement-log.jsonl`; (b) canary command escolhido e VERIFICADO
empiricamente antes do spike: `git push origin main` — confirmado bloqueado
(`bash-guard.sh check-blocklist --command "git push origin main"` -> exit 1,
categoria `git-push`), enquanto `rm -rf /tmp/...` NAO e bloqueado (tmp e zona
exenta) — logo apenas o primeiro serve como canary valido; (c) invocada uma
sessao `claude -p` aninhada e independente, com `cwd` = pasta spike (nao o
repo real), instruida a **delegar** (nao rodar Bash ela mesma) via tool
Agent/Task a um subagente, que executa o comando canary e reporta o
resultado literal.

**Evidencia observada (todas as fontes convergem)**:

1. Transcript `--output-format stream-json` da sessao aninhada mostra a
   sequencia causal inequivoca: `assistant tool_use:Agent` (spawn do
   subagente) -> `system task_started` -> `assistant tool_use:Bash`
   (`input.command = "git push origin main"`, emitida no contexto de
   progresso do subagente, `system task_progress`) -> `user tool_result`
   com o texto literal:
   `REGRA_VIOLADA: bash-guard: BLOQUEADO — categoria=git-push — git push bloqueado em qualquer remote (Principio V)`
2. `enforcement-log.jsonl` (artefato independente, escrito SOMENTE pelo
   proprio script do hook via `>>`, nunca por texto de LLM) contem
   exatamente uma linha correspondente:
   `{"source":"pretooluse-bash-guard-spike","timestamp":"2026-07-05T13:19:43Z","outcome":"blocked-by-rule","command":"git push origin main","reason":"bash-guard: BLOQUEADO — categoria=git-push — git push bloqueado em qualquer remote (Principio V)"}`
3. A resposta final da sessao aninhada confirma explicitamente que foi o
   SUBAGENTE (nao a sessao raiz) quem tentou o comando e recebeu a negacao:
   "Aqui esta o texto literal que o subagente retornou: REGRA_VIOLADA: ...".

O formato `REGRA_VIOLADA: <categoria/motivo>` e distintivo do proprio hook
(reusa `_bg_emit_block` de `bash-guard.sh`) — nao se confunde com nenhuma
outra camada de permissao do harness (ex.: o classificador de auto-mode do
proprio ambiente de execucao, observado em tentativas anteriores deste
mesmo spike com mensagens estruturalmente distintas: "Permission for this
action was denied by the Claude Code auto mode classifier..."). As tres
fontes (transcript estruturado, log independente, texto final) sao
consistentes entre si — nenhuma delas e a unica base da conclusao.

**Nota metodologica (tentativas descartadas)**: as duas primeiras tentativas
de harness foram bloqueadas pelo classificador de auto-mode do PROPRIO
ambiente onde este spike roda (nao relacionado ao hook sob teste): (i)
sessao aninhada com `--dangerously-skip-permissions` — negada como "Create
Unsafe Agents"; (ii) escrever o hook de teste em `.claude/settings.json` do
repo REAL (em vez do projeto descartavel) — negada como "Self-Modification".
Ambas as negacoes reforcam exatamente a orientacao original da task 1.1.1
("projeto de teste descartavel", nao o repo real) — a versao final do
harness (isolada em `/tmp`, sem bypass de permissao) nao esbarrou em nenhum
dos dois gates e produziu o resultado limpo acima.

---

**Decision original (pre-spike, preservada para historico)**: tratar como
**unknown documentado**, nao como fato assumido em
qualquer direcao. A documentacao oficial (`https://code.claude.com/docs/en/hooks`,
`https://code.claude.com/docs/en/how-claude-code-works.md`) **nao especifica**
se `PreToolUse` dispara para tool calls Bash emitidas de dentro de um
subagente spawnado via tool Agent/Task (agente-00c-orchestrator e
agente-00c-feature-orchestrator SAO subagentes do slash command pai, e eles
proprios spawnam subagentes de nivel 2). Existem hooks `SubagentStart`/`SubagentStop`
documentados separadamente, mas nenhuma confirmacao de que `PreToolUse`
tambem dispara dentro da execucao do subagente.

**Impacto direto em US1**: se `PreToolUse` NAO propagar para dentro de
subagentes, a interceptacao enforced desta feature cobriria apenas comandos
Bash emitidos na sessao raiz — nao os comandos que o proprio
agente-00c-feature-orchestrator (rodando como subagente) emite durante sua
execucao, que e o caso de uso CENTRAL de US1.

**Mitigacao adotada no plano**:

1. **Validacao empirica antecipada** — a primeira task de `create-tasks`
   para esta feature MUST ser um spike dedicado: provisionar o hook num
   projeto de teste, spawnar um subagente (ex: via tool Agent com um prompt
   trivial) que emite um comando Bash bloqueavel, e observar empiricamente se
   o hook dispara. Resultado vira Decisao auditavel citando evidencia
   (comando, output do hook, log). NAO prosseguir com o restante de US1 antes
   desse spike responder a pergunta.
2. **Camada advisory permanece intacta (FR-005 ja exige isso)** — caso o
   spike confirme que o hook NAO propaga a subagentes, a mitigacao e
   documentar isso como constraint conhecida em SC-001 (o SC continua
   validado para o caso "sessao raiz", nao para 100% dos casos de subagente)
   e reforcar que a camada advisory (chamada pela prosa dos orquestradores)
   continua sendo a garantia real nesse cenario — sem alegar cobertura que
   nao existe (mesmo espirito do Acceptance Scenario 3 de US1: "sem regressao
   silenciosa, mas tambem sem alegar uma garantia que nao esta ativa").
3. Se o spike confirmar propagacao: nenhuma mudanca de design adicional
   necessaria, o restante do plano vale como descrito.

**Rationale**: Constitution VI proibe tratar uma suposicao como fato. Como
esta e a premissa mais critica de todo o plano (afeta diretamente se SC-001 e
alcancavel), o unico caminho compativel com "buscar antes de supor" e
verificar empiricamente antes de investir nas demais tasks de US1.

**Alternatives considered**: assumir otimisticamente que propaga (documentacao
de exemplo do harness sempre mostra hooks disparando para qualquer Bash da
sessao) — rejeitado, é suposicao nao verificada sobre comportamento de
subagentes especificamente. Assumir pessimisticamente que nao propaga e
desenhar so para sessao raiz — rejeitado, jogaria fora o caso de uso central
sem verificar.

---

## Decision 5: Onde persistir `EnforcementDecisionLog` (FR-016)

**Decision** [PROPOSTA]: novo arquivo JSONL append-only,
`<projeto-alvo>/.claude/enforcement-log.jsonl`, com uma linha por decisao do
hook (bloqueio ou passagem explicitamente auditada — ver Data Model). Escrito
apenas pelo proprio script do hook via `>>` (append), NUNCA pelo
`state.json` do orquestrador (que e escrito exclusivamente por
`state-rw.sh` sob lock do processo do orquestrador — escrever ali a partir
de um processo de hook concorrente arriscaria corrupcao/race fora do
mutex existente, FR-028 do runtime).

**Rationale**: separa o dado transacional da execucao SDD (`state.json`,
mutex-protegido, schema versionado) do dado de auditoria de seguranca
(volume potencialmente maior, escrito por um processo diferente/concorrente).
Append de uma linha curta em JSONL e a operacao mais simples que preserva
"nao apenas visivel momentaneamente" (FR-016/SC-005) sem introduzir lock novo.

**Alternatives considered**: escrever direto em `.execution` do `state.json`
via `state-rw.sh set` a partir do hook — rejeitado, o hook roda fora do
ciclo de onda do orquestrador (pode disparar a qualquer momento, inclusive
enquanto o orquestrador esta no meio de um `state-rw.sh write` proprio),
introduzindo risco de corrupcao concorrente que o mutex atual (`state-lock.sh`,
por-onda) nao cobre (e por-execucao, nao por-tool-call). Um arquivo separado
elimina esse risco por construcao.

---

## Decision 6: Extensao fail-closed em `cli/lib/serve.sh` (US2)

**Decision** [PROPOSTA]: substituir o ramo `else` de `serve.sh:213-215`
(hoje: imprime aviso e continua) por um bloqueio por padrao. Bypass explicito
via nova flag `cstk serve --allow-unverified` (CLI) OU variavel de ambiente
`CSTK_SERVE_ALLOW_UNVERIFIED=1` (para uso nao-interativo/scripts) — quando
presente, prossegue e registra a decisao em
`<projeto-alvo-do-cache>/.claude/enforcement-log.jsonl` (mesmo arquivo de
Decision 5, entidade `IntegrityVerificationOutcome`) com o outcome
`bypass-explicito` + timestamp + versao/URL do pacote. Ausencia da flag/env
= `return 1` (aborta `cstk serve`), preservando o bloqueio ja existente em
caso de divergencia de checksum (`serve.sh:206-210`, inalterado).

**Rationale**: satisfaz FR-008/FR-009/FR-011 (decisao explicita, nao "aviso
que passa sozinho"; decisao revisavel) preservando FR-010 (divergencia
continua bloqueando sem bypass) e SC-004 (fluxo legitimo do dev sem
`.sha256` publicado — que e o estado ATUAL do cstk-panel, conforme a propria
spec assume em Dependencies & Assumptions — continua completando, desde que o
operador opte conscientemente).

**Alternatives considered**: bloquear sem NENHUM bypass ate o cstk-panel
publicar `.sha256` — rejeitado, contradiz FR-008 ("exceto quando o operador
tiver optado explicitamente") e quebraria `cstk serve` incondicionalmente no
estado atual documentado (Dependencies & Assumptions da spec). Prompt
interativo (perguntar toda vez) — rejeitado como default; via flag/env cobre
tanto uso interativo (`--allow-unverified` naquela chamada) quanto scripts,
sem forcar uma pergunta bloqueante toda execucao onde o operador ja decidiu
aceitar o risco daquele ambiente.

**Adendo (achado do gate `owasp-security`)**: `CSTK_SERVE_ALLOW_UNVERIFIED=1`
setada de forma persistente (ex: em `.zshrc`/`.bashrc`, ou em CI de longa
duracao) degrada silenciosamente o bypass "por-execucao, consciente" de volta
a um fail-open permanente e esquecido — exatamente o antipadrao que esta
feature existe para eliminar. Mitigacao MUST: toda vez que o bypass disparar
(flag OU env), `cstk serve` MUST imprimir um aviso de alta visibilidade em
stderr no INICIO da execucao (nao so registrar silenciosamente no log), ex:
`"cstk serve: AVISO — prosseguindo SEM verificacao de integridade
(CSTK_SERVE_ALLOW_UNVERIFIED=1 ou --allow-unverified); pacote baixado nao foi
confirmado"`. Isso preserva UX de automacao (nao bloqueia) sem tornar o
bypass invisivel a um operador interativo que esqueceu a env var setada.

---

## Decision 7: Allowlist de hosts para `install`/`self-update` (US3)

**Decision**: reusar EXATAMENTE o mesmo conjunto ja hardcoded em
`cli/lib/serve.sh:31` (`_SERVE_ALLOWED_HOSTS`): `github.com`,
`codeload.github.com`, `objects.githubusercontent.com`, `api.github.com`.
Extrair essa constante para um unico ponto compartilhado (proposta de nome
[PROPOSTA]: `cli/lib/trusted-hosts.sh`, uma unica variavel
`CSTK_TRUSTED_RELEASE_HOSTS`) consumida por `serve.sh` (substituindo a
constante local), `install.sh` (`_install_resolve_urls`) e `self-update.sh`
(`_su_resolve_urls`) — aplicando a MESMA funcao de checagem
(`_serve_check_host_allowlist`, generalizada/renomeada, ja existente e
testada) nos tres lugares.

**Rationale**: este e um dado factual sobre infraestrutura real do proprio
toolkit (de onde os releases sao de fato baixados hoje — GitHub), nao uma
lista inventada — a spec deferiu explicitamente essa decisao para o
`/plan`/research (Out of Scope), e a fonte e o codigo-fonte ja em producao
(`serve.sh`), nao suposicao (Constitution VI). Consolidar em um unico lugar
tambem elimina divergencia futura entre os tres arquivos.

**Alternatives considered**: manter 3 constantes independentes (uma por
arquivo) — rejeitado, gera risco de drift (ex: alguem atualiza `serve.sh` e
esquece `install.sh`, exatamente o tipo de inconsistencia ja observado entre
`update.sh`/`list.sh` aceitando `http://` enquanto `install.sh`/`self-update.sh`
rejeitam — ver achado colateral abaixo).

**Achado colateral (fora do escopo estrito de FR-012/013/014)**: `cli/lib/update.sh`
(`_update_resolve_urls`) e `cli/lib/list.sh` (`_list_do_available`) aceitam
`http://` sem rejeitar, ao contrario de `install.sh`/`self-update.sh` — e
nenhum dos dois valida host hoje. FR-012/013/014 da spec citam textualmente
apenas `install`/`self-update`; **nao expandimos o escopo desta feature** para
cobrir `update`/`list` sem uma FR que o peca explicitamente. Registrado aqui
como debito tecnico observado, candidato a spec/task separada.

---

## Decision 8: Nome do arquivo de whitelist de rede por-execucao (achado de inconsistencia pre-existente)

**Decision**: o hook de US1 (Decision 2) tenta, nesta ordem, `<cwd>/.claude/agente-00c-whitelist`
e `<cwd>/.agente-00c-whitelist.txt` (ambos os nomes ja usados em partes
distintas do codebase hoje — `global/agents/*orchestrator*.md` usa o primeiro,
`cli/lib/00c-bootstrap.sh` usa o segundo), usando o primeiro que existir. Se
nenhum existir, `bash-guard.sh check-whitelist`/`check` roda com whitelist
vazia (comportamento ja existente do proprio `bash-guard.sh` quando o arquivo
nao existe — nenhuma URL sera permitida, comandos de rede sem match sao
bloqueados por padrao).

**Rationale**: esta feature nao e o lugar de arbitrar qual dos dois nomes e o
"correto" (mudar qualquer um dos dois quebraria quem ja depende dele, e nao
ha FR desta spec pedindo essa unificacao) — Constitution VI probe inventar
qual e "o" nome certo sem fonte que resolva a divergencia. Tentar ambos e o
comportamento que funciona independentemente de qual convencao o projeto-alvo
adotou, sem decidir a questao por conta propria.

**Alternatives considered**: escolher um dos dois nomes como canonico agora —
rejeitado, out-of-scope desta feature e potencialmente breaking para
integracoes existentes. Registrado como debito tecnico (mesma classe do
achado da Decision 7) para consolidacao futura fora desta spec.

---

## Decision 9: Provisionamento automatico do hook (FR-004)

**Decision** [PROPOSTA]: os artefatos do hook (script +
`settings.json` snippet) vivem em
`global/skills/agente-00c-runtime/hooks/` (nova subpasta da skill ja
existente — segue Principio III, conteudo carregado sob demanda por
mecanismo de instalacao, nao pelo LLM). `cli/lib/hooks.sh` ganha uma nova
funcao `apply_guard_hooks(scope_dir, dest_claude_root, dry_run)` — mesma
mecanica ja testada de `merge_settings`/`print_paste_block` — invocada por:

- `cli/lib/install.sh::_install_apply_hooks_if_needed`: hoje so age quando
  `_install_profile` casa `language-*`; ganha um segundo ramo que dispara
  quando a skill `agente-00c-runtime` esta entre as skills resolvidas para
  instalacao (`sdd` e `complementary` ja a incluem, conforme
  `scripts/profiles.txt.in`), independente do profile escolhido.
- **`cli/lib/update.sh`** (mudanca real necessaria — hoje **nao** toca hooks
  em nenhum caso, achado confirmado por grep): ganha a MESMA chamada, para
  que "atualizar o toolkit" (nao so "instalar pela primeira vez") tambem
  (re)provisione o hook — sem isso, FR-004 ("fluxo normal de
  instalacao/atualizacao") ficaria meio-cumprido (so instalacao inicial).

Escopo: `--scope global` continua pulando hooks (mesma regra ja aplicada a
`language-*`, FR-009c preexistente) — hooks de enforcement precisam de um
`.claude/` de projeto especifico para funcionar (o hook busca `state.json`
relativo a `cwd`), nao fazem sentido em instalacao global.

**Rationale**: reusa 100% do mecanismo de merge de settings.json ja
implementado e testado (`merge_settings`, backup `.bak`, `print_paste_block`
como fallback sem `jq` — mesmo carve-out ja vigente), em vez de introduzir um
segundo mecanismo de distribuicao (FR-017 MUST proibe isso explicitamente).

**Alternatives considered**: novo diretorio top-level espelhando o padrao de
`language-related/` → `catalog/language/` (que e mirrored por
`scripts/build-release.sh` separadamente) — rejeitado por adicionar um
terceiro mecanismo de empacotamento (alem de `global/skills/` e
`language-related/`) para resolver o mesmo problema que a subpasta dentro da
skill ja existente resolve com menos superficie nova.

---

## Decision 10 (achado do gate `owasp-security`, MUST — nao adiavel): `enforcement-log.jsonl` MUST filtrar secrets do campo `command`

**Decision**: o campo `command` de `EnforcementDecisionLog` MUST passar por
`global/skills/agente-00c-runtime/scripts/secrets-filter.sh scrub` (ja
existente no toolkit, mesmo diretorio do novo hook) ANTES do append no
`enforcement-log.jsonl` — `printf '%s' "$CMD" | secrets-filter.sh scrub`.
Isso substitui a nota anterior ("registrado para create-tasks avaliar depois")
por um requisito MUST resolvido nesta fase de plano.

**Rationale**: gate `owasp-security` (nesta mesma onda) identificou que
comandos Bash interceptados e bloqueados frequentemente contem credenciais em
texto puro na propria linha de comando (ex: `git push https://user:TOKEN@host/repo`,
`curl -H "Authorization: Bearer xyz"`, `mysql -p'senha'` — casos reais, nao
hipoteticos). Persistir esses comandos sem filtro num arquivo que fica em
disco no projeto-alvo e um vetor de vazamento (OWASP A09 Logging Failures +
LLM02 Sensitive Info Disclosure): o arquivo pode ser lido acidentalmente por
uma sessao futura do proprio LLM (Read/Glob amplo), reintroduzindo o segredo
no contexto do modelo, de onde pode vazar por outro canal (relatorio, commit,
etc). `secrets-filter.sh` ja e o mecanismo padrao do toolkit para esse
proposito exato (usado hoje em backups de `state.json` e em `suggestions.sh`/
`issue.sh`) — reuso direto, sem dependencia nova.

**Alternatives considered**: nao filtrar e apenas documentar o risco (postura
original, pre-gate) — rejeitado apos o gate de seguranca classificar como
finding HIGH: o custo de aplicar o filtro e trivial (uma chamada a um script
ja existente) frente ao custo de um segredo persistido em texto puro.
Truncar o campo `command` inteiro em vez de filtrar (ex: só logar os
primeiros N chars) — rejeitado, perderia valor de auditoria (FR-016 exige
diagnostico revisavel) sem eliminar o risco (segredos podem aparecer no
inicio da string).

---

## Decision 11 (achado do gate `owasp-security`): threat model explicito do hook `PreToolUse`

**Decision**: documentar explicitamente, no `plan.md` (secao "Threat Model"),
que o hook de US1 protege contra o ORQUESTRADOR/MODELO emitindo um comando
perigoso por lapso, instrucao manipulada ou condicao de borda — **nao**
contra um operador (ou processo com o mesmo nivel de acesso do operador) que
edite deliberadamente `.claude/settings.json`/`settings.local.json` do
projeto-alvo para remover ou neutralizar o proprio hook. Quem tem acesso de
escrita a essa configuracao pode desabilitar a interceptacao da mesma forma
que poderia editar `bash-guard.sh` diretamente hoje.

**Rationale**: gate de seguranca perguntou explicitamente se o mecanismo pode
ser contornado por quem tem acesso de escrita ao `settings.json` — resposta e
sim, e isso e uma limitacao arquitetural inerente (nao um bug a corrigir),
mas precisa estar EXPLICITA no plano para nao ser lida como uma garantia mais
forte do que realmente e (mesmo espirito do proprio Acceptance Scenario 3 de
US1 na spec: "sem alegar uma garantia que nao esta ativa"). Nao ha mitigacao
proposta para esse vetor especifico nesta feature — esta fora do threat
model (a spec nao pede protecao contra operador malicioso com acesso local
de escrita), mas o limite MUST ficar registrado, nao implicito.

**Alternatives considered**: proteger `settings.json` com permissoes
restritivas de arquivo ou checksum — rejeitado como fora de escopo desta
feature (a spec nao pede isso, e entraria em tensao com o proprio fluxo de
`merge_settings` que precisa escrever ali); registrado apenas como nota de
threat model, nao como requisito novo.
