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
 * exibido). `ModelUsageDetailPanel` e o detalhe completo
 * (`costUsd`+`totalTokens`+`coverage` por modelo, mais o recorte por etapa)
 * da página de Métricas (FASE 3.3).
 *
 * Principio III (Honestidade de Metrica): `costUsd` aqui e MEDIDO
 * (`sum(cost_usd)` sobre telemetria real) — rotulo fixo "medido"
 * (`MODEL_USAGE_NATURE_LABEL`), nunca confundido com o proxy `tool_calls`
 * nem com o mix de modelos DERIVADO de `decisions.choice`. Nenhum componente
 * abaixo soma `costUsd` com `tool_calls`/`agent_*` (3.3.3) — so os campos do
 * `ModelUsageResult`.
 */
import type { ModelUsageVM, ModelUsageEntryVM, ModelUsageByStageGroup } from '@/lib/model-usage-select.js';
import { modelUsageCoverageLabel, modelUsageStageLabel, MODEL_USAGE_NATURE_LABEL } from '@/lib/model-usage-select.js';
import type { ModelUsageCoverage } from '@cstk-panel/shared-types';
import { fmtUsd } from './OtelUsage.js';
import { fmtTokens } from '@/lib/format.js';
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

// ---------------------------------------------------------------------------
// Detalhe completo (página de Métricas, FASE 3.3 — US1 Cenário 3, SC-004/005)
// ---------------------------------------------------------------------------

/**
 * Uma linha do detalhe por modelo: cor + rótulo textual do modelo (redundante
 * à cor, nunca só-cor — decisão 1.2.3/CHK007) + tokens + custo. Reusa
 * `modelUsageColor` (Object.hasOwn-safe, 3.3.5) em vez de duplicar o
 * mapeamento cor→modelo.
 */
