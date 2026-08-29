/**
 * Mapper: SkillRow → SkillDTO.
 * Task 3.4.5
 */
import type { SkillDTO } from '@cstk-panel/shared-types';
import type { SkillRow } from '../db/queries/skills.js';

export function mapSkill(row: SkillRow): SkillDTO {
  return {
    executionId: row.execution_id,
    skillName: row.skill_name,
    decisionId: row.decision_id,
    wave: row.wave,
  };
}

export function mapSkills(rows: SkillRow[]): SkillDTO[] {
  return rows.map(mapSkill);
}
