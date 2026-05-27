# Contract: CLI `cstk serve`

Interface de linha de comando do subcomando `serve` do binario `cstk`.

## Sinopse

```
cstk serve [--port N] [--host H] [--reinstall]
```

## Flags

| Flag | Arg | Default | Descricao |
|------|-----|---------|-----------|
| `--port` | inteiro 1-65535 | `5173` | porta TCP onde o painel escuta. Exportada como `PORT` ao processo filho. |
| `--host` | string | `127.0.0.1` | interface declarada. Aceita para forward-compat; backend atual ignora (hardcoded `127.0.0.1`). Aviso se != `127.0.0.1`. |
| `--reinstall` | (sem arg) | desligado | remove a instalacao existente e re-baixa o release mais recente antes de subir. |
| `-h`, `--help` | (sem arg) | — | imprime ajuda e sai com 0. |

Flag desconhecida ⇒ mensagem em stderr + exit 2.

## Exit codes

| Code | Constante | Significado |
|------|-----------|-------------|
| 0 | `CSTK_EXIT_OK` | painel rodou e foi encerrado graciosamente (Ctrl+C / fim do filho npm). |
| 1 | `CSTK_EXIT_ERROR` | erro geral: prereq ausente (`curl`/`npm`), download falhou, integridade invalida (mismatch quando `.sha256` presente), extracao falhou, instalacao corrompida sem `--reinstall`. |
| 2 | `CSTK_EXIT_USAGE` | uso incorreto: porta fora de 1-65535, flag desconhecida, arg faltando. |
| 3 | `CSTK_EXIT_LOCK` | (nao usado — `serve` nao adquire lock; FR-014-INFRA-LOCK). |

## Mensagens (stdout = dados/UX, stderr = erros)

### Sucesso — primeira invocacao
```
cstk serve: painel nao instalado, baixando release mais recente de JotJunior/cstk-panel...
cstk serve: release <tag_name> baixado.
cstk serve: AVISO: verificacao de integridade indisponivel (release sem asset .sha256).
cstk serve: instalando dependencias (npm install)...
cstk serve: iniciando painel em http://127.0.0.1:5173  (Ctrl+C para encerrar)
```

### Sucesso — invocacao subsequente
```
cstk serve: usando painel ja instalado (<tag_name>).
cstk serve: iniciando painel em http://127.0.0.1:5173  (Ctrl+C para encerrar)
```

### Aviso de host
```
cstk serve: AVISO: --host 0.0.0.0 ignorado; o backend do cstk-panel escuta fixo em
127.0.0.1 (limitacao do painel atual). A flag e aceita para compatibilidade futura.
```

### Erros (stderr)
| Condicao | Mensagem | Exit |
|----------|----------|------|
| `curl` ausente | `cstk serve: curl nao encontrado no PATH (necessario para baixar o painel).` | 1 |
| `npm` ausente | `cstk serve: npm nao encontrado no PATH. Instale o Node.js (https://nodejs.org).` | 1 |
| porta invalida | `cstk serve: porta invalida '<v>': deve ser inteiro entre 1 e 65535.` | 2 |
| download falhou (offline) | (mensagem de `http.sh`, ex.) `http: nao foi possivel resolver host ...` + `cstk serve: falha ao baixar o release.` | 1 |
| release inexistente | `cstk serve: nao foi possivel localizar o release mais recente (HTTP da API GitHub).` | 1 |
| integridade invalida | `cstk serve: checksum MISMATCH do release; abortando sem instalar.` | 1 |
| instalacao corrompida | `cstk serve: instalacao em <dir> parece corrompida (package.json ausente). Rode: cstk serve --reinstall` | 1 |
| porta em uso | `cstk serve: porta <N> em uso. Tente outra: cstk serve --port <outra>.` | 1 |
| extracao falhou (ex. disco) | `cstk serve: falha ao extrair o release (espaco em disco?).` | 1 |

### Encerramento (SIGINT/SIGTERM)
```
cstk serve: encerrando painel...
```

## Garantias de comportamento

- **Reuso sem rede (FR-002)**: com `PainelInstalado.valido = true` e sem `--reinstall`,
  NENHUMA requisicao a `api.github.com`/`objects.githubusercontent.com` e feita.
- **Isolamento**: `cstk serve` nao altera estado de nenhum outro subcomando.
- **Zero coleta remota (FR-012)**: trafego externo limitado a download do release.
- **Foreground**: o processo permanece ate o filho `npm` terminar ou receber SIGINT/SIGTERM.
