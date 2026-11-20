try {
  const response = await fetch('http://127.0.0.1:8787/healthz', { signal: AbortSignal.timeout(2000) });
  const status = await response.json();
  if (!response.ok || status.media !== 'direct-only') process.exit(1);
  if (process.argv.includes('--tunnel')) {
    const ready = await fetch('http://127.0.0.1:2000/ready', { signal: AbortSignal.timeout(2000) });
    if (!ready.ok) process.exit(1);
  }
} catch {
  process.exit(1);
}
