# Histórico da implementação Codex — antes da padronização

Snapshot dos documentos anteriores em 2026-10-02. Não é o backlog vigente.
As afirmações históricas sobre hooks somente pelo manifest foram corrigidas na seção 0.5.0 e não constituem aceite atual.

## Plano anterior

# Piloto feature-00c no Codex

Status: implementação iniciada em `feat/codex-feature-00c`.

Ampliação 0.5.0: concluir as seis entradas de início/retomada/aborto de
feature e projeto, respostas humanas via MCP, inspeção, handoff explícito,
reconciliação de governança/aspectos e instalação por cstk install --cli=codex.
Distribuir o adaptador autocontido no tarball, preservando o fluxo Claude.
Testar JSON/SQLite, processos reais, pacote instalado e MCP pelo app-server.
O instalador não concede confiança de hooks nem cria respostas de opt-in.

## Objetivo e escopo

Ampliação autorizada em 2026-10-02: adicionar entrada de projeto agente-00c,
as 11 etapas completas e modo roadmap usando o mesmo controlador. Implementar
transporte MCP supervisionado; conectar ao host somente após verificar nomes
reais das ferramentas e compatibilidade dos hooks. Certificação nativa e
revisão cruzada continuam critérios separados da implementação/testes locais.

Executar uma feature no Codex com as mesmas etapas, decisões auditáveis,
bloqueios e contratos transacionais usados no Claude. Primeiro alvo: Codex
local. Aplicativo, IDE e cloud exigem validações próprias antes de declarar
suporte. O piloto não publica release nem modifica a instalação global.

## Decisões de arquitetura

- Um repositório; adaptador em `adapters/codex`, runtime em `plugins/cstk`.
- Nenhuma duplicação dos scripts, templates ou regras da pipeline.
- Manter os diretórios de estado existentes nesta fase para compatibilidade
  com descoberta MCP, locks, recall e painel; `.claude` é um layout legado,
  não identidade do executor. Mudança de layout fica fora do piloto.
- `state.json`/`state.db` permanecem canônicos; knowledge.db é índice derivado,
  best-effort. Compartilhar via `CSTK_KNOWLEDGE_DB`, mantendo o default atual.
- Não copiar nem reconciliar automaticamente skills globais editadas.
- Estado deve identificar runtime, modelo observado (nullable) e versão do
  toolkit. A projeção no banco exige migração aditiva e teste de registros
  legados; não inferir o modelo a partir do texto das decisões.
- Implementação: `execution_provenance` no documento canônico, mantido em
  `execution.extra_fields` sob SQLite; projeção JSON nullable em
  `executions.execution_provenance` do knowledge.db schema 16. Ingestão
  filtra segredo e faz upsert pela chave existente.
- Uma execução tem um escritor/orquestrador proprietário. Compartilhar
  precedentes não autoriza dois runtimes a conduzir a mesma execução.
- O adaptador descobre capacidades reais. Não pressupor `ScheduleWakeup`,
  ferramenta `Skill`, nomes MCP fixos ou suporte a seleção de modelos.

## Entregas e critérios de aceite

1. **Fundação (implementada):** entrada feature-00c; preflight read-only,
   runtime resolvido da fonte, briefing e constitution verificados, contexto
   JSON com estágios e caminho do banco. Tests sem acesso à instalação real.
2. **Sessão e auditoria:** bootstrap/retomada via primitivas existentes,
   proveniência persistida e projetada no recall. IDs isolam execuções;
   ingestão repetida não duplica registros; dados legados permanecem legíveis.
3. **Guardas:** adaptar contrato de hooks e demonstrar comando permitido,
   proibido, mecanismo ausente e execução por ferramenta diferente. Ausência
   de enforcement bloqueia modo autônomo. Preflight não certifica hooks.
4. **Pipeline:** consultar precedentes em specify/plan e registrar referências
   utilizadas; conduzir oito etapas com evidências de conclusão, decisões com
   cinco campos, bloqueios humanos e orçamento existentes.
5. **Validação real:** feature pequena em projeto isolado, interrupção e
   retomada, revisão cruzada com Claude e testes de regressão. Só então
   marcar piloto utilizável e ampliar para agente-00c.

