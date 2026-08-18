# Requirements Checklist: Lançamento Paralelo de Features do Roadmap

**Purpose**: validar a QUALIDADE dos requisitos de `roadmap-parallel-launch`
(completude, clareza, consistência, mensurabilidade, cobertura) antes do
`/create-tasks`. Não valida implementação.
**Created**: 2026-08-17
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Sao os requisitos de cálculo da fronteira definidos com fonte de verdade única, proibindo derivação própria de status? [Completude, Spec §FR-001 + contracts/roadmap-frontier.md §4 e INV-3] {auto}
- [x] CHK002 - Sao os requisitos definidos para o caso "teto configurado maior que o número de candidatas"? [Completude, Spec §Edge Cases + contracts/parallel-launch.md §3 passo 5] {auto}
- [x] CHK003 - Sao os requisitos definidos para fronteira vazia e para roadmap ausente/mal-formado, distinguindo os dois casos? [Cobertura de Edge Cases, Spec §Edge Cases + contracts/roadmap-frontier.md §7.3 e §8 (exit 0 vs 1/3)] {auto}
- [x] CHK004 - Sao os requisitos de degradação sem tmux definidos com resultado equivalente ao caminho automático, e não apenas "não falhar"? [Completude, Spec §FR-007 + US3 AC2 + contracts/parallel-launch.md §4.2] {auto}
- [x] CHK005 - As duas obrigações distintas de FR-013 (validação empírica registrada + via manual independente) estão ambas expressas como requisito? [Completude, Spec §FR-013 + plan.md FASE 0 tasks 0.1/0.2/0.3] {auto}
- [x] CHK006 - Existe requisito que defina como o operador **retoma ou relança** uma feature cuja sessão-filha morreu abruptamente mas cuja worktree persiste? [Completude, Spec §FR-016 + contracts/roadmap-frontier.md §5 "Recuperacao apos sessao-filha morta" + contracts/parallel-launch.md §8.bis] {auto}
- [x] CHK007 - Sao os requisitos de identificação unívoca da sessão-filha suficientes para duas execuções simultâneas em **repos distintos** com o mesmo short-name? [Completude, Spec §FR-006 (par short-name + repo, com o campo `repo=` do payload como segundo componente) + contracts/parallel-launch.md §5 "Unicidade entre repositorios distintos"] {auto}

## Clareza de Requisitos

- [x] CHK008 - E "parada aguardando decisão humana **sem resposta**" (FR-008/FR-010) quantificado com uma janela de espera, ou conflita com o disparo imediato contratado? [Clareza, Spec §FR-008 — reescrito para deixar explícito que o próprio ato de registrar o bloqueio humano já é o estado terminal notificável, sem janela de espera anterior] {auto}
- [x] CHK009 - E "ambiente de trabalho isolado" (FR-005) quantificado, em vez de adjetivo? [Clareza, Spec §FR-005 — "sem compartilhamento de working tree ou branch corrente"; limite explicitado em contracts/parallel-launch.md §8.bis] {auto}
- [x] CHK010 - E "provavelmente tocam os mesmos artefatos" (FR-014) reduzido a uma regra determinística? [Clareza, contracts/roadmap-frontier.md §6 — interseção não-vazia de tokens que pareçam caminho de artefato; redação obrigatória "as entradas X e Y mencionam ambas <token>"] {auto}
- [x] CHK011 - E o teto de paralelismo quantificado com valor padrão explícito em vez de só "configurável"? [Clareza, Spec §FR-003 + Clarifications Q1 — default **2**] {auto}
- [x] CHK012 - Sao os três desfechos terminais enumerados sem sinônimos ambíguos entre spec e contrato? [Clareza, contracts/parallel-launch.md §6 — enum único `concluida|abortada|aguardando_humano`, com nota explícita de que `bloqueio_humano` é motivo de **onda**, não status de execução] {auto}

## Consistência de Requisitos

- [x] CHK013 - Sao as capacidades do helper `parallel-launch.sh` consistentes entre a tabela de responsabilidades e a superfície de CLI contratada? [Consistência, contracts/parallel-launch.md §1 (linha corrigida para "NAO — emit so compoe/imprime...") alinhada a §4] {auto}
- [x] CHK014 - E FR-010 (término não-concluído não libera dependentes) consistente com o mecanismo de derivação de status escolhido? [Consistência, contracts/roadmap-frontier.md §4 + contracts/parallel-launch.md §8 — abortada/bloqueada deixa `tasks.md` com linha pendente ⇒ `em-andamento` ⇒ dependentes inelegíveis, sem lógica extra] {auto}
- [x] CHK015 - E o multiplexador alvo o mesmo em FR-005, FR-007 e US3, sem menção genérica não-resolvida? [Consistência, Spec §FR-005/§FR-007 + Clarifications Q2 — tmux em todos] {auto}
- [x] CHK016 - E FR-012 (decisão e lançamento só partem da coordenadora) consistente com a alocação de atores contratada? [Consistência, contracts/parallel-launch.md §1 + INV-2 — subagente orquestrador e sessão-filha ambos "NAO" para interagir/abrir sessão] {auto}
- [x] CHK017 - A inserção do fluxo de leva respeita a ordem MUST já existente do término do modo roadmap, sem reordená-la? [Consistência, contracts/parallel-launch.md §2 + INV-1 — gatilho ocorre **após** o passo 4; nada é inserido entre os 4 passos] {auto}

