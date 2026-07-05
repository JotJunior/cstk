# Requirements Checklist: panel-installer

**Purpose**: Validar qualidade geral dos requisitos — completude, clareza, consistencia,
mensurabilidade e cobertura de cenarios. "Unit tests for English."
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)

---

## R.1 — Completude de Requisitos Funcionais

- [ ] CHK-R01 - Cada User Scenario (P1..P4) tem ao menos um FR correspondente que
  implementa seu Acceptance Criteria de forma biunivoca? Nenhum AC fica sem FR
  rastreavel? [Completude, Spec §P1-P4 vs §FR-001..FR-015]

- [ ] CHK-R02 - FR-001 especifica o que acontece se a API GitHub retornar um release
  marcado como `prerelease: true` ou `draft: true`? O comportamento (ignorar e buscar
  proximo / aceitar / erro) esta definido? [Completude, Spec §FR-001, Gap]

- [ ] CHK-R03 - FR-001 define um timeout maximo para a consulta a API GitHub e para
  o download do tarball? Ou o timeout depende do comportamento padrao do `curl` sem
  flag `--max-time`? [Completude, Spec §FR-001, Gap]

- [ ] CHK-R04 - FR-002 define o criterio exato de "instalacao valida": apenas presenca
  de `package.json` ou tambem presenca de `node_modules/` ou `apps/server/dist/`?
  "Reconhecivel" e mensuravel? [Clareza, Spec §FR-002, Ambiguity]

- [ ] CHK-R05 - FR-005 (`--reinstall`) especifica se a reinstalacao deve buscar o
  release MAIS RECENTE novamente ou reinstalar a mesma versao ja registrada em
  `.panel-version`? [Clareza, Spec §FR-005, Ambiguity]

- [ ] CHK-R06 - FR-009 (SIGINT/SIGTERM) especifica um timeout de grace period antes
  de o processo filho ser forcado a terminar (SIGKILL)? Ou o encerramento e sem
  timeout (espera indefinida)? [Completude, Spec §FR-009, Gap]

- [ ] CHK-R07 - Ha requisito que defina o comportamento quando `npm run start` termina
  sozinho (processo filho sai sem SIGINT do operador) — ex: painel crasha ou porta
  em conflito faz o Node sair? O `cstk serve` deve sair tambem (exit code do filho)
  ou tentar reiniciar? [Completude, Gap]

- [ ] CHK-R08 - FR-007 define o comportamento se `CSTK_PANEL_DIR` apontar para um
  diretorio nao-criavel (permissao negada, path invalido, dispositivo cheio)?
  [Completude, Spec §FR-007, Cobertura de Edge Cases]

---

## R.2 — Clareza e Mensurabilidade

- [ ] CHK-R09 - O Success Criteria "painel acessivel em menos de 60 segundos (excluindo
  tempo de download de rede)" e mensuravel pelo operador? Como o operador distingue
  "tempo de download" de "tempo de startup"? [Clareza, Spec §Success Criteria]

- [ ] CHK-R10 - "Progresso visivel ao operador" (FR-001) e especificado: qual mecanismo
  (barra de progresso, percentual, KB baixados, spinner, simples mensagem "baixando...")?
  O requisito e verificavel por teste automatizado? [Clareza, Spec §FR-001]

- [ ] CHK-R11 - "Mensagem de encerramento" (FR-009) tem conteudo minimo definido? E um
  requisito que o exit code do `cstk serve` seja igual ao exit code do processo `npm`
  filho? [Clareza, Spec §FR-009, Gap]

- [ ] CHK-R12 - FR-004 define "valores invalidos" para `--port` exclusivamente como
  "fora de 1-65535"? Sao ports de sistema (1-1023 sem privilegio) considerados
  invalidos ou validos com aviso? P3 AC menciona "Porta < 1024 sem privilegio:
  mensagem informando restricao de SO" — e isso um requisito funcional ou apenas
  edge case? [Clareza, Spec §FR-004, Spec §P3, Ambiguity]

- [ ] CHK-R13 - "Aviso no terminal quando `--host` difere de 127.0.0.1" (FR-004) tem
  especificado o canal (stdout vs stderr) e o formato (prefixo `[WARN]`, cor, etc)?
  [Clareza, Spec §FR-004]

- [ ] CHK-R14 - FR-003 define o que e "retro-compativel" para fins de FR-010
  (Compatibilidade retroativa do painel)? O cstk serve ASSUME que qualquer release
  tag mais recente funciona com `npm run start`, mesmo que o painel mude arquitetura?
  [Clareza, Spec §FR-010, Assumption]

---

## R.3 — Consistencia entre Requisitos

- [ ] CHK-R15 - O default `--port 5173` em FR-004 e consistente em TODOS os artefatos:
  spec.md, plan.md, research.md, quickstart.md, contratos? Nenhuma referencia residual
  a `3001` como default do cstk serve (somente como fallback interno do painel)?
  [Consistencia, Spec §FR-004, Spec §Clarifications/RECONCILIACAO]

- [ ] CHK-R16 - FR-011 (POSIX sh puro) e consistente com a decisao de usar
  `cli/lib/http.sh` como dep? Se `http.sh` usa Bash-isms internamente, a restricao
  POSIX de `serve.sh` ainda e valida? [Consistencia, Spec §FR-011, plan.md]

- [ ] CHK-R17 - P2 AC diz "tempo para o painel ficar acessivel e visivelmente menor
  que na primeira vez"; FR-002 proibe requisicoes de rede na segunda execucao. Sao
  consistentes? "Visivelmente menor" e suficientemente preciso ou deve ser quantificado
  (ex: <10s como no Success Criteria)? [Consistencia, Spec §P2, Spec §FR-002,
  Spec §Success Criteria]

