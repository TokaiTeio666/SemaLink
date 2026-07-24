import {
  DeviceProfileAdvertisement,
  DeviceRuntimeSnapshot,
  TaskRequest
} from '../contracts/semantic/SemanticModels';
import { DeviceRoutingCandidate } from './DeviceDirectory';
import { normalizeKnowledgeDomain } from
  '../contracts/semantic/KnowledgeDomainNormalizer';

export type RoutingExclusionReason =
  | 'LOCAL_ONLY_REMOTE'
  | 'PROFILE_EXPIRED'
  | 'NOT_READY'
  | 'LEVELS_NOT_SUPPORTED'
  | 'MODALITIES_NOT_SUPPORTED'
  | 'FILTER_NOT_MATCHED';

export interface RoutingSubscores {
  semanticMatch: number;
  filterMatch: number;
  freshness: number;
  normalizedRtt: number;
  load: number;
  privacyRisk: number;
  total: number;
}

export interface RoutedDevice {
  candidate: DeviceRoutingCandidate;
  scores: RoutingSubscores;
  matchedDomain: string;
  normalizedMatchedDomain: string;
}

export interface ExcludedDevice {
  candidate: DeviceRoutingCandidate;
  reason: RoutingExclusionReason;
}

export interface RoutingResult {
  selected: RoutedDevice | null;
  routed: RoutedDevice[];
  excluded: ExcludedDevice[];
}

interface DomainMatch {
  matchedCount: number;
  matchedDomain: string;
  normalizedMatchedDomain: string;
}

const PROFILE_TTL_MS: number = 5 * 60 * 1000;
const SCORE_EPSILON: number = 1e-9;

function includes<T>(values: T[], value: T): boolean {
  return values.indexOf(value) >= 0;
}

function allIncluded<T>(required: T[], available: T[]): boolean {
  for (const value of required) {
    if (!includes(available, value)) {
      return false;
    }
  }
  return true;
}

export class DeviceSemanticRouter {
  route(task: TaskRequest, candidates: DeviceRoutingCandidate[], nowMs: number): RoutingResult {
    const routed: RoutedDevice[] = [];
    const excluded: ExcludedDevice[] = [];
    for (const candidate of candidates) {
      const reason: RoutingExclusionReason | null = this.exclusionReason(task, candidate, nowMs);
      if (reason !== null) {
        excluded.push({ candidate: candidate, reason: reason });
        continue;
      }
      const match = this.domainMatch(task.requiredConcepts,
        candidate.profile.knowledgeDomains);
      routed.push({
        candidate: candidate,
        scores: this.score(task, candidate, nowMs, match.matchedCount),
        matchedDomain: match.matchedDomain,
        normalizedMatchedDomain: match.normalizedMatchedDomain
      });
    }
    routed.sort((left: RoutedDevice, right: RoutedDevice): number => {
      const difference: number = right.scores.total - left.scores.total;
      if (Math.abs(difference) > SCORE_EPSILON) {
        return difference;
      }
      if (left.candidate.snapshot.isLocal !== right.candidate.snapshot.isLocal) {
        return left.candidate.snapshot.isLocal ? -1 : 1;
      }
      return left.candidate.snapshot.deviceId < right.candidate.snapshot.deviceId ? -1 :
        (left.candidate.snapshot.deviceId > right.candidate.snapshot.deviceId ? 1 : 0);
    });
    return {
      selected: routed.length === 0 ? null : routed[0],
      routed: routed,
      excluded: excluded
    };
  }

  selectParallel(result: RoutingResult, maximumRemoteCount: number = 2): RoutedDevice[] {
    const limit: number = Math.max(0, Math.floor(maximumRemoteCount));
    const selected: RoutedDevice[] = [];
    for (const routed of result.routed) {
      if (routed.candidate.snapshot.isLocal) {
        selected.push(routed);
        break;
      }
    }
    let remotes: number = 0;
    for (const routed of result.routed) {
      if (!routed.candidate.snapshot.isLocal && remotes < limit) {
        selected.push(routed);
        remotes++;
      }
    }
    return selected;
  }

  private exclusionReason(task: TaskRequest, candidate: DeviceRoutingCandidate,
    nowMs: number): RoutingExclusionReason | null {
    const snapshot: DeviceRuntimeSnapshot = candidate.snapshot;
    const profile: DeviceProfileAdvertisement = candidate.profile;
    if (task.privacyLevel === 'LOCAL_ONLY' && !snapshot.isLocal) {
      return 'LOCAL_ONLY_REMOTE';
    }
    const profileTtlMs: number = profile.ttlMs > 0 ? profile.ttlMs : PROFILE_TTL_MS;
    if (!snapshot.isLocal && nowMs - profile.advertisedAtMs > profileTtlMs) {
      return 'PROFILE_EXPIRED';
    }
    if (snapshot.state !== 'READY' || profile.indexState !== 'READY') {
      return 'NOT_READY';
    }
    if (!allIncluded(task.acceptableLevels, profile.supportedLevels)) {
      return 'LEVELS_NOT_SUPPORTED';
    }
    if (task.filters !== undefined && task.filters.modalities !== undefined &&
      !allIncluded(task.filters.modalities, profile.modalities)) {
      return 'MODALITIES_NOT_SUPPORTED';
    }
    return null;
  }

  private score(task: TaskRequest, candidate: DeviceRoutingCandidate,
    nowMs: number, matchedCount: number): RoutingSubscores {
    const snapshot: DeviceRuntimeSnapshot = candidate.snapshot;
    const profile: DeviceProfileAdvertisement = candidate.profile;
    const semanticMatch: number = task.requiredConcepts.length === 0
      ? 0 : matchedCount / task.requiredConcepts.length;
    const filterMatch: number = 1;
    const ageMs: number = Math.max(0, nowMs - profile.advertisedAtMs);
    const profileTtlMs: number = profile.ttlMs > 0 ? profile.ttlMs : PROFILE_TTL_MS;
    const freshness: number = Math.max(0, 1 - ageMs / profileTtlMs);
    const normalizedRtt: number = Math.min(1, Math.max(0, snapshot.averageRttMs / 1000));
    const load: number = Math.min(1, Math.max(0, snapshot.load));
    const privacyRisk: number = snapshot.isLocal ? 0 : 0.2;
    const total: number = 0.45 * semanticMatch + 0.20 * filterMatch + 0.10 * freshness -
      0.10 * normalizedRtt - 0.05 * load - 0.10 * privacyRisk;
    return {
      semanticMatch: semanticMatch,
      filterMatch: filterMatch,
      freshness: freshness,
      normalizedRtt: normalizedRtt,
      load: load,
      privacyRisk: privacyRisk,
      total: total
    };
  }

  private domainMatch(requiredConcepts: string[], domains: string[]): DomainMatch {
    const normalizedDomains: string[] = domains.map(
      (domain: string): string => normalizeKnowledgeDomain(domain)
    );
    let matched: number = 0;
    let matchedDomain: string = '';
    let normalizedMatchedDomain: string = '';
    for (const concept of requiredConcepts) {
      const normalizedConcept: string = normalizeKnowledgeDomain(concept);
      const domainIndex: number = normalizedDomains.indexOf(normalizedConcept);
      if (normalizedConcept.length > 0 && domainIndex >= 0) {
        matched++;
        if (matchedDomain.length === 0) {
          matchedDomain = domains[domainIndex];
          normalizedMatchedDomain = normalizedDomains[domainIndex];
        }
      }
    }
    return {
      matchedCount: matched,
      matchedDomain: matchedDomain,
      normalizedMatchedDomain: normalizedMatchedDomain
    };
  }
}
