import { describe, expect, it } from '@ohos/hypium';
import {
  DisplayKnowledgeItem,
  KnowledgeQueryDisplayState,
  beginQueryState,
  failQueryState,
  succeedQueryState
} from '../main/ets/application/KnowledgeQueryDisplayState';

function resultItem(): DisplayKnowledgeItem {
  return {
    title: '进程与线程', relevance: 0.9, content: '进程和线程的区别',
    kind: '摘要', chunkLabel: ''
  };
}

export default function knowledgeQueryDisplayStateTest() {
  describe('KnowledgeQueryDisplayState', () => {
    it('clears previous results when a query starts and then fails', 0, () => {
      const success: KnowledgeQueryDisplayState = succeedQueryState([resultItem()], 2, false);
      const querying = beginQueryState(success);
      const failed = failQueryState(querying, 'E_TOP_K_INVALID', 'topK must be between 1 and 20');

      expect(querying.items.length).assertEqual(0);
      expect(failed.items.length).assertEqual(0);
      expect(failed.summary).assertEqual('查询失败');
      expect(failed.errorText).assertContain('E_TOP_K_INVALID');
      expect(failed.errorText.includes('2 条')).assertFalse();
    });

    it('represents an empty query as success without an error', 0, () => {
      const state = succeedQueryState([], 1, false);
      expect(state.status).assertEqual('EMPTY');
      expect(state.summary).assertContain('0 条');
      expect(state.errorText).assertEqual('');
    });
  });
}
