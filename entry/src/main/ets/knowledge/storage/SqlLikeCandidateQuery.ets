import { relationalStore } from '@kit.ArkData';
import { analyzeQuery, QueryAnalysis } from '../retrieval/QueryTokenizer';
import { KnowledgeRetrievalRequest } from '../retrieval/RetrievalEngine';
import { validateKnowledgeRetrievalRequest } from '../retrieval/KnowledgeRetrievalRequestValidator';

export const MAX_SQL_LIKE_SEARCH_TERMS: number = 32;
const MAX_SQL_LIKE_PRIMARY_TERMS: number = 8;

export interface SqlLikeCandidateQuery {
  sql: string;
  bindArgs: relationalStore.ValueType[];
  terms: string[];
  primaryTerms: string[];
  ngrams: string[];
}

function addTerm(terms: string[], seen: Set<string>, value: string): void {
  const normalized = value.toLowerCase().trim();
  if (normalized.length > 0 && !seen.has(normalized) && terms.length < MAX_SQL_LIKE_SEARCH_TERMS) {
    seen.add(normalized);
    terms.push(normalized);
  }
}

interface BoundedSearchTerms {
  all: string[];
  primary: string[];
  ngrams: string[];
}

function searchTerms(request: KnowledgeRetrievalRequest): BoundedSearchTerms {
  const analysis: QueryAnalysis = analyzeQuery(request.queryText);
  const terms: string[] = [];
  const primary: string[] = [];
  const ngrams: string[] = [];
  const seen = new Set<string>();
  for (const term of analysis.primaryTerms) {
    if (primary.length >= MAX_SQL_LIKE_PRIMARY_TERMS) break;
    const before = terms.length;
    addTerm(terms, seen, term);
    if (terms.length > before) primary.push(terms[terms.length - 1]);
  }
  const ngramCandidates: string[] = [];
  const candidateSeen = new Set<string>();
  for (let size = 3; size >= 2; size--) {
    for (const term of analysis.ngrams) {
      if (term.length !== size) continue;
      const normalized = term.toLowerCase().trim();
      if (normalized.length > 0 && !seen.has(normalized) && !candidateSeen.has(normalized)) {
        candidateSeen.add(normalized);
        ngramCandidates.push(normalized);
      }
    }
  }
  const availableSlots = MAX_SQL_LIKE_SEARCH_TERMS - terms.length;
  const selectedCount = Math.min(availableSlots, ngramCandidates.length);
  for (let slot = 0; slot < selectedCount; slot++) {
    const index = Math.floor(slot * ngramCandidates.length / selectedCount);
    const before = terms.length;
    addTerm(terms, seen, ngramCandidates[index]);
    if (terms.length > before) ngrams.push(terms[terms.length - 1]);
  }
  return { all: terms, primary: primary, ngrams: ngrams };
}

function placeholders(count: number): string {
  const values: string[] = [];
  for (let index = 0; index < count; index++) {
    values.push('?');
  }
  return values.join(',');
}

function scoreForTerm(primary: boolean): string {
  const titleWeight = primary ? 25 : 6;
  const tagWeight = primary ? 20 : 4;
  const contentWeight = primary ? 20 : 3;
  const derivedWeight = primary ? 5 : 1;
  return '(CASE WHEN INSTR(LOWER(d.title),?)>0 THEN ' + titleWeight.toString() + ' ELSE 0 END+' +
    'CASE WHEN INSTR(LOWER(d.tags_json),?)>0 THEN ' + tagWeight.toString() + ' ELSE 0 END+' +
    'CASE WHEN INSTR(LOWER(c.chunk_text),?)>0 THEN ' + contentWeight.toString() +
    ' WHEN INSTR(LOWER(c.summary),?)>0 OR INSTR(LOWER(c.keywords_json),?)>0 THEN ' +
    derivedWeight.toString() + ' ELSE 0 END)';
}

function addWeightedScores(bindArgs: relationalStore.ValueType[], terms: string[], primary: boolean,
  scores: string[]): void {
  for (const term of terms) {
    scores.push(scoreForTerm(primary));
    for (let field = 0; field < 5; field++) bindArgs.push(term);
  }
}

function addScoreArguments(bindArgs: relationalStore.ValueType[], terms: BoundedSearchTerms): string {
  const scores: string[] = [];
  addWeightedScores(bindArgs, terms.primary, true, scores);
  addWeightedScores(bindArgs, terms.ngrams, false, scores);
  return scores.join('+');
}

function addPrimaryHitArguments(bindArgs: relationalStore.ValueType[], primaryTerms: string[]): string {
  const hits: string[] = [];
  for (const term of primaryTerms) {
    hits.push('(CASE WHEN INSTR(LOWER(d.title),?)>0 OR INSTR(LOWER(d.tags_json),?)>0 OR ' +
      'INSTR(LOWER(c.chunk_text),?)>0 OR INSTR(LOWER(c.summary),?)>0 OR ' +
      'INSTR(LOWER(c.keywords_json),?)>0 THEN 1 ELSE 0 END)');
    for (let field = 0; field < 5; field++) bindArgs.push(term);
  }
  return hits.length === 0 ? '0' : hits.join('+');
}

