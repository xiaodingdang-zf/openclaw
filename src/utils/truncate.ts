/**
 * Truncate a string to a maximum length, appending a suffix (default "…")
 * when truncation occurs.
 *
 * When `wordBreak` is true, attempts to break at the last space within the
 * allowed length if the break point is past 60% of `maxLength`.
 */
export function truncateText(
  value: string,
  maxLength: number,
  options?: { suffix?: string; trim?: boolean; wordBreak?: boolean },
): string {
  const suffix = options?.suffix ?? "…";
  const doTrim = options?.trim !== false;
  const text = doTrim ? value.trim() : value;
  if (maxLength <= 0) {
    return "";
  }
  if (text.length <= maxLength) {
    return text;
  }
  if (maxLength <= suffix.length) {
    return text.slice(0, maxLength);
  }
  const cutLength = maxLength - suffix.length;
  if (options?.wordBreak) {
    const cut = text.slice(0, cutLength);
    const lastSpace = cut.lastIndexOf(" ");
    if (lastSpace > maxLength * 0.6) {
      return cut.slice(0, lastSpace) + suffix;
    }
  }
  return text.slice(0, cutLength).trimEnd() + suffix;
}
