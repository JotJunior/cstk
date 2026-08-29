/**
 * Interventions — fila cross-projeto de intervencoes humanas (US1/US2,
 * spec.md FR-001/FR-013/FR-014/FR-015).
 *
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §6/§7/§11.7;
 *      docs/specs/human-bridge/quickstart.md Cenarios 2-4.
 *
 * PRIMEIRA tela do painel com uma acao de ESCRITA (responder). O painel
 * TRANSPORTA a resposta — nunca a persiste como registro canonico
 * (Principio I do painel, "a Ponte MUST NOT gravar decisao/bloqueio/onda
 * no corpus"). `session_id` nunca atravessa esta superficie (dec-026):
 * o roteamento ocorre dentro da chamada MCP, antes de qualquer HTTP.
 *
 * Conteudo UNTRUSTED (`question`, `options[]`, `untrustedText`) SEMPRE via
 * `TextRaw` — nunca `dangerouslySetInnerHTML`, nunca interpolacao em HTML
 * cru (Principio V do painel).
 */
import { useState } from 'react';
import { useInterventions, useAnswerIntervention } from '@/lib/hooks-bridge.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import { TextRaw } from '@/components/index.js';
import { fmtMs, fmtRelative, fmtTimestamp } from '@/lib/format.js';
import type { InterventionQueueItemDTO, InterventionKind, DegradedReason } from '@cstk-panel/shared-types';

/**
 * Teto de bytes do campo de texto livre — MESMO valor MEDIDO em
 * `panel/apps/server/src/lib/bridge-sanitize.ts:62` (`TEXT_MAX_BYTES`).
 * O servidor e a fonte de verdade (trunca/valida de fato); este numero
 * aqui e SO para o contador visivel da tarefa 4.3.6 — nao re-implementa
 * a regra, so espelha o limite conhecido para UX.
 */
const TEXT_MAX_BYTES = 2048;

/** Copy legivel por `reason` de degradacao de `GET /bridge/interventions` (US3-like, 4o estado obrigatorio). */
export function interventionsDegradedCopy(reason: DegradedReason | string | null): { title: string; subtitle: string } {
  switch (reason) {
    case 'bridge_unavailable':
      return {
        title: 'Ponte de intervenções indisponível',
        subtitle: 'bridge.db está ausente ou ilegível no momento — nenhuma intervenção foi perdida, apenas a leitura falhou.',
      };
    default:
      return {
        title: 'Fila de intervenções indisponível no momento',
        subtitle: 'Tente novamente em instantes.',
      };
  }
}

/** Rotulo legivel por tipo de intervencao (FR-015). */
export function kindLabel(kind: InterventionKind | string): string {
  switch (kind) {
    case 'choice': return 'Escolha';
    case 'confirm': return 'Confirmação';
    case 'text': return 'Texto livre';
    default: return kind;
  }
}

const KIND_COLOR: Record<string, string> = {
  choice: 'var(--accent)',
  confirm: 'var(--warning)',
  text: 'var(--inprogress)',
};

/** Cor do badge de tipo — usada tambem pelo teste de distincao visual (task 4.3.4/4.3.7). */
export function kindColor(kind: InterventionKind | string): string {
  return KIND_COLOR[kind] ?? 'var(--text-3)';
}

/**
 * Byte-length UTF-8 do texto (o teto do servidor e em BYTES, nao em
 * caracteres — evita contador enganoso com emoji/acentos multi-byte).
 */
export function utf8ByteLength(s: string): number {
  return new TextEncoder().encode(s).length;
}

/**
 * Validacao de UX (nao-autoritativa — o servidor SEMPRE revalida, FR-005).
 * So habilita o botao de enviar quando o preenchimento e plausivel por
 * `kind`; nunca bloqueia uma submissao que o servidor aceitaria.
 */
export function isAnswerReady(
  kind: InterventionKind | string,
  value: string,
  text: string
): boolean {
  if (kind === 'choice') return value !== '';
  if (kind === 'confirm') return value === 'yes' || value === 'no';
  if (kind === 'text') return value !== '' && utf8ByteLength(text) <= TEXT_MAX_BYTES;
  return false;
}

