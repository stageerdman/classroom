// Mirrors ClassroomCore's TimenoteFormat.formatTimestamp exactly — both
// sides need to agree on this so a future transcript feature can line up
// with timenotes on the same clock. Kept in sync by hand; there's no
// shared package between the Swift and web code.
export function formatTimestamp(totalSeconds: number): string {
  const clampedSeconds = Math.max(0, totalSeconds);
  const totalMilliseconds = Math.round(clampedSeconds * 1000);
  const hours = Math.floor(totalMilliseconds / 3_600_000);
  const minutes = Math.floor((totalMilliseconds / 60_000) % 60);
  const seconds = Math.floor((totalMilliseconds / 1000) % 60);
  const milliseconds = totalMilliseconds % 1000;

  const pad = (value: number, length = 2) => value.toString().padStart(length, "0");
  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}.${pad(milliseconds, 3)}`;
}

export const timenoteScheme = "classroom-timenote";

export function timenoteHref(seconds: number): string {
  return `${timenoteScheme}:${seconds}`;
}

export function parseTimenoteHref(href: string): number | null {
  if (!href.startsWith(`${timenoteScheme}:`)) {
    return null;
  }
  const seconds = Number.parseFloat(href.slice(timenoteScheme.length + 1));
  return Number.isFinite(seconds) ? seconds : null;
}