## Estratégia de validação

Testes direcionados para cada contrato alterado; suite completa e cobertura
antes de commit/release. Avaliação real do Codex é distinta dos testes de
scripts. Métricas não observadas permanecem null. Uma execução não é
concluída por ter gerado documentos: tarefas e gates precisam de evidências.

## Riscos em aberto

Semântica de hooks e confiança por interface; ferramentas shell agrupadas;
retomada após encerramento da sessão; namespace MCP; roteamento por modelo;
conflitos de escrita; precedentes obsoletos; detecção de skills locais.

## Limites confirmados na documentação oficial

https://learn.chatgpt.com/docs/hooks descreve Bash (inclusive exec_command),
apply_patch, MCP e outras funções locais como caminhos cobertos. Ferramentas
hospedadas ficam fora, write_stdin não passa por novo PreToolUse e falhas
do handler/harness podem deixar a ferramenta continuar. Hooks devem ser
combinados com sandbox; testes de payload não certificam enforcement nativo.
Plugin hooks precisam de revisão e confiança pelo usuário dentro do Codex.
O piloto inicial recusa wrappers de execução ainda não validados e não
declara suporte a execução por code-mode/JavaScript ou sessões interativas.

O bootstrap prepara estado mas não abre onda. O controlador supervisionado
mantém lock durante toda a onda; optins.py exige resposta explícita (I-2), e
consulta/uso de precedentes ficam na auditoria canônica. EOF/SIGTERM não
avança a fase; recuperar dono morto exige pedido explícito com PID observado.
Autonomia permanece bloqueada pelos critérios nativos pendentes; veja
[support-matrix.md](../support-matrix.md).

## Referências

- https://developers.openai.com/plugins/guides/submit-claude-plugin
- https://developers.openai.com/plugins/build/plugins
- `plugins/cstk/agents/agente-00c-feature-orchestrator.md`
- `plugins/cstk/commands/feature-00c.md`
- `cli/lib/recall.sh`

## Evidência inicial

`cstk doctor` detectou 16 skills globais editadas. Elas serão preservadas;
o adaptador inicial lê a fonte versionada deste checkout. Nenhuma instalação,
migração de banco ou execução de feature foi feita por esse diagnóstico.


## Backlog e evidências anteriores

# Tarefas do piloto

- [x] Criar branch isolada e registrar arquitetura e critérios de aceite.
- [x] Criar entrada experimental feature-00c para Codex.
- [x] Implementar preflight read-only usando runtime da fonte e pipeline canônica.
- [x] Resolver knowledge.db compartilhado sem migração ou criação implícita.
- [x] Testar preflight, nomes, dependências, legado e estado existente.
- [x] Empacotar adaptador e runtime em diretório novo, validando resolução fora do checkout.
- [x] Implementar bootstrap e retomada com lock, validação e cleanup (preparação; não abre onda).
- [x] Persistir proveniência por execução e projetar no knowledge.db.
- [x] Implementar hooks e testar envelopes Bash, comandos agrupados, patches e falhas.
- [x] Validar instalação/cache e carregamento dos hooks no app-server real (CODEX_HOME isolado).
- [ ] Revisar/confiar hooks em /hooks e validar cobertura em turno nativo.
- [x] Resolver próxima fase e referências compartilhadas sem avançar estado.
- [x] Implementar controlador de ondas supervisionadas e despacho das fases à sessão atual.
- [x] Implementar captura explícita/idempotente de opt-ins, preservando a guarda I-2.
- [ ] Coletar a resposta real do operador para o piloto (pergunta enviada, sem resposta registrada).
- [x] Registrar consulta e uso de precedentes com IDs compostos de origem.
- [x] Exercitar oito fases em fixtures isoladas JSON/SQLite e interrupção/retomada com SIGTERM/SIGKILL reais.
- [ ] Executar feature isolada semântica por LLM após opt-in/confiança.
- [ ] Concluir revisão cruzada com Claude (tentada; conta em limite semanal).
- [x] Rodar suíte completa e repetir grupos afetados pelo sandbox.
- [x] Publicar matriz de suporte com evidências e limitações explícitas.

