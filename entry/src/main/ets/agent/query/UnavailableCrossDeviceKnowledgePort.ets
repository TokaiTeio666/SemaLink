import { TaskRequest } from '../../contracts/semantic/SemanticModels';
import {
  CrossDeviceAvailability,
  CrossDeviceKnowledgePort,
  CrossDeviceQueryResult
} from './CrossDeviceKnowledgePort';

export class UnavailableCrossDeviceKnowledgePort implements CrossDeviceKnowledgePort {
  availability(): CrossDeviceAvailability {
    return new CrossDeviceAvailability(false, 'REMOTE_CHANNEL_UNAVAILABLE');
  }

  search(_request: TaskRequest): Promise<CrossDeviceQueryResult> {
    return Promise.resolve(new CrossDeviceQueryResult(
      false, [], 0, false, false, 'REMOTE_CHANNEL_UNAVAILABLE'));
  }

  cancel(_internalTaskId: string): void {
  }
}
