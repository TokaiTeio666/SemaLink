export function normalizeKnowledgeDomain(value: string): string {
  return value
    .replace(/\u3000/g, ' ')
    .trim()
    .replace(/\s+/g, ' ')
    .toLowerCase();
}