Não confundir contexto preparado com execução validada. O piloto
mantém `autonomous_ready=false` até os contratos pendentes serem implementados.

## Validação da fundação

- 30 testes Python passaram (contexto, sessão, hooks, pacote e knowledge.db).
- Suíte shell completa: 4.458 passaram, 10 falharam, zero erros e zero órfãos.
  Nove falhas eram restrições do sandbox: os grupos telemetry-env (13),
  e2e_roadmap_wave (3), parallel-launch (96) e otel-usage (38) passaram
  fora dele. A décima era uso incorreto de assert_exit no teste novo;
  corrigido o teste, state-rw passou nos 104 cenários.
  A suíte completa não foi repetida após essa correção localizada.
- 76 cenários da pipeline compartilhada passaram.
- Cobertura de scripts shell: zero órfãos.
- Frontmatter validado com YAML.safe_load (Ruby).
- O quick_validate.py da skill-creator não rodou: PyYAML ausente no ambiente.
- Nenhuma execução real de pipeline pelo Codex foi validada nesta entrega.

## Continuação — controlador e diagnóstico nativo

- Controlador: lock persistente durante a onda; gates, evidências com SHA-256,
  backlog esgotado, promoção terminal atômica, backups/relatórios filtrados,
  ingestão best-effort e consulta/uso de precedentes auditados.
- Transporte JSONL executa a fase na sessão atual, sem segundo modelo.
  Interrupções suaves fecham sem avanço. Recuperação após SIGKILL exige PID
  observado igual ao dono registrado, comprovadamente morto; origem desconhecida
  ou Claude é recusada. Não há force implícito nem remoção cega de lock.
- Correção encontrada por teste: bloqueios usam o helper canônico count
  --pending-only; o adaptador anterior consultava um status incorreto.
- Codex CLI 0.160.0: marketplace/plugin instalados apenas em CODEX_HOME temporário.
  hooks/list reconheceu PreToolUse/PostToolUse, zero erros/avisos, ambos untrusted.
  Confiança/cobertura real não foram marcadas como validadas.
- Claude: revisão restrita, sem ferramentas/MCP/persistência de sessão, limite
  de US$3. Fora do sandbox retornou: "You've hit your weekly limit".
  Nenhuma revisão foi produzida; a pendência permanece aberta.
- A resposta de opt-in do operador segue pendente. Fixtures não são usadas
  como resposta humana para uma execução real.
- Validação da continuação: 43 testes Python passaram; 194 cenários de recall
  passaram novamente; bytecode/frontmatter validados e git diff --check limpo.
  A suíte shell completa desta sessão anterior permanece registrada acima;
  nesta continuação foi repetido o grupo compartilhado efetivamente alterado.

## Ampliação — projeto e transporte MCP

- [x] Adicionar entrada agente-00c com identidade canônica e estado de projeto.
- [x] Bootstrap sem briefing/constitution prévios; pipeline padrão de 11 fases.
- [x] Coletar os três opt-ins reais pelos helpers compartilhados; I-2 intacto.
- [x] Selecionar modo roadmap e terminar após a terceira fase.
- [x] Aplicar pre-flight de constitution e registrar bloqueio humano com opções canônicas.
- [x] Congelar governança aprovada e recusar drift em retomadas.
- [x] Implementar bridge MCP stdio experimental com proprietário persistente,
  schemas, negociação, erros de ferramentas e fechamento em EOF/SIGTERM.
- [x] Testar pipeline completa de projeto em JSON e SQLite e roadmap completo.
- [x] Gerar pacote 0.3.0 e verificar instalação temporária e descoberta dos hooks.
- [x] Registrar MCP no manifest após validar a identidade real das ferramentas
  e sua compatibilidade com o guard de hooks no host.
- [ ] Validar fase semântica real pela sessão Codex após opt-ins e revisão de hooks.
- [ ] Certificar interfaces App/IDE/code-mode/cloud separadamente.
- [ ] Concluir revisão cruzada com Claude quando a conta permitir.

Correções encontradas por testes: SQLite aceita o objeto de governança de topo
no catch-all, não paths aninhados desconhecidos; bootstrap de projeto prepara
o diretório canônico exigido pelo gate; roadmap é fase sem skill dedicada e
usa a referência root e roadmap-write.sh. Nenhuma instalação global ou banco
de conhecimento real foi alterado nesta ampliação.

