import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x534C;
const TAG: string = 'SemaLinkAgent';
const LOG_SALT: string = Date.now().toString(36) + '-' + Math.random().toString(36);

export function maskAgentId(value: string): string {
  let hash: number = 2166136261;
  const salted: string = LOG_SALT + ':' + value;
  for (let index = 0; index < salted.length; index += 1) {
    hash ^= salted.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return 'id-' + (hash >>> 0).toString(16).padStart(8, '0');
}

export class AgentSafeLog {
  static command(kind: string): void {
    hilog.info(DOMAIN, TAG, 'event=command kind=%{public}s', kind);
  }

  static transition(contextId: string, taskId: string, state: string): void {
    hilog.info(DOMAIN, TAG, 'event=transition context=%{public}s task=%{public}s state=%{public}s',
      maskAgentId(contextId), maskAgentId(taskId), state);
  }

  static runtime(outcome: string): void {
    hilog.info(DOMAIN, TAG, 'event=runtime outcome=%{public}s', outcome);
  }

  static error(code: string): void {
    hilog.error(DOMAIN, TAG, 'event=error code=%{public}s', code);
  }
}
