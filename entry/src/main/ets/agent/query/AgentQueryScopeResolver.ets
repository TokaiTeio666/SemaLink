import { AgentQueryScope } from './AgentQueryModels';

const LOCAL_TERMS: string[] = ['本机', '本地', '当前设备'];
const REMOTE_TERMS: string[] = ['其他设备', '另一台设备', '另一台可信设备', '可信设备', '跨设备', '远端'];
const COMBINED_TERMS: string[] = ['同时', '一起', '以及', '和', '与'];

function includesAny(text: string, terms: string[]): boolean {
  for (const term of terms) {
    if (text.indexOf(term) >= 0) {
      return true;
    }
  }
  return false;
}

export class AgentQueryScopeResolver {
  resolve(queryText: string): AgentQueryScope {
    const hasLocal: boolean = includesAny(queryText, LOCAL_TERMS);
    const hasRemote: boolean = includesAny(queryText, REMOTE_TERMS);
    if (hasLocal && hasRemote && includesAny(queryText, COMBINED_TERMS)) {
      return AgentQueryScope.LOCAL_AND_REMOTE;
    }
    if (hasRemote) {
      return AgentQueryScope.REMOTE_ONLY;
    }
    return AgentQueryScope.LOCAL_ONLY;
  }
}
