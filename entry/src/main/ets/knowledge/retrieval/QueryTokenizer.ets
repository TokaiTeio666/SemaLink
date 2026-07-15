const QUERY_STOP_WORDS: string[] = [
  '为什么', '有什么', '有哪些', '是什么', '怎么样', '怎么', '如何', '是否',
  '有关', '关于', '内容', '数据', '发生', '特性', '作用', '区别', '可以',
  '什么', '哪些', '这个', '那个', '以及', '还有', '会', '的', '和', '与', '是'
];

const WEAK_TERMS: Set<string> = new Set<string>([
  '数据', '内容', '有关', '关于', '信息', '资料', '情况', '问题', '作用', '区别', '特性',
  '系统', '类型', '工程', '阶段', '路径', '机制', '任务', '结果', '影响', '能力'
]);

const DOMAIN_CONCEPT_TERMS: string[] = [
  '进程', '线程', '隔离', '调度', '执行', '共享', '地址空间', '文件', '堆', '栈',
  '时间片', '优先级', '老化', '饥饿', '队列', '吞吐量', '响应时间',
  '单元测试', '集成测试', '系统测试', '验收测试', '回归测试', '需求', '验收标准',
  'arkts', 'arkui', '强类型', '静态类型', '声明式', '页面', '业务', '边界',
  '生命周期', 'uiability', 'windowstage',
  'tcp', '字节流', '粘包', '拆包', '半包', '消息边界', '长度前缀', '重传', '确认',
  '序列号', '接收窗口', '流量控制', '拥塞控制', '慢启动', '心跳', '重连', '超时', 'tls',
  '事务', '原子性', '一致性', '隔离性', '持久性', '回滚', '隔离级别', '脏读', '幻读',
  '索引', '复合索引', '唯一索引', '全表扫描', '优化器', '统计信息', '范围查询',
  '数据竞争', '互斥', '临界区', '条件变量', '信号量', '读写锁', '死锁', '取消', '背压'
];

interface ConceptAlias {
  expression: string;
  canonicalTerm: string;
}

const DOMAIN_CONCEPT_ALIASES: ConceptAlias[] = [
  { expression: '程序', canonicalTerm: '进程' },
  { expression: '执行单元', canonicalTerm: '线程' },
  { expression: '静态类型', canonicalTerm: '强类型' },
  { expression: '没有机会运行', canonicalTerm: '饥饿' },
  { expression: '消息定界', canonicalTerm: '消息边界' },
  { expression: '失败后恢复', canonicalTerm: '回滚' }
];

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
  for (const concept of DOMAIN_CONCEPT_TERMS) {
    if (sequence.toLowerCase().includes(concept)) {
      addUnique(primary, primarySeen, concept);
    }
  }
  for (const alias of DOMAIN_CONCEPT_ALIASES) {
    if (sequence.includes(alias.expression)) {
      addUnique(primary, primarySeen, alias.canonicalTerm);
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
