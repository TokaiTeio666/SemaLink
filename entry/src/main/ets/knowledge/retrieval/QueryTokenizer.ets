const QUERY_STOP_WORDS: string[] = [
  '为什么', '有什么', '有哪些', '是什么', '怎么样', '怎么', '如何', '是否',
  '有关', '关于', '内容', '数据', '发生', '特性', '作用', '区别', '可以',
  '什么', '哪些', '这个', '那个', '以及', '还有', '会', '的', '和', '与', '是'
];

const WEAK_TERMS: Set<string> = new Set<string>([
  '数据', '内容', '有关', '关于', '信息', '资料', '情况', '问题', '作用', '区别', '特性'
]);

export interface QueryAnalysis {
  normalizedQuery: string;
  primaryTerms: string[];
  ngrams: string[];
  englishTerms: string[];
  numericTerms: string[];
}

function isChinese(code: number): boolean {
  return code >= 0x4E00 && code <= 0x9FFF;
}

function isAsciiLetter(code: number): boolean {
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57;
}

function addUnique(values: string[], seen: Set<string>, value: string): void {
  const normalized = value.toLowerCase().trim();
  if (normalized.length > 0 && !seen.has(normalized)) {
    seen.add(normalized);
    values.push(normalized);
  }
}

function splitByStopWords(sequence: string): string[] {
  let parts: string[] = [sequence];
  for (const stopWord of QUERY_STOP_WORDS) {
    const next: string[] = [];
    for (const part of parts) {
      const pieces = part.split(stopWord);
      for (const piece of pieces) {
        if (piece.length > 0) {
          next.push(piece);
        }
      }
    }
    parts = next;
  }
  return parts;
}

function addChineseAnalysis(sequence: string, primary: string[], primarySeen: Set<string>,
  ngrams: string[], ngramSeen: Set<string>): void {
  if (sequence.length === 0) {
    return;
  }
  const parts = splitByStopWords(sequence);
  for (const part of parts) {
    if (part.length >= 2 && !WEAK_TERMS.has(part)) {
      addUnique(primary, primarySeen, part);
    }
  }
  for (let size = 2; size <= 3; size++) {
    for (let index = 0; index + size <= sequence.length; index++) {
      const token = sequence.substring(index, index + size);
      if (!WEAK_TERMS.has(token)) {
        addUnique(ngrams, ngramSeen, token);
      }
    }
  }
}

function normalizeQuery(query: string): string {
  return query.toLowerCase().replace(/[\s，。？！、；：,.?!;:()（）\[\]【】]+/g, '');
}

export function analyzeQuery(query: string): QueryAnalysis {
  const primaryTerms: string[] = [];
  const ngrams: string[] = [];
  const englishTerms: string[] = [];
  const numericTerms: string[] = [];
  const primarySeen: Set<string> = new Set<string>();
  const ngramSeen: Set<string> = new Set<string>();
  const englishSeen: Set<string> = new Set<string>();
  const numericSeen: Set<string> = new Set<string>();
  let chinese = '';
  let english = '';
  let numeric = '';
  for (let index = 0; index <= query.length; index++) {
    const code = index < query.length ? query.charCodeAt(index) : 0;
    if (isChinese(code)) {
      if (english.length > 0) {
        addUnique(englishTerms, englishSeen, english);
        addUnique(primaryTerms, primarySeen, english);
        english = '';
      }
      if (numeric.length > 0) {
        addUnique(numericTerms, numericSeen, numeric);
        addUnique(primaryTerms, primarySeen, numeric);
        numeric = '';
      }
      chinese += query.charAt(index);
    } else if (isAsciiLetter(code)) {
      if (chinese.length > 0) {
        addChineseAnalysis(chinese, primaryTerms, primarySeen, ngrams, ngramSeen);
        chinese = '';
      }
      if (numeric.length > 0) {
        addUnique(numericTerms, numericSeen, numeric);
        addUnique(primaryTerms, primarySeen, numeric);
        numeric = '';
      }
      english += query.charAt(index);
    } else if (isDigit(code)) {
      if (chinese.length > 0) {
        addChineseAnalysis(chinese, primaryTerms, primarySeen, ngrams, ngramSeen);
        chinese = '';
      }
      if (english.length > 0) {
        addUnique(englishTerms, englishSeen, english);
        addUnique(primaryTerms, primarySeen, english);
        english = '';
      }
      numeric += query.charAt(index);
    } else {
      if (chinese.length > 0) {
        addChineseAnalysis(chinese, primaryTerms, primarySeen, ngrams, ngramSeen);
        chinese = '';
      }
      if (english.length > 0) {
        addUnique(englishTerms, englishSeen, english);
        addUnique(primaryTerms, primarySeen, english);
        english = '';
      }
      if (numeric.length > 0) {
        addUnique(numericTerms, numericSeen, numeric);
        addUnique(primaryTerms, primarySeen, numeric);
        numeric = '';
      }
    }
  }
  return {
    normalizedQuery: normalizeQuery(query),
    primaryTerms: primaryTerms,
    ngrams: ngrams,
    englishTerms: englishTerms,
    numericTerms: numericTerms
  };
}

export function tokenizeQuery(query: string): string[] {
  const analysis = analyzeQuery(query);
  const tokens: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const term of analysis.primaryTerms) {
    addUnique(tokens, seen, term);
  }
  for (const ngram of analysis.ngrams) {
    addUnique(tokens, seen, ngram);
  }
  return tokens;
}