function addStrongNgramHitArguments(bindArgs: relationalStore.ValueType[], ngrams: string[]): string {
  const hits: string[] = [];
  for (const term of ngrams) {
    if (term.length < 3) continue;
    hits.push('(CASE WHEN INSTR(LOWER(d.title),?)>0 OR INSTR(LOWER(d.tags_json),?)>0 OR ' +
      'INSTR(LOWER(c.chunk_text),?)>0 OR INSTR(LOWER(c.summary),?)>0 OR ' +
      'INSTR(LOWER(c.keywords_json),?)>0 THEN 1 ELSE 0 END)');
    for (let field = 0; field < 5; field++) bindArgs.push(term);
  }
  return hits.length === 0 ? '0' : hits.join('+');
}

export function buildSqlLikeCandidateQuery(request: KnowledgeRetrievalRequest): SqlLikeCandidateQuery | undefined {
  validateKnowledgeRetrievalRequest(request);
  const terms: BoundedSearchTerms = searchTerms(request);
  if (terms.all.length === 0 || terms.primary.length === 0) {
    return undefined;
  }
  const bindArgs: relationalStore.ValueType[] = [];
  const scoreExpression: string = addScoreArguments(bindArgs, terms);
  const primaryHitExpression: string = addPrimaryHitArguments(bindArgs, terms.primary);
  const strongNgramHitExpression: string = addStrongNgramHitArguments(bindArgs, terms.ngrams);
  const where: string[] = [];
  if (request.privacyLevel === 'PRIVATE_GROUP') {
    where.push('d.privacy_level=?');
    bindArgs.push('PRIVATE_GROUP');
  } else {
    where.push('d.privacy_level IN (?,?)');
    bindArgs.push('LOCAL_ONLY');
    bindArgs.push('PRIVATE_GROUP');
  }
  const filters = request.filters;
  if (filters?.documentIds !== undefined && filters.documentIds.length > 0) {
    where.push('d.document_id IN (' + placeholders(filters.documentIds.length) + ')');
    for (const value of filters.documentIds) bindArgs.push(value);
  }
  if (filters?.tags !== undefined && filters.tags.length > 0) {
    for (const value of filters.tags) {
      where.push('INSTR(d.tags_json,?)>0');
      bindArgs.push(JSON.stringify(value));
    }
  }
  if (filters?.modalities !== undefined && filters.modalities.length > 0) {
    where.push('d.modality IN (' + placeholders(filters.modalities.length) + ')');
    for (const value of filters.modalities) bindArgs.push(value);
  }
  if (filters?.updatedAfter !== undefined) {
    where.push('d.updated_at>?');
    bindArgs.push(filters.updatedAfter);
  }
  bindArgs.push(Math.max(1, Math.floor(request.topK)));
  const sql = 'WITH ranked AS (SELECT d.document_id AS document_id,d.title AS title,d.modality AS modality,' +
    'd.tags_json AS tags_json,d.updated_at AS document_updated_at,d.privacy_level AS privacy_level,' +
    'c.chunk_id AS chunk_id,c.chunk_index AS chunk_index,c.chunk_text AS chunk_text,c.summary AS summary,' +
    'c.keywords_json AS keywords_json,c.start_offset AS start_offset,c.end_offset AS end_offset,' +
    'c.updated_at AS chunk_updated_at,' + scoreExpression + ' AS raw_score,' +
    primaryHitExpression + ' AS primary_hits,' + strongNgramHitExpression + ' AS strong_ngram_hits FROM documents d ' +
    'INNER JOIN document_chunks c ON c.document_id=d.document_id WHERE ' + where.join(' AND ') +
    ') SELECT * FROM ranked WHERE raw_score>0 AND ' +
    (terms.primary.length === 1 ?
      '(primary_hits>=1 OR (strong_ngram_hits>=2 AND raw_score>=6) OR ' +
      '(primary_hits=0 AND strong_ngram_hits>=1 AND raw_score>=3)) ' :
      '(primary_hits>=2 OR (primary_hits>=1 AND raw_score>=30) OR ' +
      '(strong_ngram_hits>=2 AND raw_score>=6) OR ' +
      '(primary_hits=0 AND strong_ngram_hits>=1 AND raw_score>=3)) ') +
    'ORDER BY raw_score DESC,document_id ASC,chunk_id ASC LIMIT ?';
  return {
    sql: sql, bindArgs: bindArgs, terms: terms.all,
    primaryTerms: terms.primary, ngrams: terms.ngrams
  };
}
