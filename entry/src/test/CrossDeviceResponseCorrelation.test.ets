import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceEnvelope } from
  '../main/ets/crossdevice/protocol/CrossDeviceProtocolModels';
import { matchesPendingResponse } from
  '../main/ets/crossdevice/transport/HarmonyCrossDeviceSession';

class ResponsePayload {
  status: string = 'OK';
  evidence: Object[] = [];
  truncated: boolean = false;
}

function response(peerKey: string, requestId: string,
  taskId: string): CrossDeviceEnvelope {
  return new CrossDeviceEnvelope(
    'QUERY_RESPONSE', 'message', requestId, taskId, peerKey,
    100, 200, 0, new ResponsePayload()
  );
}

export default function crossDeviceResponseCorrelationTest(): void {
  describe('CrossDeviceResponseCorrelation', () => {
    it('requires peer request and task to match before completing pending work', 0, () => {
      expect(matchesPendingResponse(
        'peer-b', 'request-1', 'task-1',
        response('peer-b', 'request-1', 'task-2')
      )).assertFalse();
      expect(matchesPendingResponse(
        'peer-b', 'request-1', 'task-1',
        response('peer-b', 'request-2', 'task-1')
      )).assertFalse();
      expect(matchesPendingResponse(
        'peer-b', 'request-1', 'task-1',
        response('peer-c', 'request-1', 'task-1')
      )).assertFalse();
      expect(matchesPendingResponse(
        'peer-b', 'request-1', 'task-1',
        response('peer-b', 'request-1', 'task-1')
      )).assertTrue();
    });
  });
}
