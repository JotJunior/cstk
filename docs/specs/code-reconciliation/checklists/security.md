# Security Checklist: Code Reconciliation (`reconcile-docs`)

**Purpose**: Validar a qualidade dos requisitos de seguranca (blast radius de escrita, entrada nao confiavel, vazamento de dados) da skill que le codigo e escreve documentacao.
**Created**: 2026-09-30
**Feature**: [spec.md](../spec.md)

## Blast radius de escrita

- [x] CHK001 - A proibicao de escrita fora da documentacao e imposta por mecanismo e nao por convencao? [Completude, Spec §FR-006 "por regra da skill, nao apenas por convencao"; Plan §Riscos `doc-guard.sh check` + auditoria `git-probe.sh status`] {auto}
- [x] CHK002 - O comportamento da guarda quando falha/ausente esta definido como fail-closed? [Completude, Plan §Riscos "Guarda falhando aberta": exit != 0 = escrita negada] {auto}
- [x] CHK003 - A exclusao do corpus `docs/specs/current/` e mensuravel? [Mensurabilidade, Spec §FR-017, SC-001 "zero arquivos em docs/specs/current/"] {auto}
- [x] CHK004 - Simlinks e TOCTOU entre check e escrita estao tratados ou o risco residual e explicito? [Cobertura de Edge Cases, Plan §Riscos "TOCTOU/simlink" (nega simlink, `pwd -P`; risco residual aceito)] {auto}
- [x] CHK005 - A skill esta proibida de executar comandos/testes do projeto ao "verificar" o codigo? [Completude, Plan §Riscos "Injecao indireta" (skill nunca executa comandos, testes ou ...)] {auto}

## Entrada nao confiavel

- [x] CHK006 - O formato aceito para o nome da feature e restrito contra path traversal e metacaracteres? [Clareza, Plan contracts/cli-invocation.md §2 regex `^([0-9]{4}-[0-9]{2}-[0-9]{2}-)?[a-z0-9][a-z0-9-]*$`, exit 2; Plan §Riscos A05; ausente no spec — apenas FR-014 (nao encontrado)] {auto}
- [x] CHK007 - Conteudo lido (codigo, docs, `reconciliation.md`) e tratado como dado e nao como instrucao? [Completude, Plan §Riscos "Injecao indireta via conteudo lido (LLM01/ASI01)"] {auto}
- [x] CHK008 - O uso de `git` esta confinado a subcomandos de leitura e neutraliza configuracao maliciosa do repositorio? [Completude, Plan §Riscos `git -c core.fsmonitor=false`, so `status --porcelain`/`log --name-only`] {auto}

## Veracidade e vazamento de dados

- [x] CHK009 - A escrita de dado factual sem fonte e proibida com destino definido ("nao verificavel")? [Completude, Spec §FR-008, Edge Cases "Dado factual sem fonte"] {auto}
- [x] CHK010 - A evidencia citada e conferida deterministicamente (arquivo/linha existem; `absent:` de fato ausente)? [Mensurabilidade, Plan §Riscos "Evidencia apontando para arquivo/linha inexistente" `markers.sh verify`] {auto}
- [ ] CHK011 - Ha requisito que impeca copiar segredos (chaves, tokens, credenciais) presentes no codigo para a documentacao, marcadores ou relatorio ao citar "trecho de codigo" como evidencia? [Gap, Spec §FR-008/FR-010/SC-004 exigem citar trecho; grep "secret|segredo|credencial|api key|senha" em spec/plan/research/data-model/contracts = 0 ocorrencias] {auto}
- [x] CHK012 - A skill nao possui comunicacao de rede/coleta remota? [Completude, Plan §Constitution Check IV "nenhuma rede; git so local"] {auto}
- [ ] CHK013 - A decisao de gravar direto (sem confirmacao) para escopo `--all` em portfolio com features arquivadas atende o apetite de risco do dono do produto, dado que a unica rede de seguranca e o VCS? [Risco, Spec §Assumptions "Modo padrao grava direto"; US4 P3] {humano}

## Notes

- Gap aberto `{auto}`: CHK011 (segredos em evidencia/marcadores/relatorio) -> `create-tasks` (especificar redacao/omissao de valores sensiveis na evidencia; referenciar `arquivo:linha` sem reproduzir o valor).
- CHK013 fica `[ ]` aguardando o dono do produto.
