/**
 * ModelUsage — apresentacao do custo/tokens REAIS por modelo (schema v12,
 * `wave_model_usage`, cstk >= 5.33.0).
 *
 * Consome o view-model puro de `lib/model-usage-select.ts` (selectModelUsage),
 * que ja resolve estado (`degraded`/`empty`/`measured`) e ordenacao
 * (`costUsd` desc, `null` por ultimo). Este arquivo so apresenta — segue o
 * mesmo precedente de `OtelUsage.tsx`/`AgentUsage.tsx` (helpers puros +
 * componentes, sem duplicar a regra de selecao).
 *
 * `ModelUsageMiniList` e o resumo compacto do dashboard principal (FASE 3.2,
 * dec-038/CHK005 — top-3 modelos por `costUsd`, so o campo `costUsd`
 * exibido). O detalhe completo (custoUsd+totalTokens+coverage) fica na
 * página de Métricas (FASE 3.3, ainda não implementada).
 *
 * Principio III (Honestidade de Metrica): `costUsd` aqui e MEDIDO
 * (`sum(cost_usd)` sobre telemetria real) — rotulo fixo "medido"
 * (`MODEL_USAGE_NATURE_LABEL`), nunca confundido com o proxy `tool_calls`
 * nem com o mix de modelos DERIVADO de `decisions.choice`.
 */
import type { ModelUsageVM, ModelUsageEntryVM } from '@/lib/model-usage-select.js';
import { modelUsageCoverageLabel, MODEL_USAGE_NATURE_LABEL } from '@/lib/model-usage-select.js';
import { fmtUsd } from './OtelUsage.js';
import { Icon } from './Icon.js';

// Mesma paleta usada no Mix de modelos (Overview.tsx) — mantida aqui em vez
// de importada para nao criar acoplamento entre os dois cards; os dois
// concordam nas 3 chaves conhecidas (haiku/sonnet/opus).
const MODEL_COLOR: Record<string, string> = {
  haiku: 'var(--model-haiku)',
  sonnet: 'var(--model-sonnet)',
  opus: 'var(--model-opus)',
};

/**
 * Cor segura por modelo. `model` e string BRUTA de telemetria externa (ver
 * contracts/model-usage-endpoint.md invariante 9) — `Object.hasOwn` evita que
 * uma chave da cadeia de protótipo (`constructor`, `toString`, `__proto__`)
 * escape do lookup, antecipando a mesma defesa que o gate de segurança exige
 * para o card de detalhe (3.3.5, invariante 10).
 */
export function modelUsageColor(model: string): string {
  return Object.hasOwn(MODEL_COLOR, model) ? MODEL_COLOR[model]! : 'var(--model-fallback)';
}

/**
 * Estado "sem dado" do resumo de custo por modelo — distingue "período sem
 * uso registrado" (tabela presente, zero linhas) de "fonte não coleta este
 * dado" (schema v2-v11, tabela `wave_model_usage` ausente). US1 Acceptance
 * Scenario 2: nunca aparece como zero.
 */
export function ModelUsageEmpty({ reason }: { reason: 'empty' | 'degraded' }) {
  if (reason === 'degraded') {
    return (
      <div className="col gap-2" style={{ padding: '10px 0' }}>
        <div className="row gap-2" style={{ color: 'var(--text-2)', fontSize: 12 }}>
          <Icon name="alert" size={12} aria-hidden />
          Custo por modelo não coletado nesta fonte.
        </div>
        <div style={{ fontSize: 11, color: 'var(--text-3)', lineHeight: 1.5 }}>
          Exige knowledge.db em schema v12 (cstk ≥ 5.33.0) com a tabela{' '}
          <span style={{ fontFamily: 'var(--font-mono)' }}>wave_model_usage</span>.
          Execuções anteriores não são retroalimentadas.
        </div>
      </div>
    );
  }
  return (
    <div style={{ color: 'var(--text-3)', fontSize: 12, textAlign: 'center', padding: '12px 0' }}>
      Nenhum modelo com uso registrado neste período.
    </div>
  );
}

/** Uma linha do resumo compacto: cor · modelo · custoUsd (medido). */
function ModelUsageMiniRow({ entry }: { entry: ModelUsageEntryVM }) {
  return (
    <div className="row" style={{ justifyContent: 'space-between' }}>
      <div className="row gap-2" style={{ minWidth: 0 }}>
        <span
          aria-hidden
          style={{ width: 8, height: 8, borderRadius: 2, background: modelUsageColor(entry.model), flexShrink: 0 }}
        />
        <span
          className="mono"
          style={{ fontSize: 11.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
        >
          {entry.model}
        </span>
      </div>
      <span className="mono tnum" style={{ fontSize: 12, color: 'var(--text-0)', flexShrink: 0 }}>
        {fmtUsd(entry.costUsd)}
      </span>
    </div>
  );
}

/**
 * Resumo compacto do dashboard principal (Overview) — top-3 modelos por
 * `costUsd` (dec-038/CHK005), rótulo "medido" sempre visível junto da
 * cobertura da amostra. Os 3 estados (`measured`/`empty`/`degraded`) nunca
 * colapsam visualmente: `empty`/`degraded` usam `ModelUsageEmpty`, nunca "$0".
 */
export function ModelUsageMiniList({ vm }: { vm: ModelUsageVM }) {
  if (vm.state !== 'measured') return <ModelUsageEmpty reason={vm.state} />;
  return (
    <div className="col gap-2">
      {vm.top.map((entry) => (
        <ModelUsageMiniRow key={entry.model} entry={entry} />
      ))}
      <div className="row" style={{ justifyContent: 'flex-end', marginTop: 4 }}>
        <span
          style={{
            padding: '1px 7px', borderRadius: 8, fontSize: 10, fontWeight: 600,
            fontFamily: 'var(--font-mono)', whiteSpace: 'nowrap',
            background: 'var(--bg-3)', color: 'var(--text-2)',
          }}
        >
          {MODEL_USAGE_NATURE_LABEL} · {modelUsageCoverageLabel(vm.coverage)}
        </span>
      </div>
    </div>
  );
}
