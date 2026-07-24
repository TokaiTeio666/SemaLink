import { describe, expect, it } from '@ohos/hypium';
import {
  AgentContinuationDecision,
  AgentContinuationDecisionParser
} from '../main/ets/agent/a2a/AgentContinuationDecision';

export default function a2aInputRequiredDecisionTest(): void {
  describe('A2AInputRequiredDecision', () => {
    it('classifies every supported local fallback acceptance deterministically', 0, () => {
      const parser: AgentContinuationDecisionParser = new AgentContinuationDecisionParser();
      const values: string[] = ['改为本机查询', '查询本机', '可以', '好', '是', '同意'];
      for (const value of values) {
        expect(parser.parse(value)).assertEqual(AgentContinuationDecision.ACCEPT_LOCAL_FALLBACK);
      }
    });

    it('classifies rejection and cancellation as terminal decisions', 0, () => {
      const parser: AgentContinuationDecisionParser = new AgentContinuationDecisionParser();
      const rejected: string[] = ['不需要', '不用了', '否', '不同意'];
      const cancelled: string[] = ['取消', '停止', '算了'];
      for (const value of rejected) {
        expect(parser.parse(value)).assertEqual(AgentContinuationDecision.REJECT);
      }
      for (const value of cancelled) {
        expect(parser.parse(value)).assertEqual(AgentContinuationDecision.CANCEL);
      }
    });

    it('keeps unrelated text in INPUT_REQUIRED instead of treating it as a query', 0, () => {
      const parser: AgentContinuationDecisionParser = new AgentContinuationDecisionParser();
      expect(parser.parse('顺便解释一下 MVCC')).assertEqual(AgentContinuationDecision.UNRELATED);
      expect(parser.parse('  可以。 ')).assertEqual(AgentContinuationDecision.ACCEPT_LOCAL_FALLBACK);
    });
  });
}
