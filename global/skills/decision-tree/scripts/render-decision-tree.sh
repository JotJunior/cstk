#!/bin/sh
# render-decision-tree.sh — gera um relatorio HTML interativo em forma de
# ARVORE DE DECISAO a partir do `state.json` de uma execucao do orquestrador
# agente-00c / feature-00c.
#
# A arvore representa, cronologicamente, o caminho percorrido pela IA: cada
# Decisao de `.decisoes[]` vira um no; dele saem galhos para todas as
# `opcoes_consideradas`; o galho da `escolha` (tronco verde) emenda no no da
# Decisao seguinte, de `dec-001` ate a ultima, terminando num no de conclusao.
#
# Ref schema (state.json):
#   .decisoes[] = { id, onda_id, etapa, contexto, opcoes_consideradas[],
#                   escolha, justificativa, score_justificativa }
#   .execucao    = { id, projeto_alvo_descricao, status }
#
# Subcomandos:
#   render-decision-tree.sh render --state PATH [--output FILE] [--title STR]
#       — Le PATH (state.json), extrai `.decisoes[]` e emite o HTML.
#         Sem --output: HTML vai para stdout.
#         Com --output FILE: grava em FILE (e stdout fica vazio).
#       — Read-only sobre o state.json (nunca o modifica).
#       — Deterministico: nao embute timestamp no payload, logo o mesmo
#         state.json produz o mesmo HTML byte-a-byte (testavel).
#
#   render-decision-tree.sh -h | --help
#       — Imprime USO em stderr e exit 2 (padrao do dispatch do runtime).
#
# Exit codes:
#   0 sucesso
#   1 erro generico (state.json ausente/invalido, jq ausente, .decisoes vazio)
#   2 uso incorreto (flag ausente, subcomando desconhecido)
#
# Invariantes:
#   IDT-1: read-only sobre state.json — jq sem -i, sem redirect ao arquivo.
#   IDT-2: deterministico — sem timestamps no payload; mesmo input -> mesmo
#          output byte-a-byte.
#   IDT-3: POSIX puro (#!/bin/sh, set -eu, sem bash-isms); depende apenas de
#          jq, sed, printf, cat, command.
#   IDT-4: a renderizacao (SVG) roda no navegador a partir do payload JSON
#          embutido — o shell apenas extrai dados + injeta no template.
#
# POSIX sh + jq.

set -eu

_DT_NAME="render-decision-tree"

# ---------- Helpers privados ----------

_dt_die_usage() {
  printf '%s: %s\n' "$_DT_NAME" "$1" >&2
  _dt_print_usage >&2
  exit 2
}

_dt_die() {
  printf '%s: %s\n' "$_DT_NAME" "$1" >&2
  exit "${2:-1}"
}

_dt_print_usage() {
  cat <<'EOF'
USO:
  render-decision-tree.sh render --state PATH [--output FILE] [--title STR]
  render-decision-tree.sh -h | --help

Gera um HTML interativo com a arvore de decisoes de um state.json do
orquestrador agente-00c/feature-00c (campo .decisoes[]).
EOF
}

_dt_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _dt_die "jq nao encontrado no PATH" 1
}

