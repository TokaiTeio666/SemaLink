const DANGEROUS_SCHEMES: Set<string> = new Set<string>([
  'file', 'content', 'datashare', 'http', 'https', 'ftp', 'data'
]);

function hasDangerousScheme(value: string): boolean {
  const separator = value.indexOf(':');
  if (separator <= 0) return false;
  const scheme = value.substring(0, separator);
  if (!/^[A-Za-z][A-Za-z0-9+.-]*$/.test(scheme)) return false;
  return DANGEROUS_SCHEMES.has(scheme.toLowerCase());
}

export function isSafeKnowledgeFilterValue(value: string): boolean {
  if (value.length === 0 || value !== value.trim()) return false;
  if (hasDangerousScheme(value) || /^[A-Za-z]:/.test(value)) return false;
  return !value.startsWith('/') && !value.startsWith('\\\\');
}