function ModelUsageDetailRow({ entry }: { entry: ModelUsageEntryVM }) {
  return (
    <div className="row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
      <div className="row gap-2" style={{ minWidth: 0 }}>
        <span
          aria-hidden
          style={{ width: 8, height: 8, borderRadius: 2, background: modelUsageColor(entry.model), flexShrink: 0 }}
        />
        <span
          className="mono"
          style={{ fontSize: 12, color: 'var(--text-0)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
        >
          {entry.model}
        </span>
      </div>
      <div className="row gap-3" style={{ flexShrink: 0 }}>
        <span className="mono tnum" style={{ fontSize: 11, color: 'var(--text-2)' }}>{fmtTokens(entry.totalTokens)}</span>
        <span className="mono tnum" style={{ fontSize: 12, color: 'var(--text-0)', minWidth: 68, textAlign: 'right' }}>
          {fmtUsd(entry.costUsd)}
        </span>
      </div>
    </div>
  );
}

/**
 * Recorte por etapa do pipeline — agrupado por `groupModelUsageByStage`
 * (lib/model-usage-select.ts). `groups: []` acontece quando a correlação
 * onda × etapa não resolve dado confiável no recorte (contrato §byStage) —
 * distinto de "sem uso no período" (vm.state === 'empty'), por isso tem
 * mensagem própria em vez de reusar `ModelUsageEmpty`.
 */
export function ModelUsageStageBreakdown({ groups }: { groups: ModelUsageByStageGroup[] }) {
  if (groups.length === 0) {
    return (
      <div style={{ fontSize: 11, color: 'var(--text-3)', padding: '4px 0' }}>
        Sem correlação onda × etapa confiável para este recorte.
      </div>
    );
  }
  return (
    <div className="col gap-3">
      {groups.map((g) => {
        // `g.stage` e string BRUTA de `waves.stages` — ha ondas na base real
        // que gravaram um resumo narrativo inteiro nessa coluna. O cabecalho
        // usa o rotulo normalizado (`modelUsageStageLabel`); o valor bruto so
        // sobrevive encurtado no `title`, nunca no fluxo do layout.
        const label = modelUsageStageLabel(g.stage);
        return (
        <div key={g.stage} className="col gap-1">
          <div
            className="mono"
            title={label.valid ? undefined : label.rawPreview}
            style={{
              fontSize: 10, letterSpacing: '0.06em',
              color: label.valid ? 'var(--text-2)' : 'var(--text-3)',
              textTransform: label.valid ? 'uppercase' : 'none',
              fontStyle: label.valid ? 'normal' : 'italic',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            }}
          >
            {label.text}
          </div>
          {g.entries.map((e) => (
            <div key={`${g.stage}-${e.model}`} className="row" style={{ justifyContent: 'space-between' }}>
              <div className="row gap-2" style={{ minWidth: 0 }}>
                <span
                  aria-hidden
                  style={{ width: 8, height: 8, borderRadius: 2, background: modelUsageColor(e.model), flexShrink: 0 }}
                />
                <span
                  className="mono"
                  style={{ fontSize: 11.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                >
                  {e.model}
                </span>
              </div>
              <span className="mono tnum" style={{ fontSize: 12, color: 'var(--text-0)', flexShrink: 0 }}>
                {fmtUsd(e.costUsd)}
              </span>
            </div>
          ))}
        </div>
        );
      })}
    </div>
  );
}

/**
 * Cobertura com os 3 denominadores INDEPENDENTES (research.md Decision 3;
 * 3.3.2/CHK005) — distinto do rótulo de 1 denominador do resumo compacto
 * (`modelUsageCoverageLabel`, usado por `ModelUsageMiniList`). Os dois
 * denominadores (`wavesWithModelUsage` vs. `wavesWithOtelCost`) podem
 * divergir sobre o mesmo `wavesTotal` (ex.: 36 vs. 46 sobre 920) — isso é
 * esperado e nunca fundido num único número.
 */
function ModelUsageCoverageDetail({ coverage }: { coverage: ModelUsageCoverage }) {
  if (coverage.wavesTotal == null) return null;
  return (
    <div className="col gap-1" style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
      <div>{coverage.wavesWithModelUsage ?? 0} de {coverage.wavesTotal} ondas com breakdown por modelo (wave_model_usage)</div>
      <div>{coverage.wavesWithOtelCost ?? 0} de {coverage.wavesTotal} ondas com custo agregado (otel-usage) — denominador independente, pode divergir</div>
    </div>
  );
}

/**
 * Detalhe completo por modelo e por etapa (Métricas, FASE 3.3). Consome o
 * MESMO `ModelUsageVM` de `selectModelUsage()` usado pelo resumo compacto do
 * Overview (SC-005: garante os mesmos valores nas duas telas) — nenhuma
 * regra de seleção nova nasce aqui, só apresentação. Os 4 estados nunca
 * colapsam visualmente: `measured` (inclusive quando algum modelo tem
 * `costUsd === 0`, exibido como "$0" — nunca confundido com `empty`/
 * `degraded`, que usam `ModelUsageEmpty`).
 */
export function ModelUsageDetailPanel({ vm, stageGroups }: { vm: ModelUsageVM; stageGroups: ModelUsageByStageGroup[] }) {
  if (vm.state !== 'measured') return <ModelUsageEmpty reason={vm.state} />;
  return (
    <div className="col gap-4">
      <div className="col gap-2">
        <div
          className="mono"
          style={{ fontSize: 10.5, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.05em' }}
        >
          Por modelo · {MODEL_USAGE_NATURE_LABEL}
        </div>
        {vm.entries.map((entry) => (
          <ModelUsageDetailRow key={entry.model} entry={entry} />
        ))}
      </div>
      <div className="col gap-2">
        <div
          className="mono"
          style={{ fontSize: 10.5, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.05em' }}
        >
          Por etapa do pipeline
        </div>
        <ModelUsageStageBreakdown groups={stageGroups} />
      </div>
      <ModelUsageCoverageDetail coverage={vm.coverage} />
    </div>
  );
}
