import { describe, expect, it } from '@ohos/hypium';
import { publicFrameworkErrorCode } from '../main/ets/common/PublicErrorSanitizer';

class FrameworkErrorFixture {
  readonly code: number;
  readonly message: string;

  constructor(code: number, message: string) {
    this.code = code;
    this.message = message;
  }
}

export default function publicErrorSanitizerTest(): void {
  describe('PublicErrorSanitizer', () => {
    it('never exposes an arbitrary framework error message or path', 0, () => {
      const secret: Error = new Error('failed at C:\\private\\certificate.p12');
      expect(publicFrameworkErrorCode(secret)).assertEqual('E_FRAMEWORK_UNKNOWN');
    });

    it('keeps only a finite numeric framework code', 0, () => {
      const frameworkError: FrameworkErrorFixture =
        new FrameworkErrorFixture(16000050, 'sensitive platform details');
      expect(publicFrameworkErrorCode(frameworkError)).assertEqual('E_FRAMEWORK_16000050');
    });
  });
}
