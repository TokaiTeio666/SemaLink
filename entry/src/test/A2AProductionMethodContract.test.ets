import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2ACommandKind } from '../main/ets/agent/a2a/A2AModels';

const METADATA: string =
  '"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent"}';

function message(method: string): string {
  return '{"jsonrpc":"2.0","id":"req-1","method":"' + method + '","params":{"message":{' +
    '"messageId":"message-1","role":"ROLE_USER","parts":[{"text":"查询本机知识"}]},' + METADATA + '}}';
}

export default function a2aProductionMethodContractTest(): void {
  describe('A2AProductionMethodContract', () => {
    it('wires only Huawei documented message/stream and tasks/cancel methods', 0, () => {
      const codec: A2ACommandCodec = new A2ACommandCodec();
      expect(codec.decode(message('message/stream')).kind).assertEqual(A2ACommandKind.MESSAGE_STREAM);
      let errorCode: string = '';
      try {
        codec.decode(message('message/send'));
      } catch (error) {
        errorCode = (error as AppError).code;
      }
      expect(errorCode).assertEqual('E_A2A_UNSUPPORTED');
      const cancel: string =
        '{"jsonrpc":"2.0","id":"cancel-1","method":"tasks/cancel","params":{"id":"task-1",' +
        METADATA + '}}';
      expect(codec.decode(cancel).kind).assertEqual(A2ACommandKind.TASK_CANCEL);
    });
  });
}
