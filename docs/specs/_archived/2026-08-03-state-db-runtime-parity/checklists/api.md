# API Checklist: state-db-runtime-parity

**Purpose**: Quality gate dos requisitos de interface — assinatura do `set`
multi-campo (FR-005/FR-006) e do helper sourceable `_state-read.sh`
(Decision 1 / contract §4). Valida QUALIDADE dos requisitos, nao a
implementacao.
**Created**: 2026-08-02
**Feature**: [spec.md](../spec.md) · [contracts/runtime-interfaces.md](../contracts/runtime-interfaces.md)

> IDs CHK001-CHK010 (sequencia unica da feature; CHK072 citado no plan e ID
> HERDADO de checklist externo — sem colisao nesta faixa).

## Assinatura do `set` multi-campo (FR-005/FR-006)

- [x] CHK001 - A assinatura do `set` multi-campo define a semantica de atomicidade POR backend (JSON = 1 write do documento; SQLite = 1 transacao `BEGIN IMMEDIATE...COMMIT`)? [Completude, Spec §FR-005; Contract §1] {auto} — evidencia: contract §1 linhas 19-27 + FR-005 ("backend JSON num unico write; backend SQLite num lote unico transacional").
- [x] CHK002 - A retrocompatibilidade de 1 par (`comportamento atual inalterado`) esta explicitada e amarrada a FR-004? [Consistencia, Spec §FR-004/FR-005; Contract §1] {auto} — evidencia: "Um unico par preserva o comportamento atual (FR-004)" (spec FR-005) e contract §1 "1 par => comportamento atual inalterado".
- [x] CHK003 - Os modos de erro de USO do parser N pares (`--value` sem `--field` previo; `--field` sem `--value` ao fim) tem exit code definido? [Cobertura, Contract §1] {auto} — evidencia: contract §1 "=> exit 2 (uso)".
- [x] CHK004 - A rejeicao por invariante tem diagnostico mensuravel (qual invariante + quais campos do lote) e garantia de estado intacto sem escrita parcial? [Mensurabilidade, Spec §FR-006; Contract §1] {auto} — evidencia: FR-006 "rejeitar com diagnostico (invariante + campos envolvidos) e deixar o estado intacto"; contract §1 "exit 1 + diagnostico (invariante + campos do lote), estado intacto".
- [x] CHK005 - O caso canonico de promocao terminal (status + finished_at + termination_reason no mesmo lote) esta documentado como exemplo executavel? [Clareza, Contract §1] {auto} — evidencia: bloco "Caso de uso canonico (promocao terminal sob C2 do schema)" no contract §1.
- [x] CHK009 - O comportamento do lote com o MESMO `--field` repetido (last-wins? erro de uso?) esta definido? [Resolvido, Contract §1] {auto} — resolvido na FASE 1/1.1.1 (onda-006): LAST-WINS na ordem de aplicacao, nao erro de uso. Evidencia: contract §1 "MESMO --field repetido no lote => LAST-WINS" + rationale (dedup textual nao capta `.a.b` == `.a["b"]`; parser atual `state-rw.sh:649` ja faz last-wins em flags repetidas) + spec FR-005 paragrafo final.

## Helper sourceable `_state-read.sh` (contract §4)

- [x] CHK006 - A assinatura do helper define as duas funcoes (`state_read_materialize` / `state_read_cleanup`) e o protocolo de trap (`EXIT INT TERM`)? [Completude, Contract §4] {auto} — evidencia: contract §4 bloco de uso com `sf=$(state_read_materialize ...)` + `trap state_read_cleanup EXIT INT TERM`.
- [x] CHK007 - As garantias cobrem os 3 cenarios de backend: JSON (devolve o proprio `state.json`, zero mudanca), SQLite (materializa fora do state-dir), SQLite sem `sqlite3` (propaga falha rapida)? [Cobertura, Contract §4; Spec §FR-003/FR-004/FR-012] {auto} — evidencia: contract §4 "Garantias" cita FR-003, FR-012 e FR-004 nominalmente.
- [x] CHK008 - As assinaturas marcadas `[PROPOSTA — a validar na implementacao]` (set multi-campo, semantica do --force, _state-read.sh) tem passo definido de validacao + remocao do marcador ao implementar? [Resolvido, Contract header] {auto} — resolvido na FASE 1/1.1.4 (onda-006): protocolo no header do contract — tarefas donas 1.2.6/3.1.7/4.2.5 validam via sonda empirica, atualizam o texto em divergencia (com Decisao auditavel) e removem o marcador no MESMO commit; gate `grep -c 'PROPOSTA'` == 0 ao fim da FASE 4.

## Exit codes contratuais (FR-008)

- [x] CHK010 - O contrato de exit codes do `report.sh` distingue exit 7 (estado ausente) de 2 (uso) e 1 (falha generica) sem sobreposicao, nos DOIS subcomandos? [Consistencia, Spec §FR-008; Contract §3] {auto} — evidencia: contract §3 "exit 7 + diagnostico em stderr ... demais exit codes (2 uso, 1 falhas genericas) INALTERADOS"; FR-008/dec-011 aplica a `generate` e `emit`.

## Notes

- Items `{auto}` resolvidos pelo agente com citacao; `[Gap]` abertos viram
  tarefas via create-tasks (loop gap->acao).
- Nenhum item `{humano}` neste dominio.
