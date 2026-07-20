import { AppError, ErrorStage } from '../common/AppError';
import { SemaLinkAgentExecutor } from './SemaLinkAgentExecutor';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse
} from './SemaLinkAgentModels';

const STUB_RESPONSE_TEXT: string =
  'SemaLink 端侧智能体已连接。跨设备知识检索能力正在准备中。';

export class StubSemaLinkAgentExecutor implements SemaLinkAgentExecutor {
  private cancelledTaskIds: Array<string> = [];

  execute(request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    if (this.isCancelled(request.taskId)) {
      return Promise.reject(new AppError(
        'E_AGENT_TASK_CANCELLED',
        'Agent task was cancelled',
        ErrorStage.LIFECYCLE,
        true
      ));
    }
    return Promise.resolve(new SemaLinkAgentResponse(STUB_RESPONSE_TEXT));
  }

  cancel(taskId: string): void {
    if (!this.isCancelled(taskId)) {
      this.cancelledTaskIds.push(taskId);
    }
  }

  private isCancelled(taskId: string): boolean {
    for (const cancelledTaskId of this.cancelledTaskIds) {
      if (cancelledTaskId === taskId) {
        return true;
      }
    }
    return false;
  }
}
