import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
export interface SessionEventInfo { sessionId: number; reason?: number; msg?: string; }
export interface SessionConnectResult { isConnected: boolean; errorCode?: number; reason?: string; }
export interface CollaborationApi {
  create(serviceName: string, context: common.UIAbilityContext, peerInfo: abilityConnectionManager.PeerInfo, connectOptions: abilityConnectionManager.ConnectOptions): number;
  onConnect(sessionId: number, callback: (info: SessionEventInfo) => void): void; onDisconnect(sessionId: number, callback: (info: SessionEventInfo) => void): void; onMessage(sessionId: number, callback: (info: SessionEventInfo) => void): void; offAll(sessionId: number): void;
  connect(sessionId: number): Promise<SessionConnectResult>; accept(sessionId: number, token: string): Promise<void>; send(sessionId: number, text: string): Promise<void>; disconnect(sessionId: number): void; destroy(sessionId: number): void;
}
export class ProductionCollaborationApi implements CollaborationApi {
  create(s: string, c: common.UIAbilityContext, p: abilityConnectionManager.PeerInfo, o: abilityConnectionManager.ConnectOptions): number { return abilityConnectionManager.createAbilityConnectionSession(s, c, p, o); }
  onConnect(id: number, cb: (i: SessionEventInfo) => void): void { abilityConnectionManager.on('connect', id, cb); } onDisconnect(id: number, cb: (i: SessionEventInfo) => void): void { abilityConnectionManager.on('disconnect', id, cb); } onMessage(id: number, cb: (i: SessionEventInfo) => void): void { abilityConnectionManager.on('receiveMessage', id, cb); }
  offAll(id: number): void { abilityConnectionManager.off('connect', id); abilityConnectionManager.off('disconnect', id); abilityConnectionManager.off('receiveMessage', id); }
  connect(id: number): Promise<SessionConnectResult> { return abilityConnectionManager.connect(id); } accept(id: number, t: string): Promise<void> { return abilityConnectionManager.acceptConnect(id, t); } send(id: number, t: string): Promise<void> { return abilityConnectionManager.sendMessage(id, t); } disconnect(id: number): void { abilityConnectionManager.disconnect(id); } destroy(id: number): void { abilityConnectionManager.destroyAbilityConnectionSession(id); }
}
