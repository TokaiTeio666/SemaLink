import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { A2ACancelCommand, A2ACommandKind, A2AConversationCommand } from '../main/ets/agent/a2a/A2AModels';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';

const NEW_MESSAGE: string = '{"jsonrpc":"2.0","id":"req-002","method":"message/stream","params":{"message":{"messageId":"msg-abc-002","role":"ROLE_USER","parts":[{"text":"请介绍一下量子计算的基本原理","mediaType":"text/plain"}]},"metadata":{"traceId":"trace-001","agentId":"semalink_knowledge_agent","appVersion":"12.0.1"}}}';
const FOLLOW_UP: string = '{"jsonrpc":"2.0","id":"req-003","method":"message/stream","params":{"message":{"messageId":"msg-003","taskId":"task-001","contextId":"ctx-001","role":"ROLE_USER","parts":[{"text":"北京","mediaType":"text/plain"}]},"metadata":{"traceId":"trace-002","agentId":"semalink_knowledge_agent"}}}';
const CANCEL: string = '{"jsonrpc":"2.0","id":"req-004","method":"tasks/cancel","params":{"id":"task-001","metadata":{"traceId":"trace-003","agentId":"semalink_knowledge_agent"}}}';

function decodeErrorCode(value: string): string {
  try {
    new A2ACommandCodec().decode(value);
    return '';
  } catch (error) {
    return (error as AppError).code;
  }
}

export default function a2aCommandCodecTest(): void {
  describe('A2ACommandCodec', () => {
    it('decodes official new conversation fixture', 0, () => {
      const command: A2AConversationCommand =
        new A2ACommandCodec().decode(NEW_MESSAGE) as A2AConversationCommand;
      expect(command.kind).assertEqual(A2ACommandKind.MESSAGE_STREAM);
      expect(command.requestId).assertEqual('req-002');
      expect(command.queryText).assertEqual('请介绍一下量子计算的基本原理');
      expect(command.contextId === undefined).assertTrue();
      expect(command.taskId === undefined).assertTrue();
      expect(command.metadata.traceId).assertEqual('trace-001');
    });

    it('decodes follow-up input for existing task', 0, () => {
      const command: A2AConversationCommand =
        new A2ACommandCodec().decode(FOLLOW_UP) as A2AConversationCommand;
      expect(command.contextId).assertEqual('ctx-001');
      expect(command.taskId).assertEqual('task-001');
      expect(command.queryText).assertEqual('北京');
    });

    it('decodes official task cancellation fixture', 0, () => {
      const command: A2ACancelCommand = new A2ACommandCodec().decode(CANCEL) as A2ACancelCommand;
      expect(command.kind).assertEqual(A2ACommandKind.TASK_CANCEL);
      expect(command.taskId).assertEqual('task-001');
    });

    it('rejects malformed json with official parse error', 0, () => {
      expect(decodeErrorCode('{bad')).assertEqual('E_A2A_PARSE');
    });

    it('rejects unknown methods without guessing from text', 0, () => {
      const value: string = NEW_MESSAGE.replace('message/stream', 'message/unknown');
      expect(decodeErrorCode(value)).assertEqual('E_A2A_UNSUPPORTED');
    });

    it('rejects empty and overlong questions', 0, () => {
      expect(decodeErrorCode(NEW_MESSAGE.replace('请介绍一下量子计算的基本原理', '   ')))
        .assertEqual('E_A2A_PARAMS');
      const longText: string = 'x'.repeat(1001);
      expect(decodeErrorCode(NEW_MESSAGE.replace('请介绍一下量子计算的基本原理', longText)))
        .assertEqual('E_A2A_PARAMS');
    });
  });
}