- [ ] CHK-R18 - A decisao FR-014-INFRA-LOCK ("multiplas instancias em portas diferentes
  sao permitidas") e consistente com P3 AC ("Porta ja em uso: mensagem clara + sugestao
  de usar `--port`")? Quem detecta a colisao — `cstk serve` ou o sistema operacional?
  [Consistencia, Spec §FR-014-INFRA-LOCK, Spec §P3]

---

## R.4 — Criterios de Aceite Mensuraveis

- [ ] CHK-R19 - P1 AC "painel acessivel no endereco exibido no terminal" — qual criterio
  define "acessivel"? Porta TCP respondendo a TCP connect, ou HTTP GET retornando 200?
  O requisito cobre o caso em que o processo npm sobe mas o servidor HTTP leva segundos
  adicionais a aceitar conexoes? [Clareza, Spec §P1, Gap]

- [ ] CHK-R20 - P1 AC "sistema exibe mensagem clara de que o painel esta rodando" tem
  o conteudo minimo da mensagem especificado (ex: deve incluir a URL com porta efetiva)?
  [Clareza, Spec §P1, Gap]

- [ ] CHK-R21 - P2 AC "sistema nao faz nenhuma requisicao de rede" e verificavel em
  teste automatizado sem interceptacao de rede? O requisito especifica como esse
  comportamento sera coberto em `tests/cstk/test_serve.sh`? [Mensurabilidade,
  Spec §P2, Spec §Success Criteria]

- [ ] CHK-R22 - P4 AC "terminal confirma a reinstalacao e o processo completo" tem
  conteudo minimo de confirmacao definido? Ou qualquer saida no terminal satisfaz
  o criterio? [Clareza, Spec §P4, Ambiguity]

---

## R.5 — Cobertura de Cenarios e Edge Cases

- [ ] CHK-R23 - Ha requisito cobrindo o cenario em que o tarball baixado e um arquivo
  `.tar.gz` corrompido (download interrompido, checksum parcial)? O comportamento
  de `tar -xzf` em arquivo truncado e tratado explicitamente? [Cobertura de Edge
  Cases, Gap]

- [ ] CHK-R24 - Ha requisito cobrindo o cenario em que o diretorio `~/.local/share/cstk/`
  existe mas nao tem permissao de escrita? [Cobertura de Edge Cases, Spec §FR-007, Gap]

- [ ] CHK-R25 - P1 Edge Case "espaco em disco insuficiente: detectar e reportar antes
  de tentar instalar" — ha FR correspondente que define como detectar (ex: `df` antes
  do download) ou o edge case fica sem requisito funcional rastreavel? [Completude,
  Spec §P1, Gap]

- [ ] CHK-R26 - Ha requisito cobrindo o cenario em que a API GitHub retorna 403
  (rate limit) ou 5xx (erro do servidor) durante a consulta ao release? Comportamento
  esperado (retry, fail-fast, mensagem) esta definido? [Cobertura de Edge Cases, Gap]

- [ ] CHK-R27 - Ha requisito cobrindo a atualizacao do painel (quando um novo release
  esta disponivel mas o painel ja esta instalado)? FR-010 (sem pin de versao) implica
  que `cstk serve` NAO atualiza automaticamente — mas ha um mecanismo para o operador
  atualizar sem usar `--reinstall`? [Completude, Spec §FR-010, Gap]

---

## R.6 — Dependencias, Premissas e Testabilidade

- [ ] CHK-R28 - A spec define a convencao de cobertura de testes para `test_serve.sh`:
  quais cenarios SAO obrigatoriamente cobertos (1a execucao, subsequente, flags
  invalidas, prerequisito ausente)? "Sem dependencia de rede real (mocks via variaveis
  de ambiente)" e suficientemente preciso como requisito de testabilidade? [Clareza,
  Spec §Success Criteria]

- [ ] CHK-R29 - O requisito FR-011 ("POSIX sh puro") tem criterio de verificacao
  automatizavel? Ex: `shellcheck --shell=sh` sem erros de Bash-ism, ou execucao sob
  `dash` sem falha? [Mensurabilidade, Spec §FR-011]

- [ ] CHK-R30 - A premissa de que `cstk-panel` e "sempre retro-compativel" (FR-010)
  esta documentada como ASSUMPTOM com risco declarado? Se o upstream quebrar o contrato,
  qual e o comportamento esperado do `cstk serve`? [Completude, Spec §FR-010, Assumption]

- [ ] CHK-R31 - FR-007 documenta a premissa de que `~/.local/share/` e acessivel no
  ambiente alvo (macOS + Linux)? Ha requisito de fallback para ambientes onde este
  caminho convencional nao existe (ex: NixOS, containers sem home)? [Completude,
  Spec §FR-007, Assumption]

---

## Notes

- Marcar items concluidos com `[x]`
- Items numerados por CHK-R01..CHK-R31 para referencia cruzada com tasks
- Gaps promovidos a FR antes de create-tasks: CHK-R02 (prerelease), CHK-R03
  (timeout), CHK-R06 (grace period SIGKILL), CHK-R07 (filho sai sozinho),
  CHK-R23 (tarball corrompido), CHK-R26 (API 403/5xx)
- CHK-R12 requer decisao do operador: porta 1-1023 sem privilegio e invalid (exit 2)
  ou valid com aviso? Impacta diretamente a logica de validacao em serve.sh
