import { common } from '@kit.AbilityKit';
import { AppStateStore } from '../state/AppStateStore';
import { QueryCoordinator, ResolverFactory } from '../application/QueryCoordinator';
import { CollaborationTransport } from '../communication/CollaborationTransport';
import { SessionManager } from '../communication/SessionManager';
import { Transport } from '../communication/Transport';
import { DistributedDeviceProvider, TrustedDeviceResolver } from '../communication/TrustedDeviceResolver';
import { Logger } from '../common/Logger';
import { SequenceIdGenerator } from '../common/IdGenerator';
import { ProtocolCodec } from '../protocol/ProtocolCodec';
import { MockSummaryService } from '../task/MockSummaryService';
import { SystemScheduler } from '../common/Scheduler';

export interface RuntimeDependencies {
  transport?: Transport;
  resolverFactory?: ResolverFactory;
}

export class AppRuntime {
  private static active: AppRuntime | null = null;
  private destroyed: boolean = false;

  readonly store: AppStateStore;
  readonly coordinator: QueryCoordinator;

  constructor(context: common.UIAbilityContext, dependencies: RuntimeDependencies = {}) {
    const bundleName: string = context.applicationInfo.name;
    const transport: Transport = dependencies.transport ??
      new CollaborationTransport(context, bundleName, new Logger());
    const codec: ProtocolCodec = new ProtocolCodec();
    const session: SessionManager = new SessionManager(
      transport, codec, new SequenceIdGenerator(), new SystemScheduler(), 3000, 10000
    );
    this.store = new AppStateStore();
    const resolverFactory: ResolverFactory = dependencies.resolverFactory ??
      (() => new TrustedDeviceResolver(new DistributedDeviceProvider(bundleName)));
    this.coordinator = new QueryCoordinator(
      session, this.store, new MockSummaryService(), resolverFactory
    );
  }

  static initialize(context: common.UIAbilityContext): AppRuntime {
    if (AppRuntime.active === null) {
      AppRuntime.active = new AppRuntime(context);
    }
    return AppRuntime.active;
  }

  static current(): AppRuntime {
    if (AppRuntime.active === null) {
      throw new Error('AppRuntime has not been initialized');
    }
    return AppRuntime.active;
  }

  static reset(): void {
    if (AppRuntime.active === null) {
      return;
    }
    AppRuntime.active.destroy();
    AppRuntime.active = null;
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.coordinator.destroy();
  }
}
