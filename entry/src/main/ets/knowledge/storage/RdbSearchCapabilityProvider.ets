import { Context } from '@kit.AbilityKit';
import {
  RdbSearchCapabilities,
  RdbSearchCapabilityProbe,
  safeUnavailableRdbSearchCapabilities
} from './RdbSearchCapabilityProbe';

export class RdbSearchCapabilityProvider {
  private readonly probe: RdbSearchCapabilityProbe;
  private capabilitiesPromise?: Promise<RdbSearchCapabilities>;

  constructor(probe: RdbSearchCapabilityProbe = new RdbSearchCapabilityProbe()) {
    this.probe = probe;
  }

  get(context: Context): Promise<RdbSearchCapabilities> {
    if (this.capabilitiesPromise === undefined) {
      this.capabilitiesPromise = this.load(context);
    }
    return this.capabilitiesPromise;
  }

  private async load(context: Context): Promise<RdbSearchCapabilities> {
    try {
      return await this.probe.probe(context);
    } catch (error) {
      return safeUnavailableRdbSearchCapabilities();
    }
  }
}

export const PROCESS_RDB_SEARCH_CAPABILITY_PROVIDER: RdbSearchCapabilityProvider =
  new RdbSearchCapabilityProvider();
