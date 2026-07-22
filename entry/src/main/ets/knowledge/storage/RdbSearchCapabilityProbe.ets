import { Context } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';

export type RdbSearchBackend = 'FTS5_TRIGRAM' | 'FTS5_DEFAULT' | 'SQL_LIKE';

export interface RdbSearchCapabilities {
  fts5Available: boolean;
  bm25Available: boolean;
  trigramAvailable: boolean;
  chineseSubstringMatchAvailable: boolean;
  defaultChineseSubstringMatchAvailable: boolean;
  probedBackend: RdbSearchBackend;
}

const IMPLEMENTED_RDB_SEARCH_BACKENDS: RdbSearchBackend[] = ['SQL_LIKE'];

export function safeUnavailableRdbSearchCapabilities(): RdbSearchCapabilities {
  return {
    fts5Available: false,
    bm25Available: false,
    trigramAvailable: false,
    chineseSubstringMatchAvailable: false,
    defaultChineseSubstringMatchAvailable: false,
    probedBackend: 'SQL_LIKE'
  };
}

export function chooseRdbSearchBackend(capabilities: RdbSearchCapabilities): RdbSearchBackend {
  if (!capabilities.fts5Available || !capabilities.bm25Available) {
    return 'SQL_LIKE';
  }
  if (capabilities.trigramAvailable && capabilities.chineseSubstringMatchAvailable) {
    return 'FTS5_TRIGRAM';
  }
  if (capabilities.defaultChineseSubstringMatchAvailable) {
    return 'FTS5_DEFAULT';
  }
  return 'SQL_LIKE';
}

export function chooseEnabledRdbSearchBackend(capabilities: RdbSearchCapabilities): RdbSearchBackend {
  const probed = chooseRdbSearchBackend(capabilities);
  if (IMPLEMENTED_RDB_SEARCH_BACKENDS.indexOf(probed) >= 0) return probed;
  return 'SQL_LIKE';
}

