# Security Checklist: Doctor Shadowed Scope

**Purpose**: Validar a qualidade dos requisitos de seguranca introduzidos pela
fronteira de confianca do `.cstk-manifest` de escopo de projeto — a secao le
um arquivo cujo conteudo pode ser controlado por um repositorio de terceiro
(dado versionado num `.claude/` clonado). Motivado pelo achado HIGH + 4 MEDIUM
do gate `owasp-security` sobre o Phase 1 do plan (research.md D12, `block-001`).
**Created**: 2026-08-27
**Feature**: [spec.md](../spec.md)

## Input Validation (fronteira untrusted)

- [x] CHK021 - O requisito de validacao do campo `name` ANTES de compor qualquer path esta especificado com a funcao concreta responsavel e a consequencia exata de reprovacao (nao apenas "validar input")? [Clareza, contract §7 regra R1] {auto}
  Evidencia: contrato §7 R1 — "`name` MUST passar por `manifest_name_is_safe` antes de compor qualquer path. Reprovado ⇒ registro `unrecognized` (entra no denominador, nunca no numerador)" — com o vetor concreto documentado: `name=../../../.ssh/known_hosts` escaparia do catalogo sem a validacao.
- [x] CHK022 - O requisito de nao seguir symlinks antes de hashear esta especificado com o teste exato (`[ -h "$path" ]`) e o estado de saida correspondente, evitando a leitura vaga "tratar symlinks com cuidado"? [Clareza, contract §7 regra R2] {auto}
  Evidencia: contrato §7 R2 — "Antes de hashear, MUST testar `[ -h "$path" ]`. Symlink ⇒ `indeterminate` com `<motivo> = symlink`; nunca hashear o alvo" — com o vetor concreto (`./.claude/agents/x.md -> ~/.ssh/id_rsa`) documentado como o que a regra impede.
- [x] CHK023 - O requisito de que o hash so pode ser impresso para paths que ja passaram por R1 e R2 esta especificado como uma regra PROPRIA (nao apenas implicita na ordem de execucao do codigo), evitando que um refactor futuro reordene os passos sem perceber a dependencia? [Consistencia, contract §7 regra R6] {auto}
  Evidencia: contrato §7 lista R6 como regra explicita e independente — "Hash so pode ser impresso para paths que passaram em R1 e R2" — com o motivo: "o prefixo de 12 caracteres so e inocuo enquanto o path e comprovadamente confinado ao catalogo; sem R1/R2 ele vira oraculo de confirmacao de conteudo".

## Protecao contra Forjamento de Saida (Log/Report Injection)

- [x] CHK024 - O requisito de sanitizacao dos campos de texto livre untrusted (`name`, `toolkit_version`) antes de impressao esta especificado com a funcao concreta e a forma de emissao (`printf '%s'` com o valor como argumento, nao interpolado em formato)? [Clareza, contract §7 regra R3] {auto}
  Evidencia: contrato §7 R3 — "`name` e `toolkit_version` MUST passar por `manifest_scrub_text` antes de impressao, e serem emitidos via `printf '%s'` com o valor como argumento" — com o vetor concreto: "ESC/`\r`/`\b` em campo untrusted forjam visualmente a linha `[OK] ... lidas integralmente` e apagam `[DRIFT]`".
- [x] CHK025 - O requisito acima reconhece explicitamente o limite da mitigacao (o exit code sobrevive, mas o RELATO HUMANO pode ser forjado) em vez de alegar que a sanitizacao resolve todo o vetor? [Clareza, contract §7 nota da regra R3] {auto}
  Evidencia: a propria nota de R3 e explicita quanto ao residual — "O exit code permanece correto (o gate de CI sobrevive), mas o relato humano e forjavel — a falsa saude que a feature existe para matar" — reconhece o vetor sem inflar a garantia da mitigacao.

## Consumo Excessivo de Recursos (DoS / CWE-400)

- [x] CHK026 - O teto de consumo (10.000 linhas / 4.096 bytes por linha) esta especificado com valores NUMERICOS concretos e o estado de saida quando excedido, em vez de um requisito vago tipo "limitar consumo de recursos"? [Clareza, Mensurabilidade, contract §7 regra R5] {auto}
  Evidencia: contrato §7 R5 — "no maximo 10.000 linhas de dados por fonte e 4.096 bytes por linha. Excedido ⇒ fonte reportada como `unreadable` com motivo `teto-excedido`" — ambos os numeros e o estado resultante sao explicitos e verificaveis.
- [x] CHK027 - O requisito distingue "teto imposto por leitura limitada" de "teto verificado a posteriori" como duas implementacoes NAO equivalentes, com o cenario adversarial que so a primeira resolve documentado explicitamente? [Clareza, contract §7 nota normativa R5 + quickstart Cenario 19 linha 15] {auto}
  Evidencia: contrato §7 ("Nota normativa sobre COMO impor o teto da R5") — "MUST ser imposto DURANTE a leitura... e nao por uma checagem de comprimento depois de a linha ja ter sido lida inteira. Um `.cstk-manifest` de um unico registro de varios GB sem `\n` derrota inteiramente um teto post-hoc". Quickstart Cenario 19 linha 15 e uma fixture dedicada (50MB numa unica linha sem `\n`) desenhada especificamente para reprovar uma implementacao que so checa comprimento depois de ler.
