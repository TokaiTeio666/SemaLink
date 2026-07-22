import cryptoFramework from '@ohos.security.cryptoFramework';
import { encodeUtf8 } from './Utf8Codec';
import { EvidenceUnit } from '../../contracts/semantic/SemanticModels';

interface CanonicalEvidence {
  level: string;
  title: string;
  summary: string | null;
  snippet: string | null;
  coveredConcepts: string[];
  relevance: number;
  estimatedCoverageGain: number;
}

interface DigestDataBlob {
  data: Object;
}

export interface Sha256DigestProvider {
  digest(data: Uint8Array): Promise<string>;
}

export interface Sha256ContentDigesterOptions {
  provider?: Sha256DigestProvider;
}

function hex(bytes: Uint8Array): string {
  let result = '';
  for (let i = 0; i < bytes.length; i++) result += bytes[i].toString(16).padStart(2, '0');
  return result;
}

function copyDigestBytes(value: Object): Uint8Array {
  if (value instanceof Uint8Array) {
    const result = new Uint8Array(value.length);
    result.set(value, 0);
    return result;
  }
  return new Uint8Array(value as ArrayBuffer);
}

function digestOutputBytes(value: Object): Uint8Array {
  if (value instanceof Uint8Array || value instanceof ArrayBuffer) {
    return copyDigestBytes(value);
  }
  return copyDigestBytes((value as DigestDataBlob).data);
}

function utf8(text: string): Uint8Array {
  return encodeUtf8(text);
}

export class Sha256ContentDigester {
  private readonly provider: Sha256DigestProvider | null;

  constructor(options?: Sha256ContentDigesterOptions) {
    this.provider = options?.provider ?? null;
  }

  async digestBytes(data: Uint8Array): Promise<string> {
    if (this.provider !== null) {
      return this.provider.digest(data);
    }
    const md = cryptoFramework.createMd('SHA256');
    const input = new Uint8Array(data.length);
    input.set(data, 0);
    await md.update({ data: input });
    const output: Object = await md.digest() as Object;
    return hex(digestOutputBytes(output));
  }

  async digestEvidence(evidence: EvidenceUnit): Promise<string> {
    const canonical: CanonicalEvidence = {
      level: evidence.level,
      title: evidence.title,
      summary: evidence.summary === undefined ? null : evidence.summary,
      snippet: evidence.snippet === undefined ? null : evidence.snippet,
      coveredConcepts: evidence.coveredConcepts.slice().sort(),
      relevance: evidence.relevance,
      estimatedCoverageGain: evidence.estimatedCoverageGain
    };
    return this.digestBytes(utf8(JSON.stringify(canonical)));
  }
}
