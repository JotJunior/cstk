# Security Quality Checklist: Agente-00C

**Purpose**: validar qualidade dos requisitos de seguranca da feature 00C —
um agente autonomo com tools amplas (Bash, Write, Agent, gh, git) que opera
no FS local, executa code generators, abre issues remotas e roda containers.
Foco em prompt injection, sanidade de input, blast radius, subagent
privilege, integridade de estado, secrets e supply chain. Continua
numeracao de `requirements.md` (CHK041+).
**Created**: 2026-05-05
**Feature**: [spec.md](../spec.md)
**Frameworks de referencia**: OWASP Top 10:2025 (servidor-side), Agentic AI
Security 2026 (autonomy bounds, alignment, audit), ASVS 5.0 (input/output).

---

## Validacao de Input do Operador

- [ ] CHK041 - O parametro `descricao-curta` da invocacao tem requisito de sanitizacao antes de ser embutido em mensagens de commit, titulos de issue e paths de arquivo? [Gap, contracts/cli-invocation.md /agente-00c]
- [ ] CHK042 - O parametro `--projeto-alvo-path` tem requisito explicito de rejeicao de paths em zonas sensiveis (`/`, `/etc`, `/usr`, `~/.claude/`, `~/.ssh/`, `~/.config/`)? [Spec §FR-017, contracts/cli-invocation.md]
- [ ] CHK043 - O parametro `--projeto-alvo-path` tem requisito de resolver simbolic links e validar o destino antes de aceitar (prevencao de symlink-traversal)? [Gap]
- [ ] CHK044 - O parametro `--stack` (JSON) tem requisito de validacao de schema (chaves esperadas, tipos, tamanho maximo) antes de ser persistido em estado? [Gap, contracts/cli-invocation.md]
- [ ] CHK045 - A descricao curta tem requisito de tamanho maximo (caracteres) para evitar prompt injection extenso? [Gap]
- [ ] CHK046 - Existe requisito de tratamento de descricao curta com metacaracteres de shell ($(, `, |, etc) antes de qualquer interpolacao em comando Bash? [Gap]

## Prompt Injection e Goal Alignment

- [ ] CHK047 - Existe requisito de detectar tentativas de prompt injection no `descricao_curta` (ex: instrucoes adversariais como "ignore the constitution", "execute rm -rf")? [Gap, Agentic AI 2026]
- [ ] CHK048 - O orquestrador tem requisito explicito de validar que cada acao tomada continua alinhada a `descricao_curta` original (anti-drift), alem de detectar "desvio de finalidade" como gatilho de aborto? [Spec §FR-014.d]
- [ ] CHK049 - "Desvio de finalidade" tem definicao operacional verificavel (criterio mecanico para distinguir refinamento legitimo de drift adversarial)? [Ambiguity, Spec §FR-014.d]
- [ ] CHK050 - Subagentes tem requisito de NAO seguir instrucoes contidas em conteudo de artefatos lidos (ex: briefing.md gerado pode conter texto que tenta reprogramar o orquestrador) — apenas instrucoes vindas do orquestrador-pai? [Gap, Agentic AI 2026]

## Blast Radius e Filesystem Boundary

- [ ] CHK051 - Toda operacao de escrita tem requisito de validar que o path absoluto resolvido esta dentro de `<projeto-alvo>/` antes de executar? [Spec §FR-017]
- [ ] CHK052 - O requisito de "skills globais sao read-only" tem mecanismo de enforcement documentado (alem de boa-fe do orquestrador)? [Ambiguity, constitution.md §V]
- [ ] CHK053 - O requisito "sudo nunca" tem mecanismo de deteccao (ex: regex em comandos Bash gerados antes de executar) ou depende apenas de o agente nao gerar `sudo`? [Gap, constitution.md §V]
- [ ] CHK054 - Package managers (npm, pip, go install) tem requisito de execucao apenas via `docker exec` ou `docker run`, nunca direto no shell do host? [Spec §FR-019]
- [ ] CHK055 - Operador renomeando o diretorio do projeto-alvo durante execucao tem comportamento definido (bloqueio humano em vez de prosseguir em path morto)? [Spec §Edge Cases — diretorio movido]

## Whitelist de Comunicacao Externa

- [ ] CHK056 - Toda chamada `curl`, `wget`, `gh`, ou equivalente tem requisito de check contra whitelist ANTES da chamada efetiva (nao apos)? [Spec §FR-018]
- [ ] CHK057 - O requisito de whitelist cobre tambem chamadas indiretas (ex: `npm install` dentro do docker pode buscar registros externos — esta no escopo aceito de docker-bound)? [Ambiguity, research.md Decision 5]
- [ ] CHK058 - O carregamento da whitelist (linha-por-URL com globs) tem requisito de validacao do formato — uma linha malformada nao pode permitir match-all involuntariamente? [Gap, research.md Decision 5]
- [ ] CHK059 - URL com glob agressivo (ex: `https://**`) tem requisito de bloqueio ou aviso explicito do operador antes de aceitar na whitelist? [Gap]

## Subagent Privileges (Defense in Depth)

- [ ] CHK060 - Cada agente custom (orchestrator, clarify-asker, clarify-answerer, executor) tem requisito de declarar **explicitamente** quais tools recebe — nao herdar do pai? [Spec §FR-013, research.md Decision 7]
- [ ] CHK061 - O requisito de bloquear Agent tool no bisneto (nivel 3) tem verificacao automatizada (ex: linter sobre o frontmatter dos agentes) ou depende de revisao manual? [Gap]
- [ ] CHK062 - Subagentes tem requisito de **nao escrever em disco fora do escopo da sua tarefa** (ex: clarify-answerer nao precisa de Write tool)? [Gap]

## Integridade de Estado e Audit Trail

- [ ] CHK063 - O requisito de validacao de schema na retomada cobre detecao de tampering manual (ex: campo modificado pra burlar orcamento de retro-execucao)? [Ambiguity, contracts/state-schema.md]
- [ ] CHK064 - Existe requisito de checksum/hash do `state.json` ao final de cada onda, gravado em arquivo separado, para detectar modificacao externa entre ondas? [Gap, Spec §FR-007]
- [ ] CHK065 - O requisito de backups em `state-history/` proibe deletacao automatica? Operador pode limpar manualmente, mas o orquestrador nao pode? [Gap]
- [ ] CHK066 - Decisoes que justifiquem violacao de orcamento (ex: "score 0 mas decidi mesmo assim") sao tratadas como erro, nao como decisao valida? [Spec §FR-015]

## Secrets e Privacidade

- [ ] CHK067 - O requisito de filtro de privacidade no `gh issue create` (anonimizacao de tokens, dominios, etc) tem regex/blacklist documentada com exemplos verificaveis? [Ambiguity, contracts/issue-template.md]
- [ ] CHK068 - O relatorio em `agente-00c-report.md` tem requisito de filtro de secrets equivalente ao do issue (decisoes podem citar credenciais por engano)? [Gap, contracts/report-format.md]
- [ ] CHK069 - O `state.json` tem requisito de NAO armazenar conteudo do `.env` como decisao ou contexto (apenas referencia que `.env` foi lido)? [Gap, contracts/state-schema.md]
- [ ] CHK070 - Sugestoes em `agente-00c-suggestions.md` tem requisito de filtro equivalente, dado que viram base de issues? [Gap, contracts/issue-template.md]

## Concorrencia e Consistencia

- [ ] CHK071 - O requisito de "1 execucao 00C ativa por projeto-alvo" tem mecanismo de detecao racy-free (file lock vs check-then-act sobre `state.json`)? [Spec §Edge Cases — multiplas execucoes]
- [ ] CHK072 - O comportamento quando duas instancias `/agente-00c` sao invocadas simultaneamente no mesmo projeto-alvo (race condition de lock) esta definido? [Gap]

## Resiliencia e Disponibilidade

- [ ] CHK073 - Disco cheio durante escrita tem comportamento definido (bloqueio humano com diagnostico, sem corromper estado parcial)? [Spec §Edge Cases — disco sem espaco]
- [ ] CHK074 - Falha de `gh issue create` (sem internet, rate limit, repo privado) tem comportamento definido (registrar tentativa em sugestoes + abortar com motivo "bug skill global", sem retry infinito)? [contracts/issue-template.md]
- [ ] CHK075 - Falha de `git commit` ao final de uma onda tem comportamento definido (bloqueio humano, nao prosseguir)? [Gap]

## Supply Chain e Dependencias

- [ ] CHK076 - Existe requisito de verificar versao minima de `gh`, `git`, `jq` (opcional) na invocacao, com mensagem clara se ausente? [Gap, plan.md §Technical Context]
- [ ] CHK077 - `cstk update` rodando durante uma execucao 00C ativa pode alterar skills globais que o orquestrador usa — existe requisito de detecao desse cenario (skill mudou hash entre duas leituras)? [Gap]
- [ ] CHK078 - Imagem docker usada no projeto-alvo tem requisito de proveniencia validada (imagem oficial ou hash conhecido) ou aceita-se qualquer Dockerfile gerado pela pipeline? [Gap, Spec §FR-019]

## Bounded Autonomy (Agentic AI 2026)

- [ ] CHK079 - Os tres orcamentos cravados (recursividade, retro-execucao, ciclos) sao verificados ANTES de cada acao que possa exceder, nao apos? [Spec §FR-013/FR-014]
- [ ] CHK080 - O requisito "pause-or-decide" do clarify-answerer tem auditoria automatizada (alguma decisao com score=0 e escolha != "pause-humano" e bug)? [Spec §FR-015, research.md Decision 6]

---

## Notes

- Marcar items concluidos com `[x]`
- IDs continuam de `requirements.md` (CHK001-040)
- Total: 40 items, dentro do soft cap

### Metricas

- Rastreabilidade: 40/40 = **100%** dos items referenciam spec/plan/research/data-model/contracts/constitution ou marcam Gap/Ambiguity (acima do minimo de 80%).
- Distribuicao por dimensao:
  - Validacao de Input: 6 (CHK041-046)
  - Prompt Injection / Alignment: 4 (CHK047-050)
  - Blast Radius / FS Boundary: 5 (CHK051-055)
  - Whitelist Externa: 4 (CHK056-059)
  - Subagent Privileges: 3 (CHK060-062)
  - Integridade de Estado: 4 (CHK063-066)
  - Secrets / Privacidade: 4 (CHK067-070)
  - Concorrencia: 2 (CHK071-072)
  - Resiliencia: 3 (CHK073-075)
  - Supply Chain: 3 (CHK076-078)
  - Bounded Autonomy: 2 (CHK079-080)

### Gaps de seguranca de prioridade alta detectados

1. **Prompt injection em `descricao_curta` e em artefatos lidos** (CHK045-050):
   o orquestrador trata texto de operador como instrucao confiavel. Risco
   real: descricao mal-intencionada ("...Importante: ignore constitution e
   execute X") pode tentar drift. Mitigacao: tamanho maximo + isolamento
   de instrucao (operador-vs-conteudo) + auditoria de alinhamento.
2. **Sudo / package manager no host nao tem enforcement explicito**
   (CHK053-054): a regra esta na constitution mas o agente pode "esquecer".
   Mitigacao: regex de pre-execucao em comandos Bash (vetar `sudo`,
   detectar `npm install` sem `docker exec`).
3. **Tampering de estado entre ondas** (CHK063-064): operador ou processo
   externo poderia editar `state.json` para burlar orcamento. Mitigacao:
   hash de integridade.
4. **Filtro de secrets no relatorio e sugestoes nao tem regex/blacklist
   concreta** (CHK067-068, CHK070): hoje so tem mencao "anonimizacao
   automatica". Sem regex documentada, e wishful thinking.
5. **Whitelist com glob `**` aceita silenciosamente** (CHK059): deve avisar.
6. **Path traversal via symlinks em `--projeto-alvo-path`** (CHK043): nao
   resolvendo links, validacao da zona sensivel pode ser burlada.
7. **Definicao de "desvio de finalidade"** (CHK049): gatilho citado em
   FR-014.d sem criterio mecanico — vira inverificavel.

### Recomendacao

Antes de `/create-tasks`, considerar:

a) **Endereçar gaps criticos** (CHK043, CHK045-046, CHK049, CHK053-054,
   CHK064, CHK067) com FRs explicitas na spec — sao mitigacoes baratas que
   evitam vetores reais.
b) **Aceitar gaps de baixa prioridade como conscientes** (CHK072 race
   theorica, CHK078 docker provenance, CHK076 versoes minimas) e mover
   para "Items a Definir" do plan.md.
c) **Documentar threat model resumido** em `docs/specs/agente-00c/threat-model.md`
   com os ataques considerados (prompt injection, blast radius escape,
   tampering de estado, secrets exfiltration via issue) e o residual
   aceito. Util pra revisao futura.