function ProvenanceLine({ item }: { item: InterventionQueueItemDTO }) {
  return (
    <div className="row gap-2" style={{ fontSize: 11, color: 'var(--text-2)', fontFamily: 'var(--font-mono)' }}>
      <span>{item.project}</span>
      {item.shortName && <><span style={{ color: 'var(--text-3)' }}>/</span><span>{item.shortName}</span></>}
      <span style={{ color: 'var(--text-3)' }}>·</span>
      <span>{item.executionKind}</span>
    </div>
  );
}

function AnswerForm({ item }: { item: InterventionQueueItemDTO }) {
  const [value, setValue] = useState('');
  const [text, setText] = useState('');
  const mutation = useAnswerIntervention();

  const disabled = !item.reachable || mutation.isPending;
  const ready = isAnswerReady(item.kind, value, text);

  const submit = () => {
    if (!ready || disabled) return;
    mutation.mutate({
      questionId: item.questionId,
      resolution: 'answered',
      value,
      text: item.kind === 'text' ? text : null,
    });
  };

  return (
    <div className="col gap-2" style={{ marginTop: 8 }}>
      {item.kind === 'choice' && (
        <div className="row gap-2" style={{ flexWrap: 'wrap' }}>
          {(item.options ?? []).map((opt) => (
            <button
              key={opt}
              disabled={disabled}
              onClick={() => setValue(opt)}
              style={{
                background: value === opt ? 'var(--accent)' : 'var(--bg-2)',
                color: value === opt ? 'var(--bg-0)' : 'var(--text-1)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--r-xs)', padding: '4px 10px', fontSize: 11.5,
                cursor: disabled ? 'default' : 'pointer',
              }}
            >
              <TextRaw value={opt} maxLength={48} />
            </button>
          ))}
        </div>
      )}

      {item.kind === 'confirm' && (
        <div className="row gap-2">
          <button
            disabled={disabled}
            onClick={() => setValue('yes')}
            style={{
              background: value === 'yes' ? 'var(--success)' : 'var(--bg-2)',
              color: value === 'yes' ? 'var(--bg-0)' : 'var(--text-1)',
              border: '1px solid var(--border)', borderRadius: 'var(--r-xs)',
              padding: '4px 14px', fontSize: 11.5, cursor: disabled ? 'default' : 'pointer',
            }}
          >
            Sim
          </button>
          <button
            disabled={disabled}
            onClick={() => setValue('no')}
            style={{
              background: value === 'no' ? 'var(--critical)' : 'var(--bg-2)',
              color: value === 'no' ? 'var(--bg-0)' : 'var(--text-1)',
              border: '1px solid var(--border)', borderRadius: 'var(--r-xs)',
              padding: '4px 14px', fontSize: 11.5, cursor: disabled ? 'default' : 'pointer',
            }}
          >
            Não
          </button>
        </div>
      )}

      {item.kind === 'text' && (
        <div className="col gap-1">
          <textarea
            className="input"
            disabled={disabled}
            value={text}
            onChange={(e) => { setText(e.target.value); setValue(e.target.value.length > 0 ? 'answered' : ''); }}
            placeholder="Resposta em texto livre…"
            rows={2}
            style={{ resize: 'vertical', fontSize: 12 }}
          />
          <span
            style={{
              fontSize: 10.5, fontFamily: 'var(--font-mono)', alignSelf: 'flex-end',
              color: utf8ByteLength(text) > TEXT_MAX_BYTES ? 'var(--critical)' : 'var(--text-3)',
            }}
          >
            {utf8ByteLength(text)} / {TEXT_MAX_BYTES} bytes
          </span>
        </div>
      )}

      <div className="row gap-2">
        <button
          disabled={disabled || !ready}
          onClick={submit}
          style={{
            background: (disabled || !ready) ? 'var(--bg-2)' : 'var(--accent)',
            color: (disabled || !ready) ? 'var(--text-3)' : 'var(--bg-0)',
            border: 'none', borderRadius: 'var(--r-xs)', padding: '5px 14px',
            fontSize: 11.5, fontWeight: 600, cursor: (disabled || !ready) ? 'default' : 'pointer',
          }}
        >
          {mutation.isPending ? 'Enviando…' : 'Responder'}
        </button>
        {!item.reachable && (
          <span style={{ fontSize: 11, color: 'var(--text-3)' }}>
            Projeto não encontrado em disco — resposta desabilitada.
          </span>
        )}
        {mutation.isError && (
          <span style={{ fontSize: 11, color: 'var(--critical)' }}>
            {mutation.error?.message ?? 'Falha ao enviar resposta.'}
          </span>
        )}
      </div>
    </div>
  );
}

