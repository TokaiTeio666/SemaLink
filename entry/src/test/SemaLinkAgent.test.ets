import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse
} from '../main/ets/agent/SemaLinkAgentModels';
import {
  MAX_AGENT_QUERY_CHARS,
  SemaLinkAgentRequestValidator
} from '../main/ets/agent/SemaLinkAgentRequestValidator';
import { StubSemaLinkAgentExecutor } from '../main/ets/agent/StubSemaLinkAgentExecutor';

const STUB_RESPONSE_TEXT: string =
  'SemaLink 端侧智能体已连接。跨设备知识检索能力正在准备中。';

function validate(query: Object): SemaLinkAgentRequest {
  return new SemaLinkAgentRequestValidator().validate('context-1', 'task-1', query);
}

function validationError(query: Object): AppError | null {
  try {
    validate(query);
    return null;
  } catch (error) {
    return error as AppError;
  }
}

export default function semaLinkAgentTest(): void {
  describe('SemaLinkAgent', () => {
    it('trims a valid query', 0, () => {
      const request: SemaLinkAgentRequest = validate('  查找本机资料  ');

      expect(request.contextId).assertEqual('context-1');
      expect(request.taskId).assertEqual('task-1');
      expect(request.queryText).assertEqual('查找本机资料');
    });

    it('rejects an empty query', 0, () => {
      const error: AppError | null = validationError('');

      expect(error === null).assertFalse();
      expect((error as AppError).code).assertEqual('E_AGENT_QUERY_INVALID');
    });

    it('rejects a whitespace-only query', 0, () => {
      const error: AppError | null = validationError(' \t\r\n ');

      expect(error === null).assertFalse();
      expect((error as AppError).code).assertEqual('E_AGENT_QUERY_INVALID');
    });

    it('rejects a non-string query', 0, () => {
      const error: AppError | null = validationError(42 as Object);

      expect(error === null).assertFalse();
      expect((error as AppError).code).assertEqual('E_AGENT_QUERY_INVALID');
    });

    it('rejects an overlong query without exposing its text', 0, () => {
      let query: string = '';
      while (query.length <= MAX_AGENT_QUERY_CHARS) {
        query += 'sensitive-query-';
      }
      const error: AppError | null = validationError(query);

      expect(error === null).assertFalse();
      expect((error as AppError).message.indexOf(query) < 0).assertTrue();
    });

    it('returns the fixed stub response', 0, async () => {
      const executor: StubSemaLinkAgentExecutor = new StubSemaLinkAgentExecutor();
      const response: SemaLinkAgentResponse = await executor.execute(validate('hello'));

      expect(response.text).assertEqual(STUB_RESPONSE_TEXT);
    });

    it('does not return success after cancellation', 0, async () => {
      const executor: StubSemaLinkAgentExecutor = new StubSemaLinkAgentExecutor();
      executor.cancel('task-1');
      let errorCode: string = '';

      try {
        await executor.execute(validate('hello'));
      } catch (error) {
        errorCode = (error as AppError).code;
      }

      expect(errorCode).assertEqual('E_AGENT_TASK_CANCELLED');
    });

    it('keeps cancellation isolated by task id', 0, async () => {
      const executor: StubSemaLinkAgentExecutor = new StubSemaLinkAgentExecutor();
      executor.cancel('task-1');
      const request: SemaLinkAgentRequest =
        new SemaLinkAgentRequest('context-1', 'task-2', 'hello');
      const response: SemaLinkAgentResponse = await executor.execute(request);

      expect(response.text).assertEqual(STUB_RESPONSE_TEXT);
    });
  });
}
