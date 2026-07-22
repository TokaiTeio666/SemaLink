import { AppSnapshot, INITIAL_SNAPSHOT } from '../model/AppModels';

export type StateListener = (snapshot: AppSnapshot) => void;
export interface StateUpdate extends Partial<AppSnapshot> {
  clearError?: boolean;
}

export class AppStateStore {
  private listeners: Array<StateListener> = [];
  private current: AppSnapshot = INITIAL_SNAPSHOT;

  snapshot(): AppSnapshot {
    return this.current;
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.push(listener);
    listener(this.current);
    return () => {
      this.listeners = this.listeners.filter((item: StateListener) => item !== listener);
    };
  }

  update(next: StateUpdate): void {
    const updated: AppSnapshot = {
      peerStatuses: next.peerStatuses ?? this.current.peerStatuses,
      activePeerCount: next.activePeerCount ?? this.current.activePeerCount,
      evidenceSourceDeviceIds: next.evidenceSourceDeviceIds ?? this.current.evidenceSourceDeviceIds,
      evidenceConflictCount: next.evidenceConflictCount ?? this.current.evidenceConflictCount,
      finalSufficiency: next.finalSufficiency ?? this.current.finalSufficiency,
      totalTaskMs: next.totalTaskMs ?? this.current.totalTaskMs,
      enteredL2: next.enteredL2 ?? this.current.enteredL2,
      role: next.role ?? this.current.role,
      connectionState: next.connectionState ?? this.current.connectionState,
      question: next.question ?? this.current.question,
      summary: next.summary ?? this.current.summary,
      requestId: next.requestId ?? this.current.requestId,
      roundTripMs: next.roundTripMs ?? this.current.roundTripMs,
      bytesSent: next.bytesSent ?? this.current.bytesSent,
      bytesReceived: next.bytesReceived ?? this.current.bytesReceived,
      peerDeviceName: next.peerDeviceName ?? this.current.peerDeviceName,
      peerDeviceIdMasked: next.peerDeviceIdMasked ?? this.current.peerDeviceIdMasked,
      error: this.current.error
    };
    if (next.clearError === true) {
      updated.error = undefined;
    } else if (next.error !== undefined) {
      updated.error = next.error;
    }
    this.current = updated;
    this.listeners.forEach((listener: StateListener) => listener(this.current));
  }
}
