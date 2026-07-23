export enum MeshDialRole {
  PRIMARY_DIALER = 'PRIMARY_DIALER',
  INBOUND_WAITER = 'INBOUND_WAITER',
  INVALID_SELF = 'INVALID_SELF'
}

export type MeshSessionDirection = 'INBOUND' | 'OUTBOUND';

export function planPeerRole(localDeviceId: string, remoteDeviceId: string): MeshDialRole {
  if (localDeviceId === remoteDeviceId) return MeshDialRole.INVALID_SELF;
  return localDeviceId < remoteDeviceId ? MeshDialRole.PRIMARY_DIALER : MeshDialRole.INBOUND_WAITER;
}

export function preferredSessionDirection(localDeviceId: string, remoteDeviceId: string): MeshSessionDirection {
  return planPeerRole(localDeviceId, remoteDeviceId) === MeshDialRole.PRIMARY_DIALER ? 'OUTBOUND' : 'INBOUND';
}

export function planFullMeshEdges(deviceIds: string[]): string[] {
  const ids: string[] = Array.from(new Set<string>(deviceIds.filter((id: string): boolean => id.length > 0))).sort();
  const edges: string[] = [];
  for (let left = 0; left < ids.length; left += 1) {
    for (let right = left + 1; right < ids.length; right += 1) {
      edges.push(ids[left] + '->' + ids[right]);
    }
  }
  return edges;
}
