export enum AgentContinuationDecision {
  ACCEPT_LOCAL_FALLBACK = 'ACCEPT_LOCAL_FALLBACK',
  REJECT = 'REJECT',
  CANCEL = 'CANCEL',
  UNRELATED = 'UNRELATED'
}

const ACCEPT_LOCAL: string[] = ['改为本机查询', '查询本机', '可以', '好', '是', '同意'];
const REJECT: string[] = ['不需要', '不用了', '否', '不同意'];
const CANCEL: string[] = ['取消', '停止', '算了'];

function normalize(value: string): string {
  return value.trim().replace(/[。！!？?，,；;]+$/g, '').trim();
}

export class AgentContinuationDecisionParser {
  parse(value: string): AgentContinuationDecision {
    const normalized: string = normalize(value);
    if (ACCEPT_LOCAL.indexOf(normalized) >= 0) {
      return AgentContinuationDecision.ACCEPT_LOCAL_FALLBACK;
    }
    if (REJECT.indexOf(normalized) >= 0) {
      return AgentContinuationDecision.REJECT;
    }
    if (CANCEL.indexOf(normalized) >= 0) {
      return AgentContinuationDecision.CANCEL;
    }
    return AgentContinuationDecision.UNRELATED;
  }
}
