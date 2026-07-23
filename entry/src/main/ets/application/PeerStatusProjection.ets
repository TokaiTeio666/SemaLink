import {
  ControlChannelState,
  DataChannelState,
  maskDeviceId,
  PeerDevice,
  PeerStatusSnapshot
} from '../model/AppModels';

export interface PeerChannelStateSource {
  controlStateOf(deviceId: string): ControlChannelState;
  dataStateOf(deviceId: string): DataChannelState;
}

export function isPeerAvailable(status: PeerStatusSnapshot): boolean {
  return status.controlState === 'READY' && status.dataState === 'READY';
}

export function activePeerCount(statuses: PeerStatusSnapshot[]): number {
  let count: number = 0;
  for (const status of statuses) {
    if (isPeerAvailable(status)) count += 1;
  }
  return count;
}

export function projectPeerStatuses(
  peers: PeerDevice[],
  states: PeerChannelStateSource,
  failures: Map<string, string>
): PeerStatusSnapshot[] {
  return peers.map((peer: PeerDevice): PeerStatusSnapshot => ({
    deviceIdMasked: maskDeviceId(peer.deviceId),
    deviceName: peer.deviceName,
    controlState: states.controlStateOf(peer.deviceId),
    dataState: states.dataStateOf(peer.deviceId),
    taskState: '',
    allocatedBytes: 0,
    evidenceCount: 0,
    failureCode: failures.get(peer.deviceId) ?? ''
  }));
}
