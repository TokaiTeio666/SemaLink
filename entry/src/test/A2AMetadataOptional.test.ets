import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { FIRST_CONVERSATION } from './fixtures/a2a/HuaweiA2AV06Fixtures';

function code(json: string): string {
  try {
    new A2ACommandCodec().decode(json);
    return '';
  } catch (error) {
    return (error as AppError).code;
  }
}

export default function a2aMetadataOptionalTest(): void {
  describe('A2AMetadataContract', () => {
    it('requires official traceId and agentId while ignoring extensions', 0, () => {
      const completeWithExtension: string = FIRST_CONVERSATION.json.replace(
        '"agentId":"semalink_knowledge_agent"',
        '"agentId":"semalink_knowledge_agent","futureField":"ignored"');
      expect(code(completeWithExtension)).assertEqual('');
      expect(code(FIRST_CONVERSATION.json.replace(',"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent"}', '')))
        .assertEqual('E_A2A_PARAMS');
      expect(code(FIRST_CONVERSATION.json.replace(',"agentId":"semalink_knowledge_agent"', '')))
        .assertEqual('E_A2A_PARAMS');
      expect(code(FIRST_CONVERSATION.json.replace('"traceId":"trace-1",', '')))
        .assertEqual('E_A2A_PARAMS');
    });
  });
}
