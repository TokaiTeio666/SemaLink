import {
  common,
  AgentExtensionAbility,
  Want
} from '@kit.AbilityKit';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SequenceIdGenerator } from '../common/IdGenerator';
import { SemaLinkAgentExecutor } from './SemaLinkAgentExecutor';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse
} from './SemaLinkAgentModels';
import { SemaLinkAgentRequestValidator } from './SemaLinkAgentRequestValidator';
import { StubSemaLinkAgentExecutor } from './StubSemaLinkAgentExecutor';

const DOMAIN: number = 0x0000;
const TAG: string = 'SemaLinkAgent';
const AUTHORIZATION_RESPONSE_TEXT: string = 'SemaLink agent authentication accepted';
const SAFE_FAILURE_RESPONSE_TEXT: string = 'SemaLink 暂时无法处理此请求，请稍后重试。';

export default class SemaLinkAgentExtensionAbility extends AgentExtensionAbility {
  private executor: SemaLinkAgentExecutor = new StubSemaLinkAgentExecutor();
  private readonly validator: SemaLinkAgentRequestValidator =
    new SemaLinkAgentRequestValidator();
  private readonly idGenerator: SequenceIdGenerator = new SequenceIdGenerator();

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'AgentExtensionAbility onCreate');
  }

  onConnect(want: Want, proxy: common.AgentHostProxy): void {
    hilog.info(DOMAIN, TAG, 'AgentExtensionAbility onConnect');
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    const contextId: string = this.idGenerator.next('agent-context');
    const taskId: string = this.idGenerator.next('agent-task');

    try {
      const request: SemaLinkAgentRequest =
        this.validator.validate(contextId, taskId, data);
      this.executor.execute(request)
        .then((response: SemaLinkAgentResponse): void => {
          this.sendData(proxy, response.text);
        })
        .catch((_error: Object): void => {
          this.sendData(proxy, SAFE_FAILURE_RESPONSE_TEXT);
        });
    } catch (_error) {
      this.sendData(proxy, SAFE_FAILURE_RESPONSE_TEXT);
    }
  }

  onAuth(proxy: common.AgentHostProxy, handshakeData: string): void {
    try {
      proxy.authorize(AUTHORIZATION_RESPONSE_TEXT);
    } catch (_error) {
      hilog.error(DOMAIN, TAG, 'Agent authorization response failed');
    }
  }

  onDisconnect(want: Want, proxy: common.AgentHostProxy): void {
    hilog.info(DOMAIN, TAG, 'AgentExtensionAbility onDisconnect');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'AgentExtensionAbility onDestroy');
  }

  private sendData(proxy: common.AgentHostProxy, text: string): void {
    try {
      proxy.sendData(text);
    } catch (_error) {
      hilog.error(DOMAIN, TAG, 'Agent response send failed');
    }
  }
}