Descoberta nativa (Codex CLI 0.160.0, CODEX_HOME temporário): skills/list
retornou `cstk-codex-pilot:agente-00c` e `cstk-codex-pilot:feature-00c`, sem
erros. hooks/list encontrou PreToolUse/PostToolUse, ambos untrusted, sem
erros/avisos. São evidências de carregamento, não de execução por modelo.

Validação final desta ampliação: 52 testes Python passaram em 219,853 s
(log `/tmp/cstk-codex-expanded-final-r2.log`), incluindo pipelines de projeto
completas em JSON/SQLite, roadmap completo, bloqueio de constitution e ciclo
MCP. Compilação Python, frontmatter YAML e git diff --check passaram. A suíte
shell não foi repetida nesta ampliação: os helpers compartilhados não foram
alterados além da fundação registrada acima.

## Integração MCP nativa — 0.4.0

- [x] Manifest portátil plugin.json/mcp.json com resolução nativa de PLUGIN_ROOT.
- [x] Servidor cstk_pipeline conectado; dez ferramentas descobertas e chamadas
  pelo app-server, com pluginId observado.
- [x] Seleção explícita de projeto: servidor inicia sem alvo, fixa o primeiro
  projeto, recusa troca de projeto e troca de execução com onda aberta.
- [x] knowledge_db explícito e preservado em seleções posteriores. O host não
  repassou CSTK_KNOWLEDGE_DB; fixtures usaram somente índice temporário.
- [x] Guard MCP com nome completo, allowlist de ferramentas, schemas e alvo.
- [x] Teste nativo de I-2, lock persistente, erros, pausa e retomada sem avanço.
- [x] AGENTS.md orienta abertura do repositório pelo Codex e encaminha workflows.
- [x] Preparar [aceite nativo](../native-acceptance.md) com arquivos/hashes/comandos.
- [ ] Executar piloto semântico com opt-in real e hooks revisados/confiáveis.
- [ ] Concluir revisão Claude após autenticação: tentativa atual retornou
  Not logged in /login, is_error=true, custo US$0, nenhuma revisão.

Evidências: 56 testes passaram em 225,931 s, incluindo teste opcional nativo
(CSTK_NATIVE_TEST_HOME isolado; log /tmp/cstk-codex-v04-final-tests.log).
Após a correção localizada de persistência do banco na seleção, foram
repetidos os cinco testes do bridge (12,101 s) e o contrato nativo contra o
pacote final (11,976 s), ambos aprovados. YAML/frontmatter, bytecode e
git diff --check passaram. Nenhum helper compartilhado foi alterado nesta
continuação, portanto a suíte shell anterior não foi repetida.

O contrato usa chamadas MCP diretas ao app-server sem turno de modelo;
não dispara hooks e não é certificado de cobertura. hooks/list encontrou
ambos os hooks habilitados/untrusted, sem erros/avisos. Não houve bypass nem
concessão automática de confiança. Nenhuma resposta humana foi presumida.
App/IDE precisam de validação específica; cloud não executa command hooks
locais deste pacote e não pode receber certificação equivalente por estes testes.

## Ciclo de vida e instalação — 0.5.0

- [x] Criar as quatro skills resume/abort, completando as seis entradas nativas
  de feature-00c e agente-00c; encaminhamento correspondente no AGENTS.md.
- [x] Retomar a etapa persistida pela conexão MCP com lock contínuo; retornar
  perguntas pendentes sem abrir onda e aplicar uma resposta real por bloqueio.
- [x] Abortar feature/projeto, com ou sem onda própria, preservando código,
  documentos e histórico; estado terminal atômico JSON/SQLite, backup filtrado,
  relatório, ingestão best-effort, purge explícito e commit condicionado ao opt-in.
- [x] Recusar outro dono vivo, permitir recuperação explícita de PID morto
  observado e tratar estados concluídos/abortados de forma idempotente.
- [x] Transferir execução Claude/legada explicitamente, guardando proveniência
  anterior, identidade, ondas, decisões e respostas de opt-in.
