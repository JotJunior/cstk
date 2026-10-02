# Ciclo de vida compartilhado no Codex

As seis entradas são skills nativas: feature-00c, feature-00c-resume,
feature-00c-abort, agente-00c, agente-00c-resume e agente-00c-abort.
No plugin, o Codex pode apresentá-las com prefixo `cstk-codex-pilot:`.
Selecione a skill pelo menu nativo; os arquivos de commands do Claude não
registram aliases `/` no Codex. No checkout, AGENTS.md encaminha pedidos com
esses nomes às mesmas instruções.

## Seleção e inspeção

Use o MCP `cstk_pipeline`, com `cstk_select_execution(project, kind,
short_name, knowledge_db?)`. Project deve ser a raiz absoluta da sessão;
kind é feature ou project. Para feature, short_name identifica o diretório
existente; para project, use execution.canonical_project do estado existente.
Descubra essa identidade com o reader compartilhado state-rw.sh read, sem
deduzi-la do nome da pasta. Não crie outro estado ao retomar ou abortar.
Se não houver identidade inequívoca, obtenha a informação faltante do operador.
Confirme knowledge_db em cstk_context. A seleção não cria estado nem exige
governança existente; bootstrap/abertura de onda validam seus pré-requisitos.

cstk_status inspeciona identidade, integridade, proveniência, etapa, ondas
abertas e bloqueios, inclusive em estado terminal ou de outro runtime.
Na conexão proprietária ele usa o lock atual; outra conexão não toma o lock.

## Retomada que continua a pipeline

Chame cstk_resume. Sem pendências ele abre a onda da etapa persistida e
devolve o mesmo descritor de cstk_open_wave, mantendo o lock entre chamadas.
Leia skill_path e phase_reference e execute a etapa na sessão atual, seguindo
feature-00c/SKILL.md. Após cada cstk_complete, inspecione o resultado; se a
execução continuar, abra a próxima onda e prossiga até conclusão ou uma
condição concreta de pausa/bloqueio. Não pare apenas por ter aberto a onda.

Se houver bloqueio, cstk_resume retorna pending_blocks sem abrir onda.
Mostre perguntas/contextos e aguarde a resposta real. Aplique uma resposta
com answer, response_source e block_id; block_id só pode ser omitido quando
exatamente um bloqueio estiver pendente. Nunca aplique a mesma resposta a
todos os bloqueios. Respostas têm 1..2000 caracteres; uma resposta registrada
não pode ser substituída. Responder não comprova qualidade da etapa nem
autoriza decisões estruturais fora do consentimento registrado.

Execução terminal retorna resumed=false e não abre onda. Uma onda órfã exige
cstk_recover, sem inferir conclusão por arquivos existentes. Lock órfão exige
abandoned_owner_pid igual ao PID observado e comprovadamente morto. Nunca
remova lock de outro escritor vivo. Em conexão com onda própria, pause ou
aborte diretamente; recuperar não é necessário.

No projeto, resume aceita init_aspects (3..7 strings), technical_aspects e
operational_aspects (0..7 strings), com response_source. Inicializa somente
aspectos ainda ausentes através de drift.sh; não substitui aspectos congelados.
Opt-ins já registrados são preservados na retomada. Estado inicial sem as
respostas exigidas continua sujeito à guarda I-2; obtenha as respostas reais.

## Transferência explícita entre runtimes

Uma execução Claude não muda de dono apenas por compartilhar knowledge.db.
Se o operador solicitar a transferência, chame cstk_handoff com
expected_runtime=claude-code (ou unattributed para origem legada desconhecida),
response_source e rationale concreta. model é opcional e exige ID observado.
O helper preserva identidade, ondas, decisões, opt-ins e artefatos; registra
runtime_handoffs com proveniência anterior e ingere o índice derivado.
Depois chame cstk_resume. Transferência exige integridade, governança válida,
nenhuma onda aberta e nenhum dono vivo. Primeiro encerre a onda no runtime
de origem. Um lock comprovadamente morto pode ser recuperado explicitamente
na transferência; não feche onda Claude sem reconciliação no runtime de origem.

## Mudanças de governança

Drift interrompe a retomada. Apresente as diferenças do briefing/constitution
e seus efeitos sobre os artefatos existentes. Se o operador aprovar a
reconciliação, chame cstk_reconcile_governance com rationale, response_source
e expected_hashes contendo `briefing:<sha256>` e `constitution:<sha256>`
dos arquivos efetivamente revisados. Os dois hashes são conferidos sob lock.
A operação guarda versões anteriores e novas e uma decisão justificada.
Não atualize hashes automaticamente para silenciar drift. Após reconciliar,
reavalie a etapa e os artefatos que dependem das mudanças antes de concluí-la.

## Aborto

cstk_abort aceita reason (default aborto manual), purge_backups (default false)
e, apenas para lock morto, abandoned_owner_pid. Na conexão proprietária,
fecha a onda imediatamente com motivo aborto, sem avançar etapa, e libera o
lock. Sem onda própria adquire o lock; outro dono vivo exige abortar na conexão
que o possui ou encerrar seu transporte normalmente. Não mate um PID arbitrário.

Preserva código, documentos, histórico e commits existentes. Grava status
abortada, finished_at e motivo em uma operação atômica JSON/SQLite, decisão,
evento, backup terminal filtrado, relatório parcial e ingestão best-effort.
Pré-requisito desaparecido/drift não impede aborto; identidade, integridade,
proveniência e confinamento de paths continuam obrigatórios. Execução já
abortada/concluída retorna aborted=false sem mudar o estado.

purge_backups=true, somente se solicitado pelo operador, remove exclusivamente
o diretório de backups desta execução após preservar estado e relatório.
Não siga symlinks nem apague estado/documentos. O opt-in persistido de commits
é respeitado: quando true, o helper canônico faz commit local por allowlist;
quando false, nenhum commit é criado. Falha no commit é reportada como
degraded; o aborto continua efetivo. Não faça push nem abra PR implicitamente.

## Transporte de terminal

Os scripts ficam em feature-00c/scripts no checkout ou pacote. Sem MCP:

```sh
python3 lifecycle.py status --project PAP --short-name SLUG
python3 controller.py resume --project PAP --short-name SLUG
python3 lifecycle.py abort --project PAP --short-name SLUG --motivo 'Motivo real'
```

Acrescente --kind project para agente-00c. controller.py resume mantém o
transporte JSONL vivo e abre a onda; aceita --block-id, --resposta-bloqueio e
--response-source. Sua ação JSONL abort aceita reason e purge_backups.
lifecycle.py resume prepara/valida e pode aplicar resposta/aspectos, sem abrir
onda; retorna exit 5 para bloqueios pendentes. lifecycle.py handoff e
reconcile-governance oferecem os mesmos contratos do MCP. SIGTERM/EOF fecha
onda sem avançar; SIGKILL exige recuperação explícita. Nenhum scheduler ou
troca automática de modelo é presumido.
