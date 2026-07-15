import { abilityAccessCtrl, common, PermissionRequestResult, Permissions }
  from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const GRANTED: number = abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;

export interface PermissionRequester {
  request(context: common.UIAbilityContext, permissions: Array<Permissions>):
    Promise<PermissionRequestResult>;
}

class RealPermissionRequester implements PermissionRequester {
  request(context: common.UIAbilityContext, permissions: Array<Permissions>):
    Promise<PermissionRequestResult> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    try {
      return atManager.requestPermissionsFromUser(context, permissions);
    } catch (error) {
      throw error as Error;
    }
  }
}

export class DistributedPermissionController {
  private granted: boolean = false;
  private finished: boolean = false;
  private readonly requester: PermissionRequester;

  constructor(requester?: PermissionRequester) {
    this.requester = requester ?? new RealPermissionRequester();
  }

  isGranted(): boolean {
    return this.granted;
  }

  isFinished(): boolean {
    return this.finished;
  }

  evaluateResult(result: PermissionRequestResult): boolean {
    if (result.authResults.length > 0 && result.authResults[0] === GRANTED) {
      this.granted = true;
    } else {
      this.granted = false;
    }
    this.finished = true;
    return this.granted;
  }

  setDenied(): void {
    this.granted = false;
    this.finished = true;
  }

  async request(context: common.UIAbilityContext, permissions: Array<Permissions>): Promise<boolean> {
    try {
      const result: PermissionRequestResult =
        await this.requester.request(context, permissions);
      return this.evaluateResult(result);
    } catch (err) {
      const businessError: BusinessError = err as BusinessError;
      this.granted = false;
      this.finished = true;
      return false;
    }
  }
}