## Qualidade de Criterios de Aceite (mensurabilidade)

- [x] CHK018 - E SC-001 ("menos de 1 minuto de interação") verificável como declarado, ou o cenário mapeado mede um proxy? [Mensurabilidade, Spec §SC-001 — redefinido como número de rodadas de pergunta (1, ou 2 quando FR-004 exige seleção), alinhado ao cenário `quickstart.md` C1 já mapeado em plan.md] {auto}
- [x] CHK019 - E SC-002 redigido de forma verificável sem depender de comportamento não comprovado? [Mensurabilidade, Spec §SC-002 — mede **tentativa** de notificação (lado da filha), não entrega/wake-up] {auto}
- [x] CHK020 - E SC-003 ("zero falhas silenciosas e zero travamentos") reduzido a asserção observável? [Mensurabilidade, plan.md FASE 3 tasks 3.2/3.3 — paridade byte a byte do texto emitido + `PATH` sem tmux ⇒ exit 0 sem prompt pendente] {auto}
- [x] CHK021 - E SC-004 verificável por matriz de casos, em vez de afirmação geral de corretude? [Mensurabilidade, plan.md §Cenários — dep concluída ⇒ elegível; dep `em-andamento` ⇒ não; dep inexistente ⇒ não; sem deps ⇒ elegível] {auto}
- [x] CHK022 - E SC-005 satisfeito por qualquer um dos dois desfechos (comprovado **ou** refutado), evitando critério que só passa se o mecanismo funcionar? [Mensurabilidade, Spec §SC-005 + plan.md task 0.1 — aceite é "funciona / não funciona / parcialmente" com transcrição literal] {auto}

## Cobertura de Cenarios

- [x] CHK023 - Todo requisito funcional tem pelo menos um cenário/critério associado? [Cobertura, gate determinístico `requirement-coverage.sh`] {auto}
      Evidência literal (re-rodado apos task 1.1/1.2 adicionarem FR-016/017/018):
      `RESULT|docs/specs/roadmap-parallel-launch/spec.md|requirements=18|covered=18|errors=0` (exit 0).
- [x] CHK024 - Cada User Story tem Independent Test que não depende das demais? [Cobertura, Spec §US1–§US4 — cada uma declara "Independent Test" próprio] {auto}
- [x] CHK025 - Os três ACs da US4 (aviso, informação insuficiente, prosseguir mesmo avisado) têm cobertura de requisito e de teste? [Cobertura, Spec §FR-014 + plan.md FASE 4 tasks 4.2/4.3] {auto}

## Dependencias e Premissas

- [x] CHK026 - A premissa de pré-requisitos já ratificados (briefing/constitution) está declarada como fora do escopo desta feature? [Assumption, Spec §Edge Cases (último item)] {auto}
- [x] CHK027 - A dependência de um helper de outra skill está declarada com a decisão de acoplamento registrada? [Dependência, research.md Decision 1 e Decision 9] {auto}
- [x] CHK028 - A dependência de tmux está classificada como **opcional** com fallback funcional exigido? [Dependência, plan.md §Constitution Check II — dep opcional com fallback FR-007 e teste dedicado] {auto}
- [x] CHK029 - A premissa não comprovada (wake-up de sessão coordenadora ociosa) está rotulada e impedida de virar afirmação antes da medição? [Assumption, contracts/parallel-launch.md §6 "NAO COMPROVADO" + INV-6 + plan.md FASE 0 como primeira task não-reordenável] {auto}

## Decisoes do dono do produto (aguardando)

- [x] CHK030 - O teto default **2** reflete o apetite de risco do produto quanto a rate-limit e conflito de merge, ou deveria ser 1 (mais conservador) na primeira versão? [Risco, Spec §FR-003] {humano} <!-- decidido pelo operador 2026-08-17 (dec-035): ver justificativa no state -->
- [x] CHK031 - A meta de SC-001 (< 1 minuto de interação) é o alvo correto, dado que o fluxo contratado tem 3 pontos de pergunta (oferta, teto, seleção)? [Risco, Spec §SC-001 + contracts/parallel-launch.md §3] {humano} <!-- decidido pelo operador 2026-08-17 (dec-035): ver justificativa no state -->
- [x] CHK032 - Aceita-se entregar US1/US2 sem o aviso de sobreposição (US4 é P4) na primeira versão utilizável? [Priorização, Spec §US4 "Why this priority"] {humano} <!-- decidido pelo operador 2026-08-17 (dec-035): ver justificativa no state -->
- [x] CHK033 - Se a FASE 0 refutar o wake-up, aceita-se US2 degradada para via manual, ou a feature deve ser repriorizada? [Risco, plan.md FASE 0 task 0.2 — "se refutado, §8 passa a depender da via manual"] {humano} <!-- decidido pelo operador 2026-08-17 (dec-035): ver justificativa no state -->

## Notes

- Items `{auto}` vêm resolvidos com citação; `[ ]` + marcador = gap real, não pendência de leitura.
- Destino obrigatório: `[Ambiguity]`/`[Conflict]` → `/clarify`; `[Gap]` → `/create-tasks`; `{humano}` → decisão antes de `/execute-task`.