function phraseParameter(value: string): string {
  return '"' + value.replace(/"/g, '""') + '"';
}

async function hasMatch(store: relationalStore.RdbStore, tableName: string, queryText: string): Promise<boolean> {
  const result = await store.querySql(
    'SELECT record_id FROM ' + tableName + ' WHERE ' + tableName + ' MATCH ? ORDER BY record_id ASC LIMIT ?',
    [phraseParameter(queryText), 1]);
  try {
    return result.goToNextRow();
  } finally {
    result.close();
  }
}

async function probeFts5(store: relationalStore.RdbStore): Promise<boolean> {
  await store.executeSql('CREATE VIRTUAL TABLE probe_fts USING fts5(record_id UNINDEXED,title,content)');
  await store.executeSql('INSERT INTO probe_fts(record_id,title,content) VALUES (?,?,?)',
    ['en-1', 'Database transaction', 'transaction isolation level']);
  await store.executeSql('INSERT INTO probe_fts(record_id,title,content) VALUES (?,?,?)',
    ['en-2', 'Transaction notes', 'transaction boundaries and rollback']);
  await store.executeSql('INSERT INTO probe_fts(record_id,title,content) VALUES (?,?,?)',
    ['zh-1', '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B',
      '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B\u652F\u6301\u4E00\u81F4\u6027\u8BFB\u53D6 HarmonyOS 24']);
  const matched = await hasMatch(store, 'probe_fts', 'transaction');
  const special = await store.querySql(
    'SELECT record_id FROM probe_fts WHERE probe_fts MATCH ? ORDER BY record_id ASC LIMIT ?',
    [phraseParameter("' OR 1=1 -- %_"), 1]);
  try {
    return matched && !special.goToNextRow();
  } finally {
    special.close();
  }
}

async function probeBm25(store: relationalStore.RdbStore): Promise<boolean> {
  const first = await store.querySql(
    'SELECT record_id,bm25(probe_fts) FROM probe_fts WHERE probe_fts MATCH ? ' +
    'ORDER BY bm25(probe_fts),record_id ASC LIMIT ?', [phraseParameter('transaction'), 1]);
  let firstId = '';
  try {
    if (!first.goToNextRow() || !Number.isFinite(first.getDouble(1))) {
      return false;
    }
    firstId = first.getString(0);
    if (first.goToNextRow()) {
      return false;
    }
  } finally {
    first.close();
  }
  const repeated = await store.querySql(
    'SELECT record_id,bm25(probe_fts) FROM probe_fts WHERE probe_fts MATCH ? ' +
    'ORDER BY bm25(probe_fts),record_id ASC LIMIT ?', [phraseParameter('transaction'), 1]);
  try {
    return repeated.goToNextRow() && repeated.getString(0) === firstId && !repeated.goToNextRow();
  } finally {
    repeated.close();
  }
}

async function probeTrigram(store: relationalStore.RdbStore): Promise<boolean> {
  await store.executeSql(
    "CREATE VIRTUAL TABLE probe_trigram USING fts5(record_id UNINDEXED,title,content,tokenize='trigram')");
  await store.executeSql('INSERT INTO probe_trigram(record_id,title,content) VALUES (?,?,?)',
    ['zh-trigram', '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B',
      '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B HarmonyOS 24']);
  return true;
}

async function probeChineseSubstrings(store: relationalStore.RdbStore, tableName: string): Promise<boolean> {
  const twoCharacterPrefix = await hasMatch(store, tableName, '\u4E8B\u52A1');
  const twoCharacterMiddle = await hasMatch(store, tableName, '\u9694\u79BB');
  const twoCharacterSuffix = await hasMatch(store, tableName, '\u7EA7\u522B');
  const threeCharacters = await hasMatch(store, tableName, '\u4E8B\u52A1\u9694');
  const fullPhrase = await hasMatch(store, tableName, '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B');
  const mixed = await hasMatch(store, tableName, 'HarmonyOS 24');
  return twoCharacterPrefix && twoCharacterMiddle && twoCharacterSuffix && threeCharacters && fullPhrase && mixed;
}

function closeProbeStore(store: relationalStore.RdbStore): void {
  try {
    store.close();
  } catch (error) {
    return;
  }
}

async function deleteProbeStore(context: Context, storeName: string): Promise<void> {
  try {
    await relationalStore.deleteRdbStore(context, storeName);
  } catch (error) {
    return;
  }
}

export class RdbSearchCapabilityProbe {
  async probe(context: Context): Promise<RdbSearchCapabilities> {
    const randomPart = Math.floor(Math.random() * 1000000000).toString();
    const storeName = 'semalink_rdb_search_probe_' + Date.now().toString() + '_' + randomPart + '.db';
    let store: relationalStore.RdbStore | undefined = undefined;
    const capabilities = safeUnavailableRdbSearchCapabilities();
    try {
      store = await relationalStore.getRdbStore(context, {
        name: storeName,
        securityLevel: relationalStore.SecurityLevel.S1
      });
      try {
        capabilities.fts5Available = await probeFts5(store);
      } catch (error) {
        return capabilities;
      }
      if (!capabilities.fts5Available) {
        return capabilities;
      }
      try {
        capabilities.bm25Available = await probeBm25(store);
      } catch (error) {
        capabilities.bm25Available = false;
      }
      try {
        capabilities.defaultChineseSubstringMatchAvailable = await probeChineseSubstrings(store, 'probe_fts');
      } catch (error) {
        capabilities.defaultChineseSubstringMatchAvailable = false;
      }
      try {
        capabilities.trigramAvailable = await probeTrigram(store);
      } catch (error) {
        capabilities.trigramAvailable = false;
      }
      if (capabilities.trigramAvailable) {
        try {
          capabilities.chineseSubstringMatchAvailable = await probeChineseSubstrings(store, 'probe_trigram');
        } catch (error) {
          capabilities.chineseSubstringMatchAvailable = false;
        }
      }
      capabilities.probedBackend = chooseRdbSearchBackend(capabilities);
      return capabilities;
    } catch (error) {
      return capabilities;
    } finally {
      if (store !== undefined) {
        closeProbeStore(store);
      }
      await deleteProbeStore(context, storeName);
    }
  }
}
