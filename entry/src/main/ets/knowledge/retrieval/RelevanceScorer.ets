import { DocumentChunk } from '../model/DocumentChunk';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import { QueryAnalysis } from './QueryTokenizer';

export interface RelevanceScore {
  relevance: number;
  matchedPrimaryTerms: string[];
  matchedNgrams: string[];
  exactPhraseMatched: boolean;
  passesQualityGate: boolean;
}

function matchedTerms(terms: string[], text: string): string[] {
  const matched: string[] = [];
  const lower = text.toLowerCase();
  for (const term of terms) {
    if (lower.includes(term)) {
      matched.push(term);
    }
  }
  return matched;
}

function ratio(terms: string[], text: string): number {
  if (terms.length === 0) {
    return 0;
  }
  return matchedTerms(terms, text).length / terms.length;
}

function boundedFrequency(primaryTerms: string[], ngrams: string[], text: string): number {
  const lower = text.toLowerCase();
  let weightedHits = 0;
  for (const term of primaryTerms) {
    if (lower.includes(term)) {
      weightedHits += 1;
    }
  }
  for (const ngram of ngrams) {
    if (lower.includes(ngram)) {
      weightedHits += 0.15;
    }
  }
  return Math.min(1, weightedHits / Math.max(1, primaryTerms.length));
}

function compact(text: string): string {
  return text.toLowerCase().replace(/[\s，。？！、；：,.?!;:()（）\[\]【】]+/g, '');
}

export function scoreChunk(analysis: QueryAnalysis, document: KnowledgeDocument,
  chunk: DocumentChunk): RelevanceScore {
  const titleAndTags = document.title + ' ' + document.tags.join(' ');
  const searchableText = titleAndTags + ' ' + chunk.text;
  const matchedPrimary = matchedTerms(analysis.primaryTerms, searchableText);
  const matchedNgrams = matchedTerms(analysis.ngrams, searchableText);
  const normalizedText = compact(searchableText);
  const joinedPrimary = analysis.primaryTerms.join('');
  const exactPhraseMatched = analysis.normalizedQuery.length >= 2 &&
    normalizedText.includes(analysis.normalizedQuery) || joinedPrimary.length >= 2 && normalizedText.includes(joinedPrimary);
  const multiplePrimaryTerms = analysis.primaryTerms.length > 1;
  const passesQualityGate = analysis.primaryTerms.length > 0 &&
    (exactPhraseMatched || !multiplePrimaryTerms && matchedPrimary.length >= 1 ||
      multiplePrimaryTerms && matchedPrimary.length >= 2);
  const titleScore = ratio(analysis.primaryTerms, document.title);
  const tagScore = ratio(analysis.primaryTerms, document.tags.join(' '));
  const coverageScore = analysis.primaryTerms.length === 0 ? 0 : matchedPrimary.length / analysis.primaryTerms.length;
  const frequencyScore = boundedFrequency(analysis.primaryTerms, analysis.ngrams, chunk.text);
  const phraseScore = exactPhraseMatched ? 1 : 0;
  const score = titleScore * 0.25 + tagScore * 0.20 + coverageScore * 0.25 +
    frequencyScore * 0.20 + phraseScore * 0.10;
  return {
    relevance: Math.max(0, Math.min(1, Math.round(score * 10000) / 10000)),
    matchedPrimaryTerms: matchedPrimary,
    matchedNgrams: matchedNgrams,
    exactPhraseMatched: exactPhraseMatched,
    passesQualityGate: passesQualityGate
  };
}
