import { analyzeQuery, QueryAnalysis } from '../retrieval/QueryTokenizer';

interface CountedKeyword {
  value: string;
  count: number;
}

function countOccurrences(text: string, keyword: string): number {
  let count = 0;
  let position = 0;
  while (position < text.length) {
    const match: number = text.indexOf(keyword, position);
    if (match < 0) {
      break;
    }
    count += 1;
    position = match + keyword.length;
  }
  return count;
}

export class KeywordExtractor {
  extract(title: string, text: string): string[] {
    const source: string = title + ' ' + text;
    const analysis: QueryAnalysis = analyzeQuery(source);
    const candidates: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const term of analysis.primaryTerms) {
      if (term.length >= 2 && !seen.has(term)) {
        seen.add(term);
        candidates.push(term);
      }
    }
    for (const ngram of analysis.ngrams) {
      if (ngram.length >= 2 && !seen.has(ngram)) {
        seen.add(ngram);
        candidates.push(ngram);
      }
    }
    const counted: CountedKeyword[] = [];
    const normalized: string = source.toLowerCase();
    for (const candidate of candidates) {
      counted.push({ value: candidate, count: countOccurrences(normalized, candidate) });
    }
    counted.sort((left: CountedKeyword, right: CountedKeyword): number => {
      if (left.count !== right.count) {
        return right.count - left.count;
      }
      if (left.value.length !== right.value.length) {
        return right.value.length - left.value.length;
      }
      return left.value < right.value ? -1 : left.value > right.value ? 1 : 0;
    });
    const result: string[] = [];
    for (let index = 0; index < counted.length && index < 8; index++) {
      result.push(counted[index].value);
    }
    return result;
  }
}