# ---------- Programa jq: state.json -> payload {meta, decisoes} ----------
#
# Mapeia cada Decisao para o formato consumido pelo renderer no navegador.
_dt_jq_program() {
  cat <<'JQ'
{
  meta: {
    total:   ((.decisoes // []) | length),
    execucao:(.execucao.id // ""),
    projeto: (.execucao.projeto_alvo_descricao // ""),
    status:  (.execucao.status // "")
  },
  decisoes: ((.decisoes // []) | map({
    id:       (.id // ""),
    onda:     (.onda_id // ""),
    etapa:    (.etapa // ""),
    contexto: (.contexto // ""),
    opcoes:   (.opcoes_consideradas // []),
    escolha:  (.escolha // ""),
    score:    (.score_justificativa),
    justif:   (.justificativa // "")
  }))
}
JQ
}

# ---------- Subcomando: render ----------

_dt_cmd_render() {
  _dt_state=""
  _dt_output=""
  _dt_title=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --state)
        [ $# -ge 2 ] || _dt_die_usage "--state requer um caminho"
        _dt_state="$2"; shift 2 ;;
      --output)
        [ $# -ge 2 ] || _dt_die_usage "--output requer um caminho"
        _dt_output="$2"; shift 2 ;;
      --title)
        [ $# -ge 2 ] || _dt_die_usage "--title requer um valor"
        _dt_title="$2"; shift 2 ;;
      *)
        _dt_die_usage "argumento desconhecido: $1" ;;
    esac
  done

  [ -n "$_dt_state" ] || _dt_die_usage "--state e obrigatorio"
  _dt_require_jq
  [ -f "$_dt_state" ] || _dt_die "state.json nao encontrado: $_dt_state" 1
  jq -e . "$_dt_state" >/dev/null 2>&1 \
    || _dt_die "state.json invalido (JSON ilegivel): $_dt_state" 1

  _dt_count=$(jq '(.decisoes // []) | length' "$_dt_state")
  [ "$_dt_count" -gt 0 ] \
    || _dt_die "nenhuma decisao encontrada em .decisoes[]" 1

  # Payload JSON compacto. O sed escapa '</' para '<\/' de modo que nenhuma
  # string (ex: contexto) possa fechar a tag <script> prematuramente. '<\/'
  # continua sendo JSON/JS valido.
  _dt_payload=$(jq -c "$(_dt_jq_program)" "$_dt_state" | sed 's,</,<\\/,g')

  # Titulo opcional (default derivado do payload, no proprio HTML).
  _dt_title_js="null"
  if [ -n "$_dt_title" ]; then
    _dt_title_js=$(printf '%s' "$_dt_title" | jq -R -s '.')
  fi

  if [ -n "$_dt_output" ]; then
    _dt_emit "$_dt_payload" "$_dt_title_js" > "$_dt_output" \
      || _dt_die "falha ao gravar em $_dt_output" 1
    printf '%s: HTML gerado em %s (%s decisoes)\n' \
      "$_DT_NAME" "$_dt_output" "$_dt_count" >&2
  else
    _dt_emit "$_dt_payload" "$_dt_title_js"
  fi
}

# _dt_emit PAYLOAD_JSON TITLE_JS — imprime o HTML completo no stdout.
_dt_emit() {
  _e_payload="$1"
  _e_title="$2"

  cat <<'DT_HTML_HEAD'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Árvore de decisões</title>
<style>
  :root{
    --bg:#0d1117; --panel:#161b22; --panel2:#1c2128; --border:#30363d;
    --text:#e6edf3; --muted:#8b949e;
    --trunk:#2ea043; --chosen-bg:#0f2a16; --chosen-border:#3fb950;
    --rej:#484f58; --rej-bg:#171b21; --rej-text:#7d8590; --edge:#30363d;
  }
  *{box-sizing:border-box;}
  html,body{margin:0;height:100%;}
  body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;}
  header{position:fixed;top:0;left:0;right:0;z-index:60;background:rgba(13,17,23,.93);backdrop-filter:blur(8px);border-bottom:1px solid var(--border);padding:12px 22px;}
  header h1{margin:0;font-size:16px;}
  header p{margin:3px 0 0;color:var(--muted);font-size:12px;max-width:980px;}
  .legend{display:flex;gap:16px;flex-wrap:wrap;margin-top:8px;font-size:11.5px;color:var(--muted);align-items:center;}
  .legend .key{display:inline-flex;align-items:center;gap:6px;}
  .sw{width:22px;border-top-width:3px;border-top-style:solid;display:inline-block;}
  .dot{width:11px;height:11px;border-radius:3px;display:inline-block;}
  .zoom{position:fixed;bottom:18px;left:18px;z-index:60;display:flex;gap:6px;}
  .zoom button{width:38px;height:38px;border-radius:9px;border:1px solid var(--border);background:var(--panel);color:var(--text);font-size:18px;cursor:pointer;}
  .zoom button:hover{border-color:var(--chosen-border);}
  #scroll{position:absolute;top:0;left:0;right:0;bottom:0;overflow:auto;padding-top:120px;}
  svg{display:block;margin:0 auto;}
  .decBox{cursor:pointer;}
  .decBox rect{fill:var(--panel);stroke:var(--border);stroke-width:1.5;transition:stroke .12s,fill .12s;}
  .decBox:hover rect,.decBox.active rect{stroke:#79c0ff;fill:var(--panel2);}
  .decId{font:700 12px ui-monospace,Menlo,monospace;}
  .decEtapa{font:11px ui-monospace,Menlo,monospace;fill:var(--muted);}
  .decCtx{font:11px -apple-system,sans-serif;fill:#c9d1d9;}
  .opt{cursor:pointer;}
  .opt.rej rect{fill:var(--rej-bg);stroke:var(--rej);stroke-width:1;}
  .opt.cho rect{fill:var(--chosen-bg);stroke:var(--chosen-border);stroke-width:2;}
  .opt.rej text{fill:var(--rej-text);font:11px ui-monospace,monospace;}
  .opt.cho text{fill:#aff5b4;font:600 11px ui-monospace,monospace;}
  .opt:hover rect{stroke:#79c0ff;}
  .optMark{font:700 12px monospace;}
  .opt.cho .optMark{fill:var(--chosen-border);}
  .opt.rej .optMark{fill:var(--rej);}
  .scoreTag{font:700 10px -apple-system,sans-serif;}
  .phaseLabel text{font:700 11px -apple-system,sans-serif;letter-spacing:.4px;}
  #panel{position:fixed;top:120px;right:0;bottom:0;width:380px;z-index:55;background:var(--panel);border-left:1px solid var(--border);padding:18px 18px 40px;overflow:auto;transform:translateX(100%);transition:transform .18s ease;}
  #panel.open{transform:translateX(0);}
  #panel .close{position:absolute;top:12px;right:14px;cursor:pointer;color:var(--muted);font-size:20px;background:none;border:none;}
  #panel h3{margin:0 0 2px;font:700 13px ui-monospace,monospace;color:#79c0ff;}
  #panel .sub{color:var(--muted);font-size:11.5px;margin-bottom:14px;}
  #panel .lbl{font:700 10.5px -apple-system,sans-serif;text-transform:uppercase;letter-spacing:.6px;color:var(--muted);margin:16px 0 7px;}
  #panel .ctx{font-size:12.5px;color:#c9d1d9;}
  #panel .pill{display:flex;align-items:center;gap:8px;border-radius:8px;padding:7px 10px;margin-bottom:6px;font:12px ui-monospace,monospace;border:1px solid var(--border);background:var(--panel2);word-break:break-word;}
  #panel .pill.cho{border-color:var(--chosen-border);background:var(--chosen-bg);color:#aff5b4;}
  #panel .pill.rej{color:var(--rej-text);}
  #panel .pill .m{font-weight:700;}
  #panel .pill.cho .m{color:var(--chosen-border);}
  #panel .pill.rej .m{color:var(--rej);}
  #panel .just{font-size:12px;color:#c9d1d9;border-left:3px solid var(--chosen-border);padding:9px 12px;background:var(--panel2);border-radius:0 8px 8px 0;}
  #panel .scoreLine{margin-top:10px;font-size:12px;}
  #panel .scoreLine b{padding:2px 8px;border-radius:6px;}
  .s3{background:#2ea043;color:#fff;} .s2{background:#d29922;color:#1c1300;} .s1{background:#6e7681;color:#fff;}
  .hint{position:fixed;bottom:18px;right:18px;z-index:60;color:var(--muted);font-size:11px;background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:6px 12px;}
  @media (max-width:900px){#panel{width:100%;}}
</style>
</head>
<body>
<header>
  <h1 id="docTitle">Árvore de decisões</h1>
  <p id="docSub"></p>
  <div class="legend">
    <span class="key"><span class="sw" style="border-top-color:var(--trunk);"></span> tronco = caminho escolhido</span>
    <span class="key"><span class="dot" style="background:var(--chosen-bg);border:1px solid var(--chosen-border);"></span> opção escolhida</span>
    <span class="key"><span class="dot" style="background:var(--rej-bg);border:1px solid var(--rej);"></span> opção descartada</span>
  </div>
</header>
<div id="scroll"><div id="canvas"></div></div>
<div class="zoom">
  <button id="zin">+</button><button id="zout">−</button>
  <button id="zfit" title="ajustar à largura" style="font-size:15px;">⤢</button>
</div>
<div class="hint">passe o mouse ou clique em um nó para ver os detalhes</div>
<div id="panel"><button class="close" id="panelClose">×</button><div id="panelContent"></div></div>
<script>
const PAYLOAD =
DT_HTML_HEAD

  printf '%s;\n' "$_e_payload"
  printf 'const TITLE_OVERRIDE = %s;\n' "$_e_title"

  cat <<'DT_HTML_TAIL'
const DECISIONS = PAYLOAD.decisoes;
const META = PAYLOAD.meta;

// cabecalho
document.getElementById('docTitle').textContent =
  TITLE_OVERRIDE || 'Árvore de decisões' + (META.execucao ? ' — ' + META.execucao : '');
document.getElementById('docSub').textContent =
  (META.projeto ? META.projeto + '  ·  ' : '') +
  META.total + ' decisões' + (META.status ? '  ·  status: ' + META.status : '');

// paleta de fases: mapa conhecido + fallback ciclico por ordem de aparicao
const KNOWN_PHASES = {
  "specify":"#2f81f7","clarify":"#a371f7","plan":"#db61a2","checklist":"#f0883e",
  "create-tasks":"#e3b341","execute-task":"#2ea043","review-task":"#1f6feb",
  "analyze":"#56d364","constitution":"#bc8cff","briefing":"#79c0ff"
};
const FALLBACK_PALETTE = ["#3fb950","#d29922","#58a6ff","#db61a2","#f0883e","#a371f7","#e3b341","#56d364"];
const _phaseColors = {};
let _fbIdx = 0;
function phaseColor(etapa){
  if(KNOWN_PHASES[etapa]) return KNOWN_PHASES[etapa];
  // prefixo conhecido (ex: execute-task-F6.1 -> execute-task)
  for(const k in KNOWN_PHASES){ if(etapa.indexOf(k)===0) return KNOWN_PHASES[k]; }
  if(!(etapa in _phaseColors)){ _phaseColors[etapa]=FALLBACK_PALETTE[_fbIdx++ % FALLBACK_PALETTE.length]; }
  return _phaseColors[etapa];
}

// geometria
const VW=1180, AXIS=540, NODE_W=300, NODE_H=44;
const PILL_W=196, PILL_GAP=20, PILL_H=34, PHASE_H=40, ROW_H=178, TOP_PAD=24;
const MAX_GROUP=VW-100;

function trunc(s,n){ s=String(s); return s.length>n ? s.slice(0,n-1)+"…" : s; }
function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

// posicoes verticais + por-linha
let y=TOP_PAD, lastPhase=null;
const layout=[];
DECISIONS.forEach((d,i)=>{
  if(d.etapa!==lastPhase){ layout.push({kind:'phase',etapa:d.etapa,y}); y+=PHASE_H; lastPhase=d.etapa; }
  const n=d.opcoes.length;
  d._pw = n>0 ? Math.min(PILL_W, (MAX_GROUP-(n-1)*PILL_GAP)/n) : PILL_W;
  d._nodeY=y;
  d._pillY=y+NODE_H+46;
  const gw = n>0 ? n*d._pw+(n-1)*PILL_GAP : 0;
  const start=AXIS-gw/2+d._pw/2;
  d._optCx=d.opcoes.map((o,k)=>start+k*(d._pw+PILL_GAP));
  d._chosenIdx=d.opcoes.indexOf(d.escolha);
  d._chosenCx=(d._chosenIdx>=0)?d._optCx[d._chosenIdx]:AXIS;
  // ponto de partida do tronco
  if(n>0 && d._chosenIdx>=0){ d._trunkX=d._chosenCx; d._trunkY=d._pillY+PILL_H; }
  else { d._trunkX=AXIS; d._trunkY=d._nodeY+NODE_H; }
  layout.push({kind:'dec',d,i});
  y+=ROW_H;
});
const END_Y=y, TOTAL_H=END_Y+80;

function curveV(x1,y1,x2,y2){ const my=(y1+y2)/2; return `M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}`; }

let phases='',edges='',trunk='',nodes='';

layout.forEach(it=>{
  if(it.kind!=='phase') return;
  const c=phaseColor(it.etapa);
  const label=esc(it.etapa);
  phases+=`<g class="phaseLabel">
    <line x1="40" y1="${it.y+PHASE_H/2}" x2="${VW-40}" y2="${it.y+PHASE_H/2}" stroke="${c}" stroke-opacity="0.25" stroke-width="1"/>
    <rect x="40" y="${it.y+6}" width="${30+label.length*7}" height="26" rx="6" fill="#1c2128" stroke="${c}" stroke-opacity="0.6"/>
    <circle cx="56" cy="${it.y+19}" r="4" fill="${c}"/>
    <text x="70" y="${it.y+23}" fill="${c}">${label}</text>
  </g>`;
});

// tronco cronologico: chosen -> proxima decisao
for(let i=0;i<DECISIONS.length-1;i++){
  const d=DECISIONS[i], nx=DECISIONS[i+1];
  trunk+=`<path d="${curveV(d._trunkX,d._trunkY,AXIS,nx._nodeY)}" fill="none" stroke="var(--trunk)" stroke-width="3.5" stroke-linecap="round" filter="url(#glow)"/>`;
}
{ const d=DECISIONS[DECISIONS.length-1];
  trunk+=`<path d="${curveV(d._trunkX,d._trunkY,AXIS,END_Y+8)}" fill="none" stroke="var(--trunk)" stroke-width="3.5" stroke-linecap="round" filter="url(#glow)"/>`; }

// arestas decisao -> opcoes
DECISIONS.forEach(d=>{
  const nx=AXIS, ny=d._nodeY+NODE_H;
  d.opcoes.forEach((o,k)=>{
    const cx=d._optCx[k], cy=d._pillY, chosen=k===d._chosenIdx;
    edges+=`<path d="${curveV(nx,ny,cx,cy)}" fill="none" stroke="${chosen?'var(--chosen-border)':'var(--edge)'}" stroke-width="${chosen?2.4:1.3}" ${chosen?'':'stroke-dasharray="3 3"'}/>`;
  });
});

function scoreColor(s){ return s===3?'#2ea043':(s===2?'#d29922':(s==null?'#6e7681':'#6e7681')); }

DECISIONS.forEach((d,i)=>{
  const nx=AXIS-NODE_W/2, ny=d._nodeY;
  const scTxt=(d.score==null)?'—':d.score;
  nodes+=`<g class="decBox" data-idx="${i}">
    <rect x="${nx}" y="${ny}" width="${NODE_W}" height="${NODE_H}" rx="10"/>
    <text class="decId" x="${nx+14}" y="${ny+19}" fill="#79c0ff">${esc(d.id)}</text>
    <text class="decEtapa" x="${nx+14}" y="${ny+34}">${esc(d.onda)}</text>
    <rect x="${nx+NODE_W-46}" y="${ny+11}" width="30" height="22" rx="6" fill="${scoreColor(d.score)}"/>
    <text class="scoreTag" x="${nx+NODE_W-31}" y="${ny+26}" text-anchor="middle" fill="${d.score===2?'#1c1300':'#fff'}">${scTxt}</text>
  </g>`;
  nodes+=`<text class="decCtx" x="${AXIS}" y="${ny+NODE_H+18}" text-anchor="middle">${esc(trunc(d.contexto,64))}</text>`;
  d.opcoes.forEach((o,k)=>{
    const cx=d._optCx[k], cy=d._pillY, chosen=k===d._chosenIdx;
    const cap=Math.max(8, Math.floor(d._pw/8));
    nodes+=`<g class="opt ${chosen?'cho':'rej'}" data-idx="${i}">
      <rect x="${cx-d._pw/2}" y="${cy}" width="${d._pw}" height="${PILL_H}" rx="8"/>
      <text class="optMark" x="${cx-d._pw/2+12}" y="${cy+22}">${chosen?'✓':'✗'}</text>
      <text x="${cx-d._pw/2+28}" y="${cy+22}">${esc(trunc(o,cap))}</text>
      <title>${esc(o)}</title>
    </g>`;
  });
});

nodes+=`<g>
  <rect x="${AXIS-160}" y="${END_Y+8}" width="320" height="42" rx="21" fill="#0f2a16" stroke="var(--chosen-border)" stroke-width="2"/>
  <text x="${AXIS}" y="${END_Y+34}" text-anchor="middle" fill="#aff5b4" style="font:700 13px -apple-system,sans-serif;">Fim do caminho — ${esc(META.status||'concluído')}</text>
</g>`;

document.getElementById('canvas').innerHTML =
`<svg id="tree" width="${VW}" height="${TOTAL_H}" viewBox="0 0 ${VW} ${TOTAL_H}" xmlns="http://www.w3.org/2000/svg">
  <defs><filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter></defs>
  ${phases}${edges}${trunk}${nodes}
</svg>`;

// painel
const panel=document.getElementById('panel'), pc=document.getElementById('panelContent');
let pinned=null;
function showDetail(i,pin){
  const d=DECISIONS[i];
  const sc=d.score===3?'s3':(d.score===2?'s2':'s1');
  const opts=d.opcoes.map(o=>{const c=o===d.escolha;return `<div class="pill ${c?'cho':'rej'}"><span class="m">${c?'✓':'✗'}</span><span>${esc(o)}</span></div>`;}).join('') || '<div class="ctx">— sem opções registradas —</div>';
  pc.innerHTML=`<h3>${esc(d.id)}</h3>
    <div class="sub">${esc(d.onda)} · etapa <b>${esc(d.etapa)}</b></div>
    <div class="lbl">Contexto</div><div class="ctx">${esc(d.contexto)}</div>
    <div class="lbl">Opções consideradas (${d.opcoes.length})</div>${opts}
    <div class="lbl">Justificativa da escolha</div><div class="just">${esc(d.justif)||'—'}</div>
    <div class="scoreLine">Score de evidência: <b class="${sc}">${d.score==null?'—':d.score}</b></div>`;
  panel.classList.add('open');
  document.querySelectorAll('.decBox').forEach(n=>n.classList.toggle('active',+n.dataset.idx===i));
  if(pin) pinned=i;
}
function closePanel(){panel.classList.remove('open');pinned=null;document.querySelectorAll('.decBox').forEach(n=>n.classList.remove('active'));}
const canvas=document.getElementById('canvas');
canvas.addEventListener('mouseover',e=>{const g=e.target.closest('[data-idx]'); if(g&&pinned===null) showDetail(+g.dataset.idx,false);});
canvas.addEventListener('click',e=>{const g=e.target.closest('[data-idx]'); if(g) showDetail(+g.dataset.idx,true);});
document.getElementById('panelClose').addEventListener('click',closePanel);

// zoom
let scale=1; const svgEl=document.getElementById('tree');
function applyScale(){ svgEl.style.width=(VW*scale)+'px'; svgEl.style.height=(TOTAL_H*scale)+'px'; }
document.getElementById('zin').onclick=()=>{scale=Math.min(2,scale+0.15);applyScale();};
document.getElementById('zout').onclick=()=>{scale=Math.max(0.4,scale-0.15);applyScale();};
document.getElementById('zfit').onclick=()=>{const w=document.getElementById('scroll').clientWidth-40;scale=Math.min(1.4,w/VW);applyScale();};
(function(){const w=document.getElementById('scroll').clientWidth-40;scale=Math.min(1,w/VW);applyScale();})();
</script>
</body>
</html>
DT_HTML_TAIL
}

# ---------- Dispatch ----------

if [ $# -eq 0 ]; then
  _dt_print_usage >&2
  exit 2
fi

case "$1" in
  -h|--help|help)
    _dt_print_usage >&2
    exit 2
    ;;
  render)
    shift
    _dt_cmd_render "$@"
    ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_DT_NAME" "$1" >&2
    _dt_print_usage >&2
    exit 2
    ;;
esac
