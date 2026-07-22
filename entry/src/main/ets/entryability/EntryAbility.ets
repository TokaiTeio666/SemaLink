import { abilityAccessCtrl, AbilityConstant, ConfigurationConstant, PermissionRequestResult, Permissions, UIAbility, Want }
  from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppRuntime } from '../runtime/AppRuntime';

const DOMAIN = 0x0000;

let abilityInstance: EntryAbility | null = null;

export function getEntryAbility(): EntryAbility | null {
  return abilityInstance;
}

export default class EntryAbility extends UIAbility {
  private distributedPermissionGranted: boolean = false;
  private permissionRequestFinished: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    abilityInstance = this;
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');

    const runtime: AppRuntime = AppRuntime.initialize(this.context);
    runtime.initializeKnowledge(this.context).catch((error: Object) => {
      hilog.error(DOMAIN, 'testTag', 'Knowledge initialization failed. Cause: %{public}s', JSON.stringify(error));
    });
  }

  onCollaborate(wantParam: Record<string, Object>): AbilityConstant.CollaborateResult {
    return AppRuntime.current().acceptCollaboration(wantParam)
      ? AbilityConstant.CollaborateResult.ACCEPT
      : AbilityConstant.CollaborateResult.REJECT;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    AppRuntime.reset();
    abilityInstance = null;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      AppRuntime.current().initializeKnowledge(this.context).catch((error: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Knowledge initialization failed: %{public}s', error.message);
      });
      this.requestDistributedPermission()
        .then((granted: boolean) => {
          hilog.info(DOMAIN, 'testTag', 'permission_request_finished: %{public}s',
            granted ? 'granted' : 'denied');
        });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  isDistributedPermissionGranted(): boolean {
    return this.distributedPermissionGranted;
  }

  isPermissionRequestFinished(): boolean {
    return this.permissionRequestFinished;
  }

  private async requestDistributedPermission(): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.DISTRIBUTED_DATASYNC'] as Permissions[];
    try {
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(this.context, permissions);
      if (result.authResults.length > 0 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        this.distributedPermissionGranted = true;
        this.permissionRequestFinished = true;
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'distributed_permission_granted');
        return true;
      } else {
        this.distributedPermissionGranted = false;
        this.permissionRequestFinished = true;
        hilog.error(DOMAIN, 'testTag', '%{public}s', 'distributed_permission_denied');
        return false;
      }
    } catch (err) {
      const businessError: BusinessError = err as BusinessError;
      this.distributedPermissionGranted = false;
      this.permissionRequestFinished = true;
      hilog.error(DOMAIN, 'testTag', 'distributed_permission_denied: code=%{public}d message=%{public}s',
        businessError.code, businessError.message);
      return false;
    }
  }
}
