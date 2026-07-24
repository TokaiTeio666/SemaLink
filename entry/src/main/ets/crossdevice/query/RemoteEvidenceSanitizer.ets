import {
  EvidenceLevel,
  EvidenceUnit
} from '../../contracts/semantic/SemanticModels';
import { normalizeKnowledgeDomain } from
  '../../contracts/semantic/KnowledgeDomainNormalizer';
import { SharingPolicy } from '../model/SharingPolicy';

export class RemoteEvidence {
  readonly title: string;
  readonly summary: string;
  readonly snippet: string;
  readonly relevance: number;
  readonly knowledgeDomain: string;
  readonly updatedAtMs: number;
  readonly level: EvidenceLevel;
  readonly sourceDeviceAlias: string;
  readonly truncated: boolean;

  constructor(title: string, summary: string, snippet: string, relevance: number,
    knowledgeDomain: string, updatedAtMs: number, level: EvidenceLevel,
    sourceDeviceAlias: string, truncated: boolean) {
    this.title = title;
    this.summary = summary;
    this.snippet = snippet;
    this.relevance = relevance;
    this.knowledgeDomain = knowledgeDomain;
    this.updatedAtMs = updatedAtMs;
    this.level = level;
    this.sourceDeviceAlias = sourceDeviceAlias;
    this.truncated = truncated;
  }
}

export class RemoteEvidenceResponse {
  readonly evidence: RemoteEvidence[];
  readonly truncated: boolean;

  constructor(evidence: RemoteEvidence[], truncated: boolean) {
    this.evidence = evidence;
    this.truncated = truncated;
  }
}

function bounded(text: string | undefined, limit: number): string {
  if (text === undefined) {
    return '';
  }
  return text.length <= limit ? text : text.slice(0, limit);
}

function safeTitle(title: string): string {
  if (title.includes(':\\') || title.startsWith('/') || title.startsWith('\\\\')) {
    return 'Shared evidence';
  }
  return safeContent(title, 256);
}

function safeContent(text: string | undefined, limit: number): string {
  if (text === undefined) {
    return '';
  }
  const normalizedSql: string = text
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/--[^\r\n]*/g, '')
    .toLowerCase();
  if (/\b(select|insert|update|delete|drop|alter|pragma|attach|create\s*table)\b/
    .test(normalizedSql)) {
    return '[redacted unsafe content]';
  }
  const redacted: string = text
    .replace(/file:\/\/[^\s]+/gi, '[redacted path]')
    .replace(/\/[a-zA-Z0-9._-]+(?:\/[^\s,;)\]}]+)+/g, '[redacted path]')
    .replace(/(?:^|\s)(?:\.\.?\/)+[^\s]+/g, ' [redacted path]')
    .replace(/[a-zA-Z]:\\[^\s]+/g, '[redacted path]')
    .replace(/\\\\[^\s]+/g, '[redacted path]')
    .replace(/(?:document|chunk|database|evidence)[_-]?id\s*[:=]\s*[^\s,;]+/gi,
      '[redacted id]');
  return bounded(redacted, limit);
}

export class RemoteEvidenceSanitizer {
  sanitize(input: EvidenceUnit[], policy: SharingPolicy, sourceDeviceAlias: string,
    knowledgeDomain: string, updatedAtMs: number): RemoteEvidenceResponse {
    const normalizedDomain: string = normalizeKnowledgeDomain(knowledgeDomain);
    const eligible: EvidenceUnit[] = input.filter((item: EvidenceUnit): boolean =>
      policy.allowedLevels.indexOf(item.level) >= 0 &&
      (normalizedDomain.length === 0 ||
        item.coveredConcepts.some((concept: string): boolean =>
          normalizeKnowledgeDomain(concept) === normalizedDomain)));
    eligible.sort((left: EvidenceUnit, right: EvidenceUnit): number =>
      right.relevance - left.relevance);

    const selected: EvidenceUnit[] = eligible.slice(0, policy.maxEvidenceCount);
    let truncated: boolean = selected.length < input.length;
    const output: RemoteEvidence[] = selected.map((item: EvidenceUnit): RemoteEvidence => {
      const originalSnippet: string = item.snippet ?? item.summary ?? '';
      const summary: string = safeContent(item.summary, 1024);
      const snippet: string = safeContent(originalSnippet, policy.maxSnippetChars);
      const itemTruncated: boolean =
        originalSnippet.length > snippet.length ||
        (item.summary?.length ?? 0) > summary.length ||
        item.title.length > 256;
      truncated = truncated || itemTruncated;
      return new RemoteEvidence(
        safeTitle(item.title),
        summary,
        snippet,
        item.relevance,
        bounded(knowledgeDomain, 128),
        updatedAtMs,
        item.level,
        bounded(sourceDeviceAlias, 128),
        itemTruncated
      );
    });
    return new RemoteEvidenceResponse(output, truncated);
  }
}
