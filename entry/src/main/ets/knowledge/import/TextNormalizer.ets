export function normalizeText(input: string): string {
  let value = input;
  if (value.length > 0 && value.charCodeAt(0) === 0xFEFF) {
    value = value.substring(1);
  }
  value = value.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const lines = value.split('\n');
  const normalized: string[] = [];
  let previousBlank = false;
  for (const line of lines) {
    const cleaned = line.replace(/[\t ]+/g, ' ').trim();
    if (cleaned.length === 0) {
      if (normalized.length > 0 && !previousBlank) {
        normalized.push('');
      }
      previousBlank = true;
    } else {
      normalized.push(cleaned);
      previousBlank = false;
    }
  }
  while (normalized.length > 0 && normalized[normalized.length - 1].length === 0) {
    normalized.pop();
  }
  return normalized.join('\n');
}