- [x] CHK028 - A severidade real do risco de DoS esta calibrada explicitamente (por que NAO e bloqueio) em vez de tratada com o mesmo peso de um achado critico, evitando tanto a subestimacao quanto a inflacao do risco? [Clareza, Consistencia, contract §7 nota final] {auto}
  Evidencia: contrato §7 fecha com calibracao explicita — "Impacto real e baixo e por isso isto NAO e bloqueio: o alvo e um CLI local read-only, o vetor exige que o operador ja tenha clonado o repo hostil, e o pior resultado e um `cstk doctor` consumindo memoria ate ser interrompido — sem escrita, sem escalonamento, sem persistencia" — ao mesmo tempo mantendo o requisito de implementacao ("um teto que nao limita nada e pior que teto nenhum").

## Glob/Word-Splitting Injection

- [x] CHK029 - O requisito de rodar o laco de iteracao de linhas sob `set -f` (glob desabilitado) esta especificado com o vetor concreto que ele fecha, e amarrado a um precedente JA existente no repo (nao uma mitigacao inventada ad-hoc para esta feature)? [Consistencia, contract §7 regra R4] {auto}
  Evidencia: contrato §7 R4 — "Com `IFS=<newline>` mas sem `set -f`, uma linha de dados contendo `*` sofre glob e vira N iteracoes — inflando o numerador 'por uso' acima do denominador e disparando `inconsistent` a partir de input externo. Precedente literal no repo: `cli/lib/recall.sh`, `fts_query_escape()`, que isola `set -f` num subshell pelo mesmo motivo" — a mitigacao segue um padrao ja auditado no proprio codebase, nao uma solucao isolada.

## Avaliacao de Ameaca Documentada (Threat Modeling)

- [x] CHK030 - Cada regra de mitigacao (R1-R6) esta rastreavel ao achado especifico do gate `owasp-security` que a motivou, em vez de aparecer como lista solta sem proveniencia? [Traceability, contract §7 intro + research.md D12] {auto}
  Evidencia: contrato §7 abre com "Adicionado apos o gate `owasp-security` sobre o Phase 1 (achado HIGH de path traversal + 4 MEDIUM). Ver research.md D12" — a secao inteira e resultado direto e rastreavel de um gate de seguranca real, nao uma adicao especulativa.
- [x] CHK031 - Uma classe de ameaca AVALIADA e descartada (TOCTOU / CWE-367) tem o racional de descarte registrado explicitamente, em vez de simplesmente nao aparecer no documento (o que seria indistinguivel de "nao foi considerada")? [Completude, contract §7 "TOCTOU ... avaliado e NAO e achado"] {auto}
  Evidencia: contrato §7 dedica um paragrafo a TOCTOU (CWE-367): "a secao e read-only, nao tem `--fix` associado... A janela entre ler o manifesto e hashear so pode produzir `indeterminate`, que e reportado e impede o rotulo `[OK]`... a propriedade que importa aqui e que a corrida nunca produz uma afirmacao de saude". Ausencia de acao documentada com justificativa e diferente de lacuna nao percebida.
- [x] CHK032 - O escopo de superficie de ataque desta feature esta delimitado explicitamente (read-only, sem `--fix` para os estados novos, sem saida JSON nova, kind `skills` fora de escopo), reduzindo o espaco de requisitos de seguranca que precisariam ser especificados nesta rodada? [Completude, contract §6 nao-objetivos] {auto}
  Evidencia: contrato §6 — "Nenhum `--fix` para os estados novos", "Nenhuma saida JSON... adicionar seria feature nova", "Nenhuma cobertura do kind `skills`" — a superficie e delimitada por decisao explicita, nao por omissao.

## Consistencia entre Postura de Seguranca e Requisitos Funcionais

- [x] CHK033 - A decisao de tornar a secao inteira report-only (nunca gateia, mesmo diante de input hostil) esta registrada como decisao AUDITAVEL do operador (nao inferida ou assumida pelo agente), com o bloqueio humano e a resposta rastreaveis? [Traceability, dec-020/dec-022/block-001] {auto}
  Evidencia: `dec-020` registra literalmente "Resposta humana ao block-001 (gate owasp-security HIGH...)" com a escolha `default-on-report-only` e o racional "Input de terceiro pode produzir diagnostico, nunca veredito"; `dec-022` aplica a postura aos artefatos. Esta e exatamente a classe de decisao que a regra de "classe estrutural" do orquestrador (eixo de postura de seguranca perante input de terceiro) exige documentar com consentimento humano explicito — e o consentimento esta presente e citavel.
- [ ] CHK034 - O teto numerico de R5 (10.000 linhas / 4.096 bytes) e adequado ao apetite de risco do operador para o pior caso plausivel (repo hostil clonado + `cstk doctor` executado sem `--scope`), ou deveria ser configuravel/revisitado conforme uso real do toolkit? [Risco, Spec/contract §7 R5] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`)
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia (continuando de `requirements.md`, CHK001-CHK020)
- Este dominio nao cobre autenticacao/autorizacao/secrets/compliance (catalogo generico de `references/security.md`) porque a feature nao introduz esses eixos — a superficie real e input validation sobre um arquivo untrusted lido por um CLI local read-only (contrato §6/§7).
