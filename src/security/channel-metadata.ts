import { truncateText } from "../utils/truncate.js";
import { wrapExternalContent } from "./external-content.js";

const DEFAULT_MAX_CHARS = 800;
const DEFAULT_MAX_ENTRY_CHARS = 400;

function normalizeEntry(entry: string): string {
  return entry.replace(/\s+/g, " ").trim();
}

export function buildUntrustedChannelMetadata(params: {
  source: string;
  label: string;
  entries: Array<string | null | undefined>;
  maxChars?: number;
}): string | undefined {
  const cleaned = params.entries
    .map((entry) => (typeof entry === "string" ? normalizeEntry(entry) : ""))
    .filter((entry) => Boolean(entry))
    .map((entry) => truncateText(entry, DEFAULT_MAX_ENTRY_CHARS, { suffix: "..." }));
  const deduped = cleaned.filter((entry, index, list) => list.indexOf(entry) === index);
  if (deduped.length === 0) {
    return undefined;
  }

  const body = deduped.join("\n");
  const header = `UNTRUSTED channel metadata (${params.source})`;
  const labeled = `${params.label}:\n${body}`;
  const truncated = truncateText(`${header}\n${labeled}`, params.maxChars ?? DEFAULT_MAX_CHARS, {
    suffix: "...",
  });

  return wrapExternalContent(truncated, {
    source: "channel_metadata",
    includeWarning: false,
  });
}