- [x] Reconciliar governança com os dois hashes revisados, fonte do operador,
  decisão e snapshots; inicializar aspectos legados de projeto uma única vez.
- [x] Implementar `cstk install --cli=codex`, com checkout/release verificada,
  Codex CLI nativo, banco configurado no env do MCP e instalação isolável.
- [x] Proteger edits no pacote/cache/hooks, preservar outros plugins/handlers,
  suportar reinstalação e troca de banco, registrar marketplace de raiz estável.
- [x] Distribuir adaptador e helper Python na release; restringir descoberta
  de bootstrap/self-update à CLI externa para não selecionar a CLI do plugin.
- [x] Configurar os dois hooks em CODEX_HOME/hooks.json. O harness 0.160.0
  não listou hooks somente pelo manifest, inclusive em nova consulta da
  instalação 0.4.0; esta constatação corrige a descrição anterior de descoberta.
  Na instalação CSTK os plugin hooks ficam vazios, evitando execução dupla.
  Handlers apontam para pacote imutável por hash e continuam untrusted.
- [x] Verificar instalação nativa: seis skills habilitadas; quinze ferramentas;
  I-2, lock, bloqueio/resposta, resume, aborto, handoff, drift/reconciliação,
  purge e banco configurado exercitados via app-server, sem turno de modelo.

Validação: suíte Python completa com 74 testes (73 passaram, um nativo
opcional foi pulado) em 358,662 s. Após alterações posteriores, os 18 testes
de ciclo de vida passaram em 141,313 s, os seis de instalação passaram em
6,449 s e os dois contratos nativos passaram em 28,270 s. São 81 casos
distintos exercitados entre a suíte e verificações direcionadas.
Logs: `/tmp/cstk-codex-v05-full-tests.log`,
`/tmp/cstk-codex-v05-lifecycle-final.log`,
`/tmp/cstk-codex-v05-installer-hooks-final.log` e
`/tmp/cstk-codex-v05-final-native-r2.log`.

Regressões shell: install (31), build-release (11), self-update (19),
bootstrap/00c-bootstrap (32) e cstk-main (23), todos aprovados. Cobertura:
zero órfãos. Compilação Python, frontmatter das seis skills, sintaxe shell e
git diff --check aprovados. Nenhuma instalação global, autenticação ou banco
real foi modificado; nenhuma release foi publicada.

Instalação de aceite: `/tmp/cstk-codex-v05-final-home`. Relatório de hooks:
`/tmp/cstk-codex-v05-final-hooks-r2.json`, com ambos enabled=true,
trustStatus=untrusted, zero erros/avisos. O registro de hooks na camada user
é intencional e não representa concessão de confiança.

Pendências de homologação: resposta real dos opt-ins do piloto, revisão e
confiança dos hooks, execução semântica real com LLM e revisão cruzada Claude
(última tentativa sem autenticação). App/IDE/cloud exigem validação própria;
roteamento de modelos, scheduler e medição de custo/tokens não são assumidos
no adaptador supervisionado. Essas pendências não foram marcadas como testes
aprovados por fixtures nem por chamadas MCP sem modelo.


## Procedimento de aceite anterior

# Atualização de instalação — 0.5.0

Use `sh cli/cstk install --cli=codex` neste checkout ou
`cstk install --cli=codex` após atualizar a CLI para uma release que contenha
o adaptador. O instalador registra skills/MCP como plugin nativo e mescla os
handlers CSTK em CODEX_HOME/hooks.json. Outros hooks permanecem intactos.
Os comandos apontam para o pacote imutável identificado por hash; as
declarações de hooks do plugin instalado ficam vazias para evitar duplicação.
Nenhuma confiança é concedida pelo instalador. A consulta abaixo deve mostrar
PreToolUse/PostToolUse enabled=true, trustStatus=untrusted antes da revisão:

```sh
python3 adapters/codex/skills/feature-00c/scripts/native_status.py \
  --project /tmp/cstk-codex-v05-final-probe-project \
  --codex-home /tmp/cstk-codex-v05-final-home
```

