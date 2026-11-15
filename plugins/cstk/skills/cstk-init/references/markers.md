# Marcadores de origem, pendencia e reconstituicao — cstk-init

Referencia do `SKILL.md` (lida sob demanda). E a gramatica NORMATIVA dos marcadores que a skill
escreve nos documentos do projeto-alvo. A verdade executavel e `scripts/init-provenance.sh lint`:
tudo o que esta aqui foi conferido contra o que o `lint` aceita e rejeita; se este texto e o
script divergirem, vale o script e a divergencia e defeito desta referencia.

Os tokens abaixo sao literais (nao traduza nem reformate); o texto ao redor segue o idioma do
projeto confirmado pelo operador.

## 1. Origem de fato

| Marcador | Uso |
|----------|-----|
| ``(fonte: `<caminho>`)`` | fato extraido de um artefato do projeto |
| ``(fonte: `<caminho>:<linha>`)`` | idem, apontando uma linha |
| `(informado pelo operador)` | resposta dada pelo operador na sessao |

Regras do `<caminho>` (verificadas pelo `lint`):

- relativo a raiz do projeto e MUST existir; inexistente (ou `<linha>` alem do fim do arquivo, ou
  linha apontada em diretorio) = `DANGLING`;
- caminho absoluto, iniciado por `\` ou `~`, com letra de unidade (`C:`), com segmento `..`, com
  caractere de controle, vazio, ou cujo symlink resolva para fora da raiz = `BAD-MARKER`;
- `<linha>` e inteiro de 1 a 999999999; `:0` e fora da faixa = `BAD-MARKER`;
- forma fora da gramatica (sem crases, sem o fechamento ``` `) ```) = `BAD-MARKER`;
- nunca cite arquivo `secret-bearing` copiando valor; citar a existencia da configuracao (so o
  caminho e o nome da chave) e permitido.

`(informado pelo operador)` e origem valida e nao exige verificacao de caminho.

## 2. Pendencia

```text
[PENDENTE: <pergunta que resolveria o campo>]
```

Substitui o valor do campo e nunca acompanha valor presumido. Cada ocorrencia sai do `lint` como
`PENDING<TAB><linha><TAB><pergunta>` e aparece no resumo final. Sem `:` e pergunta, ou sem `]`
de fechamento = `BAD-MARKER`.

Ciclo de vida: na execucao seguinte o artefato com pendencia entra em modo de revisao; o operador
e reconsultado so nos campos pendentes e preencher e um `amend` confirmado (ver
`references/write-policy.md`).

## 3. Spec reconstituida

Vale para `docs/specs/<short>/spec.md` OU qualquer arquivo com o marcador de maquina. Logo apos o
titulo (e antes do primeiro `## `):

```text
<!-- cstk-init:reconstructed -->
> **Origem**: spec reconstituida a partir do projeto existente por `cstk-init` em
> AAAA-MM-DD. Nao foi escrita antes da implementacao; descreve comportamento observado.
```

Sem o marcador, ou com ele depois do primeiro `## ` = `BAD-MARKER`. Alem disso, o `lint` rejeita
(`BAD-MARKER`), em spec reconstituida:

| Situacao | Como satisfazer |
|----------|-----------------|
| Item `- **FR-NNN**: ...` fora de `### Inferido (nao confirmado)` sem origem nem pendencia | ``(fonte: `<caminho>[:<linha>]`)`` ou `[PENDENTE: ...]` na linha |
| Titulo `### User Story ...` sem origem nem pendencia (a prioridade e o campo) | fonte na linha do titulo ou `(Priority: [PENDENTE: ...])` |
| Cenario de aceite (item sob `**Acceptance Scenarios**`, ou linha com `Given`..`When`/`Then`, `Dado`..`Quando`/`Entao`) sem origem nem pendencia | ``(fonte: `<teste>[:<linha>]`)`` ou `[PENDENTE: ...]` |
| Success Criterion (item de lista sob `## Success Criteria`) com algum digito fora dos IDs `SC-`/`FR-`/`INF-` e das origens/pendencias, sem origem de fato | ``(fonte: `...`)`` ou `(informado pelo operador)` na linha; `[PENDENTE: ...]` NAO conta como origem quando ha meta numerica fora dele |
| Qualquer `MUST`, `MUST NOT` ou `SHOULD` sob `### Inferido (nao confirmado)` | reescreva sem palavra normativa (inferencia nao e obrigacao) |

Formatos canonicos:

- Observado: ``- **FR-NNN**: O sistema <comportamento>. (fonte: `<caminho>[:<linha>]`)`` — formato
  reconhecido por `checklist/scripts/requirement-coverage.sh`.
- Inferido: subsecao `### Inferido (nao confirmado)` com itens `- **INF-NNN**: ...`.
- Delta: `## Delta Requirements` com `**Skip**: spec reconstituida de comportamento ja existente;
  nao altera comportamento documentado — cstk-init, AAAA-MM-DD`.

Exemplos que o `lint` ACEITA / REJEITA (conferidos pelo teste da skill):

```text
- **FR-001**: O sistema expoe a rota de saude. (fonte: `src/app.js`)             aceito
- **FR-002**: O sistema grava o log. [PENDENTE: qual arquivo implementa?]        aceito (PENDING)
- **FR-003**: O sistema exporta CSV.                                             BAD-MARKER (sem origem)
(fonte: src/app.js)                                                              BAD-MARKER (sem crases)
(fonte: `../fora.txt`)                                                           BAD-MARKER (segmento ..)
(fonte: `nao-existe.txt`)                                                        DANGLING
[PENDENTE: ]                                                                     BAD-MARKER (sem pergunta)
```

## 4. Emenda de constitution

Segue a skill `constitution`: Sync Impact Report em comentario HTML no topo, bump SemVer e
`**Last Amended**` atualizado no rodape. A entrada do Sync Impact Report cita `cstk-init` como
origem e a regra de conformidade aplicada (`CR-NNN` ou `missing-section`). Procedimento completo:
`references/write-policy.md` e `references/conformance-rules.md`.
