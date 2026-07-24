import { common, AgentExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SequenceIdGenerator } from '../common/IdGenerator';
import { PROCESS_RUNTIME_BOOTSTRAP } from '../runtime/RuntimeBootstrap';
import { A2ACommandCodec } from './a2a/A2ACommandCodec';
import { A2AResponseFactory } from './a2a/A2AResponseFactory';
import { AgentSessionRegistry } from './a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from './a2a/AgentTaskRegistry';
import { RealSemaLinkAgentExecutor } from './RealSemaLinkAgentExecutor';
import {
  AgentDataSender,
  SemaLinkAgentAbilityOrchestrator
} from './SemaLinkAgentAbilityOrchestrator';
import { KnowledgeAnswerFormatter } from './query/KnowledgeAnswerFormatter';
import { RuntimeAgentKnowledgeQueryPort } from './query/RuntimeAgentKnowledgeQueryPort';
import { UnavailableCrossDeviceKnowledgePort } from './query/UnavailableCrossDeviceKnowledgePort';
import { AgentAuthorizationCoordinator } from './AgentAuthorizationCoordinator';

const DOMAIN: number = 0x0000;
const TAG: string = 'SemaLinkAgent';

class ProxyDataSender implements AgentDataSender {
  private readonly proxy: common.AgentHostProxy;

  constructor(proxy: common.AgentHostProxy) {
    this.proxy = proxy;
  }

  send(data: string): void {
    this.proxy.sendData(data);
  }
}

export default class SemaLinkAgentExtensionAbility extends AgentExtensionAbility {
  private orchestrator?: SemaLinkAgentAbilityOrchestrator;
  private readonly ids: SequenceIdGenerator = new SequenceIdGenerator();
  private readonly connections: Map<common.AgentHostProxy, string> = new Map<common.AgentHostProxy, string>();
  private readonly authorization: AgentAuthorizationCoordinator = new AgentAuthorizationCoordinator();

  onCreate(_want: Want): void {
    const remote: UnavailableCrossDeviceKnowledgePort = new UnavailableCrossDeviceKnowledgePort();
    const queryPort: RuntimeAgentKnowledgeQueryPort =
      new RuntimeAgentKnowledgeQueryPort(this.context, PROCESS_RUNTIME_BOOTSTRAP, remote);
    const executor: RealSemaLinkAgentExecutor =
      new RealSemaLinkAgentExecutor(queryPort, new KnowledgeAnswerFormatter());
    this.orchestrator = new SemaLinkAgentAbilityOrchestrator(
      new A2ACommandCodec(), new A2AResponseFactory(),
      new AgentSessionRegistry(this.ids), new AgentTaskRegistry(), this.ids, executor);
    hilog.info(DOMAIN, TAG, 'lifecycle=onCreate runtime=cold_start_ready');
  }

  onConnect(_want: Want, proxy: common.AgentHostProxy): void {
    this.connectionId(proxy);
    hilog.info(DOMAIN, TAG, 'lifecycle=onConnect');
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    const orchestrator: SemaLinkAgentAbilityOrchestrator | undefined = this.orchestrator;
    if (orchestrator === undefined) {
      hilog.error(DOMAIN, TAG, 'lifecycle=onData error=E_RUNTIME_NOT_READY');
      return;
    }
    orchestrator.handleData(this.connectionId(proxy), new ProxyDataSender(proxy), data)
      .catch((_error: Object): void => {
        hilog.error(DOMAIN, TAG, 'lifecycle=onData error=E_ORCHESTRATION');
      });
  }

  onAuth(proxy: common.AgentHostProxy, handshakeData: string): void {
    if (!this.authorization.authorize(handshakeData, (data: string): void => proxy.authorize(data))) {
      hilog.error(DOMAIN, TAG, 'lifecycle=onAuth error=E_AUTH_RESPONSE');
    }
  }

  onDisconnect(_want: Want, proxy: common.AgentHostProxy): void {
    const connectionId: string | undefined = this.connections.get(proxy);
    if (connectionId !== undefined) {
      this.orchestrator?.disconnect(connectionId);
      this.connections.delete(proxy);
    }
    hilog.info(DOMAIN, TAG, 'lifecycle=onDisconnect');
  }

  onDestroy(): void {
    for (const connectionId of this.connections.values()) {
      this.orchestrator?.disconnect(connectionId);
    }
    this.connections.clear();
    this.orchestrator = undefined;
    hilog.info(DOMAIN, TAG, 'lifecycle=onDestroy');
  }

  private connectionId(proxy: common.AgentHostProxy): string {
    const existing: string | undefined = this.connections.get(proxy);
    if (existing !== undefined) {
      return existing;
    }
    const created: string = this.ids.next('agent-connection');
    this.connections.set(proxy, created);
    return created;
  }
}
