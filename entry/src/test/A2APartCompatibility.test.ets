import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AConversationCommand } from '../main/ets/agent/a2a/A2AModels';
import { FIRST_CONVERSATION } from './fixtures/a2a/HuaweiA2AV06Fixtures';

function decodeError(json: string): string {
  try {
    new A2ACommandCodec().decode(json);
    return '';
  } catch (error) {
    return (error as AppError).code;
  }
}

export default function a2aPartCompatibilityTest(): void {
  describe('A2APartCompatibility', () => {
    it('accepts text with optional mediaType', 0, () => {
      const withoutMediaType: string = FIRST_CONVERSATION.json.replace(',"mediaType":"text/plain"', '');
      const command: A2AConversationCommand =
        new A2ACommandCodec().decode(withoutMediaType) as A2AConversationCommand;
      expect(command.queryText).assertEqual('查询本机知识');
    });

    it('rejects empty binary unknown and contradictory parts', 0, () => {
      const base: string = FIRST_CONVERSATION.json;
      expect(decodeError(base.replace('"查询本机知识"', '"   "'))).assertEqual('E_A2A_PARAMS');
      expect(decodeError(base.replace('{"text":"查询本机知识","mediaType":"text/plain"}',
        '{"data":"AA==","mediaType":"application/octet-stream"}'))).assertEqual('E_A2A_PARAMS');
      expect(decodeError(base.replace('{"text":"查询本机知识","mediaType":"text/plain"}',
        '{"unknown":"value"}'))).assertEqual('E_A2A_PARAMS');
      expect(decodeError(base.replace('"text/plain"', '"application/octet-stream"'))).assertEqual('E_A2A_PARAMS');
      expect(decodeError(base.replace('{"text":"查询本机知识","mediaType":"text/plain"}',
        '{"text":"查询本机知识","data":"AA==","mediaType":"text/plain"}'))).assertEqual('E_A2A_PARAMS');
      expect(decodeError(base.replace('{"text":"查询本机知识","mediaType":"text/plain"}',
        '{"text":"查询本机知识","url":"https://invalid.example","mediaType":"text/plain"}')))
        .assertEqual('E_A2A_PARAMS');
    });
  });
}
