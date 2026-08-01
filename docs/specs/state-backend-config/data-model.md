# Data Model: Configuração de Backend do state.db (Cutover Fase 2)

> **Nota de escopo**: esta feature não introduz nenhuma tabela nova no `state.db`
> nem no `knowledge.db`. As duas entidades da spec são, respectivamente, um
> **arquivo de configuração de texto plano** e um **relatório efêmero computado em
> tempo de execução**. O modelo abaixo descreve a estrutura de cada uma no formato
> em que de fato existem — não há DDL nesta feature.

---

## Entity: BackendConfig

Registro global **por-usuário do sistema operacional** que declara qual backend de
estado deve ser usado por padrão em novas inicializações de execução 00c.

**Persistência**: arquivo de texto plano `key=value`, um par por linha.
**Localização**: `$HOME/.claude/cstk/config`
**Cardinalidade**: exatamente um por usuário do SO (nunca system-wide, nunca
por-projeto).

### Campos (chaves reconhecidas)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `state_backend` | enum | `sqlite` \| `json` | Chave introduzida por esta feature. Ausente ⇒ tratado como `json` (FR-008) |

> Chaves **desconhecidas** no arquivo são ignoradas pelo leitor, não são erro. Isso
> mantém o arquivo extensível por features futuras sem que uma versão antiga do
> leitor quebre ao encontrar uma chave que não conhece.

### Regras de formato

| Regra | Comportamento |
|-------|---------------|
| Linha `chave=valor` | Par válido; sem espaços ao redor do `=` |
| Linha iniciada por `#` | Comentário — ignorada |
| Linha em branco | Ignorada |
| Linha sem `=` | Formato inválido (ver estados abaixo) |
| Chave repetida | Não é produzida pelo escritor (Decision 7 reescreve a linha existente em vez de acrescentar); se presente por edição manual, o leitor adota a **última** ocorrência |

### Estados

O `BackendConfig` é observado pelo leitor em um destes três estados. Note que
`AUSENTE` e `INVÁLIDO` colapsam no **mesmo comportamento efetivo** por força de
FR-008 — a distinção existe apenas para o relatório de diagnóstico poder informar
o operador com precisão.

```
AUSENTE   — arquivo não existe                     ⇒ backend efetivo: json (fallback)
INVÁLIDO  — arquivo existe, não interpretável      ⇒ backend efetivo: json (fallback, FR-008)
DECLARADO — arquivo existe, state_backend legível  ⇒ backend efetivo: valor declarado,
                                                     sujeito à checagem de dependência
```

Nenhum desses estados faz a inicialização ou o diagnóstico falharem (FR-008).

### Transições

```
AUSENTE ──[enable-sqlite: deps OK + runtime capaz]──> DECLARADO(sqlite)
AUSENTE ──[enable-sqlite: deps insuficientes]──────> AUSENTE   (recusado, exit != 0, FR-004)
AUSENTE ──[enable-sqlite: runtime incapaz]─────────> AUSENTE   (recusado, exit != 0, FR-004A)

DECLARADO(sqlite) ──[enable-sqlite novamente, deps OK]──> DECLARADO(sqlite)
                                                          (no-op silencioso, FR-009-INFRA-IDEMP)
```

**Invariante**: toda transição recusada deixa o arquivo **byte-a-byte idêntico** ao
que era antes da tentativa (FR-004, SC-002). A validação inteira ocorre antes de
qualquer escrita.

### Relacionamentos

- `BackendConfig` **1:N** inicializações de execução 00c — a config é lida a cada
  nova inicialização; nenhuma referência é gravada no estado criado.
- `BackendConfig` **não** tem relação com execuções **já existentes**: FR-006
  determina que projetos com `state.json` não migrado ou com `state.db` já migrado
  continuam se comportando exatamente como antes. A config nunca dispara migração.

---

## Entity: DependencyDiagnosticReport

Saída do diagnóstico de dependências. **Efêmera** — computada a cada invocação,
nunca persistida. Não há armazenamento, portanto não há schema; a estrutura abaixo
descreve o conteúdo que o relatório MUST conter (FR-007).

### Campos

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `dependencies[]` | lista | ≥ 2 entradas: `sqlite3` e `jq` | Conjunto mínimo exigido por FR-007 |
| `dependencies[].name` | string | `sqlite3` \| `jq` | |
| `dependencies[].present` | bool | — | Encontrada no `PATH`? |
| `dependencies[].detected_version` | string | vazio quando ausente | Versão efetivamente detectada |
| `dependencies[].minimum_version` | string | vazio quando não há piso | `3.45.1` para `sqlite3` |
| `dependencies[].adequate` | bool | — | Presente **e** ≥ mínimo |
| `effective_backend` | enum | `sqlite` \| `json` | Backend que uma nova inicialização usaria **agora** |
| `reason` | enum | ver tabela abaixo | Por que esse backend seria escolhido |
| `anomaly_detected` | bool | — | Governa o exit code (FR-007) |

### Domínio de `reason`

| Valor | Significado | `effective_backend` | Anomalia? |
|-------|-------------|---------------------|-----------|
| `nunca-configurado` | Config ausente ou sem `state_backend` | `json` | Não — default legítimo (FR-008) |
| `config-invalida` | Config presente mas não interpretável | `json` | Não — fallback previsto por FR-008 |
| `configurado-dependencia-adequada` | `sqlite` declarado, `sqlite3` ≥ mínimo | `sqlite` | Não |
| `configurado-dependencia-abaixo-do-minimo` | `sqlite` declarado, `sqlite3` presente porém < mínimo | `json` | **Sim** |
| `configurado-dependencia-ausente` | `sqlite` declarado, `sqlite3` ausente | `json` | **Sim** |
| `json-explicito` | `json` declarado explicitamente | `json` | Não |

> **`jq` ausente é sempre anomalia**, independentemente do backend configurado: o
> runtime de estado já encerra com exit 1 quando `jq` falta — função
> `_sr_require_jq()` em `state-rw.sh:123-127`, mais os demais scripts do
> `agente-00c-runtime`. Condição regularizada pelo carve-out do amendment 1.3.0
> da constitution. Um ambiente sem `jq` não executa 00c em nenhum backend, e o
> diagnóstico deve dizer isso.
>
> **Nota de drift (Princípio VI)**: `docs/constitution.md` cita esse gate como
> `state-rw.sh L116-118`. Verificado que hoje essas linhas contêm
> `_sr_ts_for_filename()` (um helper de timestamp), **não** a checagem de `jq`.
> A citação da constitution está desatualizada em relação ao código. Este
> documento cita a localização **real** e registra a divergência em vez de
> propagá-la; corrigir a constitution é ação separada, fora do escopo desta
> feature.

### Relacionamentos

- `DependencyDiagnosticReport` **lê** `BackendConfig` (1:1 por invocação) — relação
  estritamente de leitura. O diagnóstico **nunca** escreve na config nem a corrige.
