import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AConversationCommand } from '../main/ets/agent/a2a/A2AModels';
import { FIRST_CONVERSATION, FOLLOW_UP } from './fixtures/a2a/HuaweiA2AV06Fixtures';

function errorCode(json: string): string {
  try {
    new A2ACommandCodec().decode(json);
    return '';
  } catch (error) {
    return (error as AppError).code;
  }
}

export default function a2aRequestIdCompatibilityTest(): void {
  describe('A2ARequestIdCompatibility', () => {
    it('preserves string and numeric request ids', 0, () => {
      const stringCommand: A2AConversationCommand =
        new A2ACommandCodec().decode(FIRST_CONVERSATION.json) as A2AConversationCommand;
      const numberCommand: A2AConversationCommand =
        new A2ACommandCodec().decode(FOLLOW_UP.json) as A2AConversationCommand;
      expect(stringCommand.requestId as string).assertEqual('req-1');
      expect(numberCommand.requestId as number).assertEqual(2);
    });

    it('rejects absent null boolean and structured ids', 0, () => {
      expect(errorCode(FIRST_CONVERSATION.json.replace('"id":"req-1",', ''))).assertEqual('E_A2A_REQUEST');
      expect(errorCode(FIRST_CONVERSATION.json.replace('"req-1"', 'null'))).assertEqual('E_A2A_REQUEST');
      expect(errorCode(FIRST_CONVERSATION.json.replace('"req-1"', 'true'))).assertEqual('E_A2A_REQUEST');
      expect(errorCode(FIRST_CONVERSATION.json.replace('"req-1"', '{}'))).assertEqual('E_A2A_REQUEST');
    });
  });
}