Abra uma nova sessão Codex usando a instalação e projeto desejados. Em
`/hooks`, revise os dois comandos e os scripts apontados antes de confiar.
Confiança de hooks não substitui os opt-ins reais de cada execução. O teste
nativo de contrato usa RPC sem turno de modelo e não prova cobertura dos hooks.

O diagnóstico final no Codex 0.160.0 não listou hooks somente pelo manifest,
inclusive na instalação 0.4.0. As instruções/evidências anteriores abaixo
são históricas; a configuração do instalador 0.5.0 é a referência vigente.

# Aceite nativo do pacote Codex 0.4.0

Pacote local pronto: `dist/cstk-codex-pilot-v0.4.0-r1`. Instalação isolada:
`/tmp/cstk-codex-native-v04-release-home`. Projeto de diagnóstico:
`/tmp/cstk-codex-native-v04-project`. Nenhuma instalação global foi alterada.

## O que já foi verificado

O Codex CLI 0.160.0 conectou o servidor cstk_pipeline do plugin, expôs dez
ferramentas e executou o contrato pelo app-server: seleção explícita de projeto
e banco temporários, gate I-2 sem respostas, lock entre chamadas, recusa de
troca com onda aberta, pausa e retomada. Respostas dessa verificação são
fixtures identificadas como teste; não são respostas humanas para um piloto.
Chamadas MCP diretas ao app-server não dispararam hooks; não certificam
cobertura em um turno de modelo.

## Definições de hooks disponíveis para revisão

Os dois hooks foram encontrados habilitados e untrusted. Revise
[PreToolUse](../../../../adapters/codex/hooks/pretooluse.py),
[PostToolUse](../../../../adapters/codex/hooks/posttooluse.py) e
[a configuração](../../../../adapters/codex/hooks/hooks.json).

PreToolUse reutiliza a política Bash, confina apply_patch e permite apenas
as ferramentas do servidor cstk_pipeline com argumentos válidos. O MCP
revalida lock, identidade, opt-ins, evidências e gates. PostToolUse grava
a contagem compartilhada de chamadas; não registra custo nem tokens.

| Evento | Hash da definição observado pelo Codex | Estado |
|---|---|---|

Hashes dos scripts instalados (conteúdo que acompanha as definições):

| Arquivo | SHA-256 |
|---|---|

## Passo que depende do operador

Abra a instalação isolada e revise as duas definições pelo /hooks:

```sh
env CODEX_HOME=/tmp/cstk-codex-native-v04-release-home codex --no-alt-screen -C /tmp/cstk-codex-native-v04-project
```

Use `/hooks` para revisar e confiar nas definições desta instalação. Não foi
concedida confiança automaticamente nem usado bypass. O produto exige revisão
da definição exata antes de executar hooks não gerenciados, conforme
[a documentação oficial](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks).

Após a revisão, confirme o status:

```sh
python3 adapters/codex/skills/feature-00c/scripts/native_status.py --project /tmp/cstk-codex-native-v04-project --codex-home /tmp/cstk-codex-native-v04-release-home
```

A primeira onda de um piloto real também exige a resposta explícita do operador
sobre atomic_commit. Para projeto completo, exige ainda roadmap_mode e
delivery_tier. A autorização geral para desenvolver não substitui essas escolhas.
A pergunta sobre commits está pendente; nenhuma resposta foi presumida.
A [skill feature-00c](../../../../adapters/codex/skills/feature-00c/SKILL.md)
exige: “Não transforme autorização geral para desenvolver em opt-in de commit.”

## Validação restante

Com hooks revisados e opt-ins reais, executar uma feature pequena pela sessão
Codex, observar os hooks em ferramentas permitidas/negadas, patches, contagem
e interrupção, e inspecionar decisões, relatórios e estado terminal. Até lá,
autonomous_ready continua false. App/IDE e cloud exigem ambiente próprio de
validação; cloud não executa command hooks locais deste pacote, conforme
[o suporte oficial de MCP](https://learn.chatgpt.com/docs/extend/mcp).

Revisão cruzada com Claude: tentativa sobre o código atualizado retornou
`Not logged in · Please run /login`, is_error=true, custo US$0. É necessário
restabelecer a autenticação do Claude antes de repetir a revisão restrita.
