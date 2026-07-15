import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x534C;
const TAG: string = 'SemaLink';

export class Logger {
  info(event: string, message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', event + ' ' + message);
  }

  error(event: string, message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', event + ' ' + message);
  }
}
