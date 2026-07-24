import { EvidenceUnit } from '../../contracts/semantic/SemanticModels';
import { AgentQueryResult, AgentQueryScope } from './AgentQueryModels';

const MAX_EVIDENCE: number = 5;
const MAX_SUMMARY_CHARS: number = 400;
const MAX_OUTPUT_CHARS: number = 2000;

function safeSummary(unit: EvidenceUnit): string {
  const value: string = (unit.summary ?? unit.snippet ?? unit.title).replace(/\s+/g, ' ').trim();
  if (value.length <= MAX_SUMMARY_CHARS) {
    return value;
  }
  return value.substring(0, MAX_SUMMARY_CHARS - 1) + '…';
}

function contains(values: string[], value: string): boolean {
  return values.indexOf(value) >= 0;
}

export class KnowledgeAnswerFormatter {
  format(result: AgentQueryResult): string {
    const lines: string[] = [];
    if (result.evidence.length === 0) {
      lines.push('未找到相关资料。');
    } else {
      lines.push('根据可用资料，找到以下相关内容：');
      const count: number = Math.min(MAX_EVIDENCE, result.evidence.length);
      for (let index = 0; index < count; index += 1) {
        lines.push((index + 1).toString() + '. ' + safeSummary(result.evidence[index]));
      }
      lines.push('');
      lines.push('来源：');
      const sources: string[] = [];
      for (let index = 0; index < count; index += 1) {
        const unit: EvidenceUnit = result.evidence[index];
        const remote: boolean = contains(result.remoteEvidenceIds, unit.evidenceId);
        const source: string = remote ? '另一台可信设备中的' + unit.title : '本机' + unit.title;
        if (!contains(sources, source)) {
          sources.push(source);
          lines.push('- ' + source);
        }
      }
    }
    if (result.sufficiency.feedback !== 'ENOUGH') {
      lines.push('资料可能不完整。');
    }
    if (!result.remoteAvailable && result.scope !== AgentQueryScope.LOCAL_ONLY) {
      lines.push('跨设备通道当前不可用，未查询远端设备。');
    } else if (result.queriedRemote && result.failedSources.length > 0) {
      lines.push('部分远端来源查询失败。');
    }
    const answer: string = lines.join('\n');
    return answer.length <= MAX_OUTPUT_CHARS ? answer : answer.substring(0, MAX_OUTPUT_CHARS - 1) + '…';
  }
}
