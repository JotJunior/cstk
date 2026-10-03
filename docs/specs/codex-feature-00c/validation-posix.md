# Validação da reescrita POSIX — 2026-10-03

O mantenedor solicitou a reescrita e a atualização do PR #223. O incremento
Python foi removido do adaptador, hooks, instalador, builder e testes. A
constitution não foi alterada. Scripts Python anteriores de outros escopos
do repositório permanecem fora desta revisão.

O adaptador 0.6.0 usa POSIX sh e awk, com JSON validado sem eval ou jq.
Estado, locks, ondas, decisões, gates, ingestão e relatórios continuam nos
helpers canônicos. `state-rw.sh check-dependencies` expõe verificação somente
leitura dos requisitos da camada transacional, sem introduzir dependência
jq na biblioteca JSON ou no instalador.

| Verificação | Resultado |
|---|---|
| `sh tests/run.sh codex` | 81 cenários aprovados; zero falhas/erros/órfãos; 513 s. Um contrato nativo opcional não selecionado na suíte, executado separadamente abaixo. |
| Ciclos de feature | Oito fases completas, JSON e SQLite; evidências, backlog, budget, bloqueios, proveniência e terminal verificados. |
| Ciclos de projeto/roadmap | Onze/três fases completas; três opt-ins, governança, conflito humano e fechamento terminal verificados. |
| Hook proprietário | Claude `a-claude` ativo junto da feature Codex: tick somente no estado Codex. Guarda Bash usa o mesmo vínculo. Outra onda Codex no projeto é recusada. |
| Interrupção | SIGTERM fecha sem avanço; SIGKILL exige PID registrado comprovadamente morto. Dono vivo/desconhecido ou modificado é recusado. |
| JSON | Unicode/pares de surrogates, escapes, chaves duplicadas, UTF-8 inválido, NUL, alterações de arrays/objetos e ausência de eval verificados. |
| `dash tests/codex/test_controller.sh` | Oito cenários aprovados, incluindo pipelines JSON/SQLite. Sintaxe sh/dash e ShellCheck sem warnings nos novos scripts. |
| `sh tests/run.sh recall` | 195 cenários aprovados. `--precedents --include-source-ids` aceito, com tipo/projeto/feature/onda/source_id; saída padrão preservada. |
| `sh tests/run.sh state-rw` | 105 cenários aprovados, incluindo a nova verificação somente leitura. |
| Build/instalação compartilhados | 11 cenários de build-release e 37 de install aprovados após ajustar expectativas de entrypoint e JSON. |
| Painel | 54 testes do leitor/watcher aprovados; tipos compartilhados compilados. Código TypeScript do PR foi preservado. |
| Cobertura/manifestos | Zero órfãos; manifestos e lockstep de versões do painel aprovados. Comparação com tag não solicitada, pois não é release. |

A suíte completa foi executada fora do sandbox: 4.545 passaram, três falharam,
zero erros/órfãos, 1.879 s. Duas falhas eram expectativas antigas dos testes
(`install-codex.py` no tarball e espaços na saída JSON); a terceira leu
state-rw.sh enquanto o arquivo era editado. Os três grupos foram reexecutados
com os arquivos estáveis e passaram (projeto: cinco; build: onze; install: 37).
A suíte final do adaptador e a nova verificação de state-rw também passaram.
A suíte completa inteira não foi repetida após essas correções; os resultados
originais e as reexecuções ficam separados para preservar a evidência.

## Instalação e protocolo nativos

Instalação e reinstalação reais em CODEX_HOME/projeto/banco temporários,
Codex CLI 0.160.0. O app-server conectou `cstk_pipeline` e descobriu quinze
ferramentas do servidor 0.6.0. Os dois hooks em shell foram descobertos,
habilitados e **untrusted**. Nenhum turno de modelo, confiança, aprovação ou
opt-in do operador foi sintetizado para fazer a validação passar.

Uma instalação temporária criada pelo instalador Python 0.5 foi atualizada
para POSIX 0.6 e reinstalada com sucesso. Os recibos antigos usam ordenação
por componentes de Path; o hash POSIX preserva essa ordem (foo/a precede
foo-bar/a), sem ignorar edições locais. A suíte específica do instalador foi
reexecutada após esse ajuste, com seis cenários aprovados.

Os testes de instalação preservam configuração, hooks personalizados e bytes
do banco; protegem edições em cache/hooks e locks concorrentes. Build de
release verificada e instalação passam com um `python3` de fixture que sempre
falha, comprovando ausência dessa dependência no novo fluxo.

## Limites e reprodução

A homologação semântica por modelo, cobertura real de ferramentas com hooks
confiáveis e revisão externa continuam abertas em native-acceptance.md.
Conexão MCP e fixtures não fecham esses critérios. `autonomous_ready=false`
permanece nos contratos. A reescrita resolve os três achados solicitados,
sem afirmar que o piloto está certificado para todas as interfaces.

Trabalho realizado em checkout isolado; arquivo local não rastreado do
operador e instalações globais foram preservados. Doctor foi consultado
somente leitura; diferenças já existentes na instalação global não foram
reescritas. Testes nativos e indexação usaram apenas diretórios temporários.

Comandos reproduzíveis: `sh tests/run.sh codex`, `sh tests/run.sh recall`,
`sh tests/run.sh state-rw`, `sh tests/run.sh build-release`,
`sh tests/run.sh install`, `sh tests/run.sh --check-coverage` e
`dash tests/codex/test_controller.sh`. Os probes são `sh native-mcp.sh` e
`sh native-status.sh`, ambos com `--project` e `--codex-home` temporários.
Sumários e hashes dos logs: [posix-test-results.txt](evidence/posix-test-results.txt).
