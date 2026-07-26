/**
 * Barrel de mappers — ponto de importacao unico.
 * Task 3.4.5
 */
export { mapExecution, mapExecutions } from './execution.js';
export { normalizeStatus, type ExecutionStatus } from './status.js';
export { mapWave, mapWaves } from './wave.js';
export { mapDecision, mapDecisions } from './decision.js';
export { mapTask, mapTasks } from './task.js';
export { mapEvent, mapEvents } from './event.js';
export { mapAlert, mapAlerts } from './alert.js';
export { mapBlock, mapBlocks } from './block.js';
export { mapSkill, mapSkills } from './skill.js';
export { mapSuggestion, mapSuggestions } from './suggestion.js';
export { mapAgentUsageRollup, mapAgentUsageResult } from './agent-usage.js';
