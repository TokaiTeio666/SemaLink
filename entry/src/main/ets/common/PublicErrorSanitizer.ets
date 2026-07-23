export function publicFrameworkErrorCode(error: Object): string {
  if (error !== null && typeof error === 'object') {
    const code: Object | undefined = (error as Record<string, Object>)['code'];
    if (typeof code === 'number' && Number.isFinite(code)) {
      return 'E_FRAMEWORK_' + Math.trunc(code).toString();
    }
  }
  return 'E_FRAMEWORK_UNKNOWN';
}
