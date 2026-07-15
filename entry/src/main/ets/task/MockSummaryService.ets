import { AppError, ErrorStage } from '../common/AppError';
import { MAX_QUESTION_CHARS, MAX_SUMMARY_CHARS } from '../protocol/ProtocolModels';

export class MockSummaryService {
  generate(question: string): string {
    const normalized: string = question.trim();
    if (normalized.length === 0 || normalized.length > MAX_QUESTION_CHARS) {
      throw new AppError('E_QUERY_INVALID', '问题长度无效', ErrorStage.QUERY, true);
    }
    const excerpt: string = normalized.substring(0, 120);
    const summary: string = `响应端设备已收到关于"${excerpt}"的查询。\n` +
      '这是由远端设备生成的模拟摘要，未执行真实文档检索，也未传输完整文件。';
    return summary.substring(0, MAX_SUMMARY_CHARS);
  }
}