function InterventionCard({ item }: { item: InterventionQueueItemDTO }) {
  return (
    <div className="card" style={{ padding: 14 }}>
      <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div className="col gap-1" style={{ flex: 1 }}>
          <ProvenanceLine item={item} />
          <div style={{ fontSize: 13, color: 'var(--text-0)', marginTop: 2 }}>
            <TextRaw value={item.question} />
          </div>
        </div>
        <div className="col gap-1" style={{ alignItems: 'flex-end' }}>
          <span
            style={{
              padding: '2px 7px', borderRadius: 8, fontSize: 10.5, fontWeight: 600,
              fontFamily: 'var(--font-mono)',
              background: `${kindColor(item.kind)}22`, color: kindColor(item.kind),
            }}
          >
            {kindLabel(item.kind)}
          </span>
          <span
            title={fmtTimestamp(item.createdAt)}
            style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}
          >
            aguardando {fmtMs(item.waitingMs)}
          </span>
        </div>
      </div>

      <div style={{ fontSize: 11, color: 'var(--text-2)', marginTop: 6 }}>
        Se ninguém responder até {fmtRelative(item.expiresAt)}, aplica-se o padrão:{' '}
        <span style={{ color: 'var(--text-1)', fontWeight: 500 }}>
          <TextRaw value={item.defaultValue} maxLength={80} />
        </span>
      </div>

      {item.state === 'open' ? (
        <AnswerForm item={item} />
      ) : (
        // A fila desta tela filtra `state=open` no servidor (default),
        // mas uma resposta pode ter sido aplicada por OUTRO cliente entre
        // o fetch e a exibicao (polling), ou o item pode ter expirado no
        // meio do ciclo — nesse caso mostramos o desfecho em vez do
        // formulario. `untrustedText`/`appliedValue` seguem o MESMO
        // tratamento de `question` (TextRaw, nunca HTML cru).
        <div className="row gap-2" style={{ marginTop: 8, fontSize: 11.5, color: 'var(--text-2)' }}>
          <span>{item.state === 'expired' ? 'Expirou sem resposta' : 'Já respondida'}:</span>
          <span style={{ color: 'var(--text-0)', fontWeight: 500 }}>
            <TextRaw value={item.appliedValue} maxLength={80} />
          </span>
          {item.untrustedText != null && (
            <span style={{ color: 'var(--text-1)' }}>
              (<TextRaw value={item.untrustedText} maxLength={120} />)
            </span>
          )}
        </div>
      )}
    </div>
  );
}

export function Interventions() {
  const query = useInterventions();
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(query);

  if (isLoading) return <LoadingState variant="table" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar intervenções.'} />;

  const meta = query.data?.meta;
  const data = query.data?.data;

  if (isDegraded) {
    const copy = interventionsDegradedCopy(meta?.reason ?? null);
    return (
      <div className="col gap-4">
        {meta && <DegradedBanner meta={meta} />}
        <EmptyState title={copy.title} subtitle={copy.subtitle} />
      </div>
    );
  }

  const interventions: InterventionQueueItemDTO[] = data?.interventions ?? [];

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Intervenções</h1>
          <div className="sub">
            Fila cross-projeto de perguntas pendentes de agentes autônomos · atualiza automaticamente
          </div>
        </div>
        <span style={{ background: 'var(--bg-3)', color: 'var(--text-1)', fontSize: 10, fontWeight: 600, fontFamily: 'var(--font-mono)', padding: '1px 7px', borderRadius: 10 }}>
          {interventions.length}
        </span>
      </div>

      {interventions.length === 0 ? (
        <EmptyState
          title="Nenhuma intervenção pendente"
          subtitle="Nenhum agente autônomo está aguardando resposta humana neste momento."
        />
      ) : (
        <div className="col gap-3">
          {interventions.map((item) => (
            <InterventionCard key={item.questionId} item={item} />
          ))}
        </div>
      )}
    </div>
  );
}
