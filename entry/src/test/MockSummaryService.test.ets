import { describe, expect, it } from '@ohos/hypium';
import { MockSummaryService } from '../main/ets/task/MockSummaryService';

export default function mockSummaryServiceTest(): void {
  describe('MockSummaryService', () => {
    const service: MockSummaryService = new MockSummaryService();
    it('returnsDeterministicSummary', 0, () => {
      expect(service.generate('  鸿蒙通信如何工作？  ')).assertEqual(
        service.generate('鸿蒙通信如何工作？'));
    });
    it('includesQuestionAndDisclosure', 0, () => {
      const result: string = service.generate('项目状态');
      expect(result).assertContain('项目状态');
      expect(result).assertContain('未执行真实文档检索');
      expect(result).assertContain('未传输完整文件');
    });
  });
}
