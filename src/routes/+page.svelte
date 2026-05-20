<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { fly, fade } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';

  const ACCENT = 'fizx';
  const REST = '';
  const ALL_CHARS = (ACCENT + REST).split('').map((ch, i) => ({ ch, isAccent: i < ACCENT.length }));
  const LETTER_DURATION = 350;
  const LETTER_STAGGER = ALL_CHARS.length > 1 ? (1200 - LETTER_DURATION) / (ALL_CHARS.length - 1) : 0;

  // ── Event kind → NIP mapping ──────────────────────────────────────────────────
  const KIND_MAP = [
    { kind: 0,     label: 'Profile',        nip: 1  },
    { kind: 1,     label: 'Note',           nip: 1  },
    { kind: 3,     label: 'Follows',        nip: 2  },
    { kind: 4,     label: 'Enc DM',         nip: 4  },
    { kind: 5,     label: 'Delete',         nip: 9  },
    { kind: 6,     label: 'Repost',         nip: 18 },
    { kind: 7,     label: 'Reaction',       nip: 25 },
    { kind: 8,     label: 'Badge',          nip: 58 },
    { kind: 9,     label: 'Chat Msg',       nip: 29 },
    { kind: 10,    label: 'Group Reply',    nip: 29 },
    { kind: 11,    label: 'Thread',         nip: 29 },
    { kind: 12,    label: 'Thread Reply',   nip: 29 },
    { kind: 16,    label: 'Generic Repost', nip: 18 },
    { kind: 17,    label: 'Web React',      nip: 25 },
    { kind: 20,    label: 'Picture',        nip: 68 },
    { kind: 22,    label: 'Short Video',    nip: 71 },
    { kind: 40,    label: 'Channel',        nip: 28 },
    { kind: 1059,  label: 'Gift Wrap',      nip: 17 },
    { kind: 1063,  label: 'File Meta',      nip: 94 },
    { kind: 9735,  label: 'Zap',            nip: 57 },
    { kind: 10002, label: 'Relay List',     nip: 65 },
    { kind: 30023, label: 'Long-form',      nip: 23 },
    { kind: 30078, label: 'App Data',       nip: 78 },
  ];
  $: supportedNips = Array.isArray(relayInfo?.supported_nips) ? (relayInfo!.supported_nips as number[]) : [];
  $: isGrasp = supportedNips.includes(34);

  // ── Nostr login (NIP-07 + NIP-55) ────────────────────────────────────────────
  declare global { interface Window { nostr?: { getPublicKey(): Promise<string> } } }
  let pubkey: string | null = null;
  try {
    const _p = new URLSearchParams(window.location.search);
    const _nip55 = _p.get('nostr_pk');
    if (_nip55) { pubkey = _nip55; localStorage.setItem('nostr_pubkey', _nip55); }
    else { pubkey = localStorage.getItem('nostr_pubkey'); }
  } catch { try { pubkey = localStorage.getItem('nostr_pubkey'); } catch {} }
  async function login() {
    if (typeof window !== 'undefined' && window.nostr) {
      try { const pk = await window.nostr.getPublicKey(); if (pk) { pubkey = pk; localStorage.setItem('nostr_pubkey', pk); } } catch {}
      return;
    }
    const cb = `${window.location.origin}${window.location.pathname}?nostr_pk={signature}`;
    window.location.href = `nostrsigner:getpubkey?compressionType=none&returnType=signature&type=get_public_key&callbackUrl=${encodeURIComponent(cb)}`;
  }
  function logout() { pubkey = null; try { localStorage.removeItem('nostr_pubkey'); } catch {} }

  // ── Relay status ───────────────────────────────────────────────────────────────
  type RelayStatus = 'checking' | 'online' | 'offline';
  let wsStatus: RelayStatus = 'checking';
  let nip11Status: 'loading' | 'ok' | 'error' = 'loading';
  let relayInfo: Record<string, unknown> | null = null;
  let lastChecked: string | null = null;
  let wsLatency: number | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;

  // Combined online status for the indicator dot
  $: relayOnline = wsStatus === 'online' ? true : wsStatus === 'offline' ? false : null;

  function checkRelay() {
    wsStatus = 'checking';
    nip11Status = 'loading';
    wsLatency = null;
    if (retryTimer) { clearTimeout(retryTimer); retryTimer = null; }

    // NIP-11 fetch
    fetch('https://relay.fizx.uk', { headers: { Accept: 'application/nostr+json' } })
      .then(r => r.json())
      .then((d: Record<string, unknown>) => { relayInfo = d; nip11Status = 'ok'; })
      .catch(() => { nip11Status = 'error'; });

    // WebSocket connectivity + latency
    const t0 = Date.now();
    let wsOpened = false;
    const wsTimeout = setTimeout(() => {
      if (!wsOpened) {
        wsStatus = 'offline';
        lastChecked = new Date().toLocaleTimeString();
        retryTimer = setTimeout(checkRelay, 30000);
      }
    }, 8000);
    try {
      const ws = new WebSocket('wss://relay.fizx.uk');
      ws.onopen = () => {
        wsOpened = true;
        clearTimeout(wsTimeout);
        wsLatency = Date.now() - t0;
        wsStatus = 'online';
        lastChecked = new Date().toLocaleTimeString();
        ws.close();
        // Refresh NIP-11 info periodically while online
        retryTimer = setTimeout(checkRelay, 5 * 60 * 1000);
      };
      ws.onerror = () => {
        if (!wsOpened) {
          clearTimeout(wsTimeout);
          wsStatus = 'offline';
          lastChecked = new Date().toLocaleTimeString();
          retryTimer = setTimeout(checkRelay, 30000);
        }
      };
      ws.onclose = () => {
        if (!wsOpened) {
          clearTimeout(wsTimeout);
          if (wsStatus === 'checking') {
            wsStatus = 'offline';
            lastChecked = new Date().toLocaleTimeString();
            retryTimer = setTimeout(checkRelay, 30000);
          }
        }
      };
    } catch {
      clearTimeout(wsTimeout);
      wsStatus = 'offline';
      lastChecked = new Date().toLocaleTimeString();
      retryTimer = setTimeout(checkRelay, 30000);
    }
  }

  onMount(() => {
    if (new URLSearchParams(window.location.search).get('nostr_pk'))
      window.history.replaceState({}, '', window.location.pathname);
    checkRelay();
    openSamplesFeed();
    return () => {
      if (retryTimer) clearTimeout(retryTimer);
      if (samplesWs) samplesWs.close();
    };
  });

  const vibeProjects = [
    {
      href: 'https://blst.fizx.uk',
      label: 'blst',
      desc: 'rebroadcaster',
      color: 'purple',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 11l19-9-9 19-2-8-8-2z"/>
      </svg>`,
    },
    {
      href: 'https://glmps.fizx.uk',
      label: 'glmps',
      desc: 'discography',
      color: 'emerald',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="9"/>
        <circle cx="12" cy="12" r="3" fill="#a78bfa" stroke="none"/>
      </svg>`,
    },
    {
      href: 'https://npub.fizx.uk',
      label: 'npub',
      desc: 'relay.fizx.uk profiles',
      color: 'emerald',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="8" r="4"/>
        <path d="M4 20c0-4 3.582-7 8-7s8 3 8 7"/>
      </svg>`,
    },
    {
      href: 'https://pls.fizx.uk',
      label: 'pls',
      desc: 'relay dashboard',
      color: 'purple',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="3,17 9,11 13,15 21,7"/>
        <polyline points="15,7 21,7 21,13"/>
      </svg>`,
    },
    {
      href: 'https://smpl.fizx.uk',
      label: 'smpl',
      desc: 'audio',
      color: 'emerald',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="2" stroke-linecap="round">
        <line x1="2" y1="12" x2="2" y2="12"/>
        <line x1="6" y1="8" x2="6" y2="16"/>
        <line x1="10" y1="5" x2="10" y2="19"/>
        <line x1="14" y1="8" x2="14" y2="16"/>
        <line x1="18" y1="10" x2="18" y2="14"/>
        <line x1="22" y1="12" x2="22" y2="12"/>
      </svg>`,
    },
  ];

  // Footer-only inline link chips (ln + recipes + relay).
  const footerLinks = [
    {
      href: 'https://ln.fizx.uk',
      label: 'ln',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="#a78bfa">
        <path d="M13 2L4.5 13.5H11L10 22L20.5 10.5H14L13 2z"/>
      </svg>`,
    },
    {
      href: 'https://recipes.fizx.uk',
      label: 'recipes',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/>
        <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>
      </svg>`,
    },
    {
      href: 'https://relay.fizx.uk',
      label: 'relay',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"/>
      </svg>`,
    },
  ];

  // ── Recent samples feed (smpl kind:1063 from relay.fizx.uk) ─────────────────
  interface NostrEvent {
    id: string;
    pubkey: string;
    created_at: number;
    kind: number;
    tags: string[][];
    content: string;
    sig: string;
  }
  interface Sample {
    id: string;
    pubkey: string;
    created_at: number;
    url: string;
    title: string;
    mime?: string;
    tagged?: string[];
    raw: NostrEvent;  // full event kept so we can republish without re-fetching
  }
  const AUDIO_MIME_RE = /^audio\//i;
  const AUDIO_EXT_RE  = /\.(mp3|ogg|wav|flac|m4a|aac|opus|weba)(\?.*)?$/i;

  let samples: Sample[] = [];
  let samplesWs: WebSocket | null = null;
  let playingId: string | null = null;
  let audioEl: HTMLAudioElement;
  // Per-sample republish status — keyed by event id
  let republishStatus: Record<string, 'idle' | 'sending' | 'ok' | 'err'> = {};

  function setRepublishStatus(id: string, s: 'idle' | 'sending' | 'ok' | 'err') {
    republishStatus = { ...republishStatus, [id]: s };
  }

  /** Send the original (already-signed) event to wss://relay.fizx.uk.
   * Useful for ensuring an event is on the primary relay even if it was
   * originally seen elsewhere. The relay returns OK true even for
   * duplicates (NIP-20), so this is idempotent and harmless. */
  function republishToRelay(s: Sample) {
    setRepublishStatus(s.id, 'sending');
    let settled = false;
    const ws = new WebSocket('wss://relay.fizx.uk');
    const cleanup = () => { try { ws.close(); } catch { /* */ } };
    const t = setTimeout(() => {
      if (settled) return; settled = true;
      setRepublishStatus(s.id, 'err'); cleanup();
      setTimeout(() => setRepublishStatus(s.id, 'idle'), 2500);
    }, 8000);
    ws.onopen = () => { try { ws.send(JSON.stringify(['EVENT', s.raw])); } catch { /* */ } };
    ws.onmessage = (ev) => {
      if (settled) return;
      try {
        const msg = JSON.parse(ev.data as string);
        if (msg[0] === 'OK' && msg[1] === s.id) {
          settled = true; clearTimeout(t); cleanup();
          setRepublishStatus(s.id, msg[2] ? 'ok' : 'err');
          setTimeout(() => setRepublishStatus(s.id, 'idle'), 2500);
        }
      } catch { /* */ }
    };
    ws.onerror = () => {
      if (settled) return; settled = true; clearTimeout(t); cleanup();
      setRepublishStatus(s.id, 'err');
      setTimeout(() => setRepublishStatus(s.id, 'idle'), 2500);
    };
  }

  // Priority: own > mentions > public; then chronological desc. Cap at 18 rows
  // (3-col grid = 6 visible rows on desktop; chips are tight so this fits).
  $: visibleSamples = (() => {
    const me = pubkey;
    const scored = samples.map(s => {
      const own = me && s.pubkey === me ? 0 : null;
      const ment = me && !own && s.tagged?.includes(me) ? 1 : null;
      const priority = own !== null ? own : ment !== null ? ment : 2;
      return { ...s, priority };
    });
    return scored
      .sort((a, b) => a.priority - b.priority || b.created_at - a.created_at)
      .slice(0, 18);
  })();

  function relTime(t: number): string {
    const diff = Date.now() / 1000 - t;
    if (diff < 60)     return 'just now';
    if (diff < 3600)   return `${Math.floor(diff / 60)}m`;
    if (diff < 86400)  return `${Math.floor(diff / 3600)}h`;
    if (diff < 604800) return `${Math.floor(diff / 86400)}d`;
    return new Date(t * 1000).toLocaleDateString();
  }

  function togglePlay(s: Sample) {
    if (!audioEl) return;
    if (playingId === s.id) {
      audioEl.pause();
      playingId = null;
      return;
    }
    audioEl.src = s.url;
    audioEl.play()
      .then(() => { playingId = s.id; })
      .catch(() => { playingId = null; });
  }

  function openSamplesFeed() {
    if (typeof window === 'undefined') return;
    try { samplesWs = new WebSocket('wss://relay.fizx.uk'); } catch { return; }
    const since = Math.floor(Date.now() / 1000) - 86400 * 30;
    samplesWs.onopen = () => {
      samplesWs!.send(JSON.stringify(['REQ', 's-pub', { kinds: [1063], limit: 60, since }]));
      if (pubkey) {
        samplesWs!.send(JSON.stringify(['REQ', 's-mine',    { kinds: [1063], authors: [pubkey], limit: 30 }]));
        samplesWs!.send(JSON.stringify(['REQ', 's-mentions',{ kinds: [1063], '#p': [pubkey],    limit: 30 }]));
      }
    };
    samplesWs.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data as string);
        if (msg[0] !== 'EVENT') return;
        const e = msg[2] as NostrEvent;
        const urlTag = e.tags.find(t => t[0] === 'url');
        const mTag   = e.tags.find(t => t[0] === 'm');
        const altTag = e.tags.find(t => t[0] === 'alt') ?? e.tags.find(t => t[0] === 'title');
        const url  = urlTag?.[1] ?? '';
        const mime = mTag?.[1] ?? '';
        if (!url) return;
        if (mime && !AUDIO_MIME_RE.test(mime)) return;
        if (!mime && !AUDIO_EXT_RE.test(url))  return;
        const title = altTag?.[1] ?? e.content?.trim() ?? url.split('/').pop() ?? 'untitled';
        const taggedHexes = e.tags
          .filter(t => t[0] === 'p' && /^[0-9a-f]{64}$/i.test(t[1] || ''))
          .map(t => t[1].toLowerCase());
        const sample: Sample = {
          id: e.id, pubkey: e.pubkey, created_at: e.created_at, url, title, mime,
          tagged: taggedHexes.length > 0 ? taggedHexes : undefined,
          raw: e,
        };
        if (samples.find(s => s.id === sample.id)) return;
        samples = [...samples, sample];
      } catch {}
    };
  }
</script>

<svelte:head>
  <title>fizx.uk</title>
  <meta name="description" content="Personal web presence of fizx — developer, Bitcoiner, Nostr enthusiast." />
</svelte:head>

<div class="min-h-screen bg-[#0d1117] text-[#f0f6fc] flex flex-col">

  <!-- Nav -->
  <nav class="border-b border-[#1e2d3d] px-6 py-4">
    <div class="max-w-5xl mx-auto flex items-center gap-4">
      <span class="font-mono text-[11px] sm:text-[12px] text-[#6b7a8d]/50 cursor-default shrink-0">fizx</span>
      <div class="flex-1 flex justify-center items-center gap-x-3 text-[11px] sm:text-[12px] font-mono overflow-x-auto">
        {#each [
          ['https://blst.fizx.uk',  'blst'],
          ['https://glmps.fizx.uk', 'glmps'],
          ['https://npub.fizx.uk',  'npub'],
          ['https://pls.fizx.uk',   'pls'],
          ['https://smpl.fizx.uk',  'smpl'],
        ] as [href, label]}
          <a href={href}
             class="text-[#6b7a8d] hover:text-[#34d399] transition-colors whitespace-nowrap">{label}</a>
        {/each}
      </div>
      <a href="https://github.com/adjmx/fizx.uk" target="_blank" rel="noopener noreferrer" title="Source on GitHub" aria-label="Source on GitHub" class="shrink-0 text-[#6b7a8d]/60 hover:text-[#34d399] transition-colors">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.56 0-.28-.01-1.02-.02-2-3.2.69-3.88-1.54-3.88-1.54-.53-1.34-1.29-1.7-1.29-1.7-1.05-.72.08-.71.08-.71 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.71 1.26 3.37.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.7 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.18 1.18.92-.26 1.91-.39 2.89-.39.98 0 1.97.13 2.89.39 2.21-1.49 3.18-1.18 3.18-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.84 1.19 3.1 0 4.43-2.69 5.41-5.25 5.69.41.36.77 1.07.77 2.16 0 1.56-.01 2.82-.01 3.21 0 .31.21.68.8.56 4.56-1.52 7.85-5.83 7.85-10.91C23.5 5.65 18.35.5 12 .5z"/></svg>
      </a>
      <!-- Shaka → nstart.me -->
      <a href="https://nstart.me/en" target="_blank" rel="noopener noreferrer" aria-label="Open nstart.me" class="hover:opacity-75 transition-opacity shrink-0">
        <svg class="h-8 w-auto" fill="url(#fizx-shaka)" viewBox="0 0 210 282">
          <defs>
            <linearGradient id="fizx-shaka" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#f0f9ff" />
              <stop offset="50%" stop-color="#60a5fa" />
              <stop offset="100%" stop-color="#34d399" />
            </linearGradient>
          </defs>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M57.143 98.9848C58.6367 95.1177 62.1322 93.1733 65.8719 92.1713C74.9767 89.7317 81.3757 95.1838 85.1202 100.138C87.0353 102.672 88.5381 105.402 89.6797 107.666C90.3271 108.95 90.784 109.916 91.1512 110.693C91.5296 111.493 91.8127 112.092 92.1107 112.628L92.3791 113.112L92.5365 113.642C92.9678 115.095 93.7096 117.176 94.4929 118.735C94.6234 118.994 94.7454 119.22 94.8568 119.411C96.2962 119.978 97.4576 121.196 97.8887 122.805C98.6106 125.499 97.0117 128.268 94.3176 128.99C90.8191 129.928 88.423 127.512 87.7439 126.76C86.7757 125.688 86.0213 124.371 85.4685 123.271C84.4243 121.194 83.5514 118.773 83.0054 117.015C82.6598 116.345 82.2327 115.455 81.797 114.546C81.4081 113.735 81.0122 112.91 80.6612 112.214C79.6317 110.173 78.4453 108.058 77.0622 106.228C74.2102 102.455 71.5767 101.099 68.4861 101.928C67.2891 102.248 66.763 102.551 66.5602 102.706C66.5455 102.953 66.5618 103.751 67.1654 105.569C67.7276 107.262 68.5363 109.136 69.5419 111.467C69.899 112.294 70.281 113.18 70.6855 114.135C72.1619 117.62 73.7875 121.713 75.0216 126.318C75.7971 129.213 76.5206 132.737 77.2684 136.379C77.6581 138.278 78.0544 140.208 78.468 142.098C79.7244 147.838 81.2286 153.692 83.4154 159.022C87.7563 169.603 94.3593 177.289 106.433 178.342L106.529 178.351L106.625 178.363C109.419 178.714 112.697 177.918 115.701 177.112C118.395 176.391 121.165 177.989 121.887 180.684C122.608 183.378 121.01 186.147 118.316 186.869L118.166 186.909C115.421 187.645 110.401 188.991 105.464 188.396C88.154 186.849 79.1418 175.217 74.0708 162.856C71.5471 156.704 69.8952 150.17 68.6012 144.257C68.1109 142.017 67.6816 139.921 67.2802 137.961C66.5822 134.553 65.9686 131.557 65.2653 128.932C64.212 125.001 62.7989 121.412 61.3851 118.074C61.0692 117.329 60.7434 116.574 60.4177 115.82C59.3548 113.359 58.2928 110.9 57.5795 108.751C56.6874 106.064 55.8077 102.442 57.143 98.9848ZM66.4502 102.814C66.4467 102.813 66.46 102.792 66.5009 102.755C66.4742 102.797 66.4537 102.815 66.4502 102.814Z"/>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M110.765 100.588C105.447 106.291 101.312 115.759 99.3897 122.479C98.6226 125.16 95.8269 126.712 93.1453 125.945C90.4637 125.178 88.9117 122.383 89.6788 119.701C91.8059 112.265 96.5106 101.065 103.377 93.7002C106.832 89.9939 111.303 86.7601 116.731 86.0659C122.387 85.3426 127.938 87.5088 133.082 92.3049L133.115 92.3362L133.148 92.3681C137.351 96.4319 138.339 102.566 138.148 108.032C137.949 113.717 136.446 119.945 134.287 125.595C132.132 131.235 129.187 136.66 125.845 140.636C124.178 142.619 122.255 144.43 120.101 145.672C117.93 146.924 115.206 147.765 112.252 147.16C109.337 146.564 106.744 145.387 104.783 143.392C102.786 141.361 101.852 138.897 101.552 136.487C101 132.048 102.548 127.175 103.955 123.382C106.452 116.654 109.786 109.569 110.805 107.805C112.2 105.389 115.288 104.562 117.704 105.956C120.119 107.351 120.947 110.439 119.552 112.855C118.921 113.948 115.814 120.46 113.425 126.896C111.989 130.765 111.361 133.516 111.576 135.241C111.659 135.914 111.844 136.167 111.986 136.311C112.162 136.491 112.72 136.941 114.239 137.257C114.319 137.249 114.575 137.199 115.057 136.921C115.849 136.465 116.9 135.58 118.113 134.136C120.532 131.258 122.973 126.908 124.852 121.99C126.726 117.084 127.904 111.973 128.054 107.679C128.21 103.204 127.233 100.723 126.154 99.6553C122.606 96.3623 119.932 95.8391 118.012 96.0847C115.858 96.3602 113.401 97.7603 110.765 100.588Z"/>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M148.576 99.5765C147.378 97.8131 145.202 95.6384 142.159 94.4817C138.745 93.1841 134.64 93.342 130.601 96.0088C128.274 97.5456 127.633 100.678 129.17 103.006C130.706 105.333 133.839 105.975 136.167 104.438C136.898 103.955 137.405 103.832 137.696 103.801C137.992 103.769 138.272 103.81 138.57 103.923C139.285 104.195 139.945 104.834 140.233 105.27L140.315 105.394L140.404 105.513C141.425 106.878 142.178 109.533 142.032 113.653C141.891 117.623 140.936 122.239 139.41 126.752C137.884 131.261 135.869 135.427 133.77 138.525C132.722 140.073 131.721 141.252 130.838 142.06C129.92 142.9 129.36 143.128 129.206 143.17C128.698 143.306 128.451 143.278 128.388 143.266C128.367 143.248 128.329 143.21 128.274 143.135C127.88 142.603 127.203 140.925 127.411 137.461C127.578 134.677 125.456 132.285 122.672 132.118C119.888 131.951 117.495 134.072 117.329 136.857C117.058 141.364 117.724 145.861 120.157 149.146C121.436 150.873 123.188 152.225 125.367 152.905C127.514 153.575 129.73 153.486 131.82 152.926C134.105 152.314 136.064 150.968 137.656 149.512C139.282 148.024 140.782 146.184 142.133 144.189C144.835 140.2 147.221 135.181 148.977 129.989C150.733 124.799 151.942 119.195 152.126 114.011C152.302 109.023 151.557 103.642 148.576 99.5765Z"/>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M186.841 91.1686C185.772 91.5973 185.168 92.2069 184.973 92.544C183.264 95.5056 179.325 100.324 175.48 104.794C171.507 109.414 167.22 114.13 164.478 117.072C162.576 119.112 159.38 119.224 157.34 117.322C155.3 115.42 155.188 112.224 157.09 110.184C159.763 107.317 163.956 102.703 167.822 98.2078C171.818 93.5623 175.079 89.4804 176.226 87.4938C177.817 84.7382 180.464 82.8432 183.083 81.7933C185.71 80.7403 188.941 80.2834 192.028 81.1664C195.357 82.1186 198.189 84.5703 199.383 88.482C200.486 92.0952 200.034 96.4116 198.408 101.218C192.231 119.477 179.621 133.86 174.895 138.051C173.698 139.112 172.27 141.273 170.323 145.956C168.418 150.541 166.292 156.814 163.351 165.509C160.041 175.292 152.771 183.982 144.169 188.607C135.418 193.311 124.606 194.032 115.772 186.268C113.677 184.427 113.471 181.236 115.312 179.141C117.153 177.046 120.344 176.84 122.439 178.681C127.282 182.937 133.283 182.991 139.386 179.71C145.636 176.35 151.258 169.738 153.783 162.273L153.849 162.079C156.711 153.619 158.943 147.019 160.996 142.08C163.023 137.203 165.165 133.179 168.193 130.494C171.917 127.192 183.347 114.22 188.84 97.9817C190.131 94.1642 189.957 92.1976 189.722 91.4309C189.582 90.972 189.465 90.9385 189.263 90.8808L189.25 90.8772C188.798 90.7479 187.902 90.7432 186.841 91.1686Z"/>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M87.4391 172.66C90.1332 171.938 92.9024 173.537 93.6243 176.231C94.4031 179.138 94.2478 183.011 93.9724 186.046C93.6772 189.298 93.1456 192.495 92.737 194.492C92.1778 197.225 89.5094 198.987 86.7768 198.427C84.0443 197.868 82.2825 195.2 82.8416 192.467C83.1876 190.777 83.6573 187.954 83.9133 185.133C84.1891 182.095 84.1349 179.841 83.868 178.845C83.1462 176.151 84.745 173.382 87.4391 172.66Z"/>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M137.693 185.612C139.544 187.699 139.352 190.891 137.266 192.742C133.64 195.957 128.811 202.842 126.912 207.176C125.793 209.731 122.814 210.895 120.26 209.775C117.705 208.656 116.541 205.678 117.661 203.123C120.087 197.584 125.741 189.462 130.564 185.184C132.651 183.334 135.843 183.525 137.693 185.612Z"/>
          <path fill-rule="evenodd" clip-rule="evenodd" d="M143.142 106.629C143.189 103.84 145.487 101.617 148.275 101.663C152.563 101.733 158.532 103.631 162.187 109.36C165.863 115.122 166.352 123.427 162.604 134.507C160.305 141.303 157.71 146.407 154.909 150.066C152.117 153.714 148.909 156.189 145.365 157.139C137.608 159.218 131.981 153.53 130.512 148.048C129.79 145.354 131.389 142.585 134.083 141.863C136.777 141.141 139.546 142.74 140.268 145.434C140.76 147.269 141.972 147.592 142.751 147.383C143.476 147.189 144.96 146.446 146.888 143.927C148.807 141.42 150.959 137.41 153.036 131.27C156.29 121.652 155.029 116.919 153.672 114.793C152.294 112.633 149.948 111.792 148.109 111.762C145.32 111.716 143.096 109.418 143.142 106.629Z"/>
        </svg>
      </a>
      <div class="shrink-0 flex justify-end w-[34px] sm:w-[210px]">
        {#if pubkey}
          <button on:click={logout} class="font-mono text-[11px] px-2 py-1 border border-[#34d399]/30 text-[#34d399]/70 hover:text-[#34d399] hover:border-[#34d399]/60 transition-colors flex items-center gap-1.5 w-full justify-center whitespace-nowrap">
            <span class="w-1.5 h-1.5 rounded-full bg-[#34d399] shrink-0"></span>
            <span class="hidden sm:inline">{pubkey.slice(0,8)}…</span>
            <span class="text-[#6b7a8d]/50 ml-0.5">×</span>
          </button>
        {:else}
          <button on:click={login} class="font-mono text-[11px] px-2 py-1 border border-[#1e2d3d] text-[#6b7a8d] hover:text-[#34d399] hover:border-[#34d399]/30 transition-colors flex items-center gap-1.5 w-full justify-center whitespace-nowrap">
            <svg class="h-3 w-3 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><polyline points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
            <span class="hidden sm:inline">Log in with Nostr</span>
          </button>
        {/if}
      </div>
    </div>
  </nav>

  <!-- Main -->
  <main class="flex-1 max-w-5xl mx-auto w-full px-6 py-10">

    <!-- Hero card: full-width bg-card border, title (left) · relay status (middle) · Shaka (right).
         Mirrors the React subdomains' hero card pattern. On narrow widths the
         children wrap (flex-wrap). -->
    <div class="bg-[#131d2a] border border-[#1e2d3d] px-4 py-3 mb-10 min-h-[110px] flex flex-wrap items-start gap-4">
      <h1 class="font-bold tracking-tight shrink-0" style="font-size: clamp(28px, 5vw, 40px)">
        {#each ALL_CHARS as { ch, isAccent }, i (i)}
          <span
            class="inline-block"
            style={isAccent ? 'background: linear-gradient(to right,#60a5fa,#4ade80); -webkit-background-clip: text; background-clip: text; -webkit-text-fill-color: transparent;' : 'color: rgba(74,222,128,0.2);'}
            in:fly={isAccent ? { x: -80, duration: LETTER_DURATION, delay: Math.round(i * LETTER_STAGGER), easing: cubicOut } : { x: 0, duration: 600, delay: Math.round(i * LETTER_STAGGER), easing: cubicOut }}
          >{ch}</span>
        {/each}
      </h1>

      <!-- Relay status text — flex-1, sits between the title and the Shaka inside the hero card -->
      <div class="flex-1 min-w-0 space-y-0.5 font-mono text-[10px] sm:text-[11px] group">

        <!-- Line 1: status · name · version · latency · checked · refresh -->
        <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <a href="https://relay.fizx.uk" class="flex items-center gap-1.5 shrink-0 hover:opacity-80 transition-opacity">
            {#if relayOnline === null}
              <span class="w-1.5 h-1.5 rounded-full bg-[#a78bfa] animate-pulse shrink-0"></span>
            {:else if relayOnline}
              <span class="w-1.5 h-1.5 rounded-full bg-[#34d399] shrink-0" style="box-shadow:0 0 4px rgba(52,211,153,.5)"></span>
            {:else}
              <span class="w-1.5 h-1.5 rounded-full bg-[#f87171] shrink-0"></span>
            {/if}
            <span class="font-bold text-[#34d399]">relay<span class="text-[#6b7a8d]">.fizx.uk</span></span>
          </a>
          {#if nip11Status === 'ok' && relayInfo?.version}
            <span class="text-[#6b7a8d]">v{relayInfo.version}</span>
          {:else if nip11Status === 'loading'}
            <span class="text-[#6b7a8d] animate-pulse">querying…</span>
          {:else if nip11Status !== 'ok'}
            <span class="text-[#f87171]/60">NIP-11 unavailable</span>
          {/if}
          {#if wsLatency !== null}
            <span class="text-[#34d399]/60">{wsLatency}ms</span>
          {/if}
          {#if wsStatus === 'offline'}
            <span class="text-[#f87171]/60">offline</span>
          {/if}
          {#if isGrasp}
            <span class="text-[10px] font-bold tracking-widest px-1 text-[#a78bfa] border border-[#a78bfa]/60" title="NIP-34 git events accepted">GRASP</span>
          {/if}
          {#if lastChecked}
            <span class="text-[9px] text-[#6b7a8d]/40">{lastChecked}</span>
          {/if}
          <button on:click|preventDefault={checkRelay}
            class="text-[#6b7a8d]/60 hover:text-[#34d399] transition-colors"
            title="Refresh relay status">
            {#if wsStatus === 'checking'}
              <span class="w-1.5 h-1.5 rounded-full bg-[#a78bfa] animate-pulse inline-block"></span>
            {:else}
              ↻
            {/if}
          </button>
        </div>

        <!-- Line 2: NIPs · Kinds (numbers only, separator-dotted, flex-wraps if room is tight) -->
        {#if relayInfo && Array.isArray(relayInfo.supported_nips) && relayInfo.supported_nips.length}
          {@const acceptedKinds = KIND_MAP.filter(k => supportedNips.includes(k.nip))}
          <div class="flex flex-wrap items-baseline gap-x-1 gap-y-0.5 text-[10px] leading-tight mt-0.5">
            <span class="text-[#a78bfa]/70 font-bold uppercase tracking-widest text-[9px] mr-0.5">NIPs</span>
            {#each (relayInfo.supported_nips as number[]).slice().sort((a,b)=>a-b) as nip, i}
              {#if i > 0}<span class="text-[#6b7a8d]/30">·</span>{/if}
              <a href={`https://github.com/nostr-protocol/nips/blob/master/${String(nip).padStart(2,'0')}.md`}
                 target="_blank" rel="noopener noreferrer"
                 class="text-[#a78bfa]/80 hover:text-[#a78bfa] tabular-nums transition-colors"
                 title={`NIP-${nip}`}>{nip}</a>
            {/each}
            {#if acceptedKinds.length}
              <span class="text-[#fbbf24]/70 font-bold uppercase tracking-widest text-[9px] ml-2 mr-0.5">Kinds</span>
              {#each acceptedKinds as { kind, label, nip }, i}
                {#if i > 0}<span class="text-[#6b7a8d]/30">·</span>{/if}
                <span title={`${label} · NIP-${nip}`} class="text-[#fbbf24]/80 tabular-nums">{kind}</span>
              {/each}
            {/if}
          </div>
        {/if}

        </div>
        <!-- /flex-1 text content -->

    </div>
    <!-- /hero card -->

    <!-- Standalone relay status section — REMOVED 2026-05-17.
         Relay card now lives inline in the hero row (between title and Shaka). -->


    <!-- Vibe Projects grid — REMOVED 2026-05-17 (links live in the top nav).
         `vibeProjects` array above is kept intact for potential future
         reintroduction (icons, descriptions, colors). To revive: drop a
         <section> here that iterates over it. -->


    <!-- Recent smpl samples (live feed from relay.fizx.uk) -->
    <section class="mb-14">
      <div class="flex items-baseline justify-between mb-3">
        <h2 class="text-[10px] font-mono uppercase tracking-widest text-[#6b7a8d]">recent samples</h2>
        <a href="https://smpl.fizx.uk" class="text-[10px] font-mono text-[#6b7a8d]/60 hover:text-[#34d399] transition-colors">smpl.fizx.uk →</a>
      </div>
      {#if visibleSamples.length === 0}
        <p class="text-[11px] font-mono text-[#6b7a8d]/50 px-3 py-4 border border-[#1e2d3d] bg-[#131d2a]/40">
          No samples yet — be the first to <a href="https://smpl.fizx.uk" class="text-[#34d399] hover:underline">publish one</a>.
        </p>
      {:else}
        <!-- Tight chip grid — 3 columns on md+, 2 on sm, 1 on default.
             Each chip: tiny play, truncated title (full revealed via native
             tooltip), optional you/@/·N badges, tiny republish.
             Time + author + tagged count live in the hover tooltip; the
             visible chip stays at ~22-24px tall to fit ~18 samples in the
             same vertical space that previously held 8. -->
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-1 border border-[#1e2d3d] bg-[#131d2a]/40 p-1">
          {#each visibleSamples as s (s.id)}
            {@const rep = republishStatus[s.id] ?? 'idle'}
            {@const tip = `${s.title}\n${relTime(s.created_at)} · ${s.pubkey.slice(0,8)}…${s.tagged && s.tagged.length > 0 ? ` · ${s.tagged.length} tagged` : ''}`}
            <div class="flex items-center gap-1.5 px-1.5 py-1 min-w-0 hover:bg-[#1e2d3d]/40 transition-colors group">
              <button on:click={() => togglePlay(s)} aria-label={playingId === s.id ? 'pause' : 'play'}
                class="shrink-0 w-5 h-5 rounded-full border border-[#1e2d3d] hover:border-[#34d399] text-[#6b7a8d] hover:text-[#34d399] transition-colors flex items-center justify-center">
                {#if playingId === s.id}
                  <svg width="7" height="7" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>
                {:else}
                  <svg width="7" height="7" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
                {/if}
              </button>
              <a href="https://smpl.fizx.uk" target="_blank" rel="noopener noreferrer" title={tip}
                 class="flex-1 min-w-0 font-mono text-[10px] text-[#e6edf3]/90 hover:text-[#34d399] transition-colors truncate">{s.title}</a>
              {#if s.priority === 0}
                <span class="shrink-0 text-[8px] font-mono uppercase tracking-widest px-1 leading-3 py-0.5 border border-[#34d399]/40 text-[#34d399]/80" title="Your sample">you</span>
              {:else if s.priority === 1}
                <span class="shrink-0 text-[9px] font-mono leading-3 px-1 py-0.5 border border-[#a78bfa]/40 text-[#a78bfa]/80" title="Mentions you">@</span>
              {/if}
              {#if s.tagged && s.tagged.length > 0}
                <span class="shrink-0 text-[9px] font-mono text-[#a78bfa]/60" title={`${s.tagged.length} tagged`}>·{s.tagged.length}</span>
              {/if}
              <button on:click={() => republishToRelay(s)} disabled={rep === 'sending'}
                title={rep === 'ok' ? `Republished ✓ (${relTime(s.created_at)})`
                     : rep === 'err' ? 'Republish failed ✗'
                     : `Republish to wss://relay.fizx.uk · ${relTime(s.created_at)}`}
                aria-label="Republish to relay.fizx.uk"
                class="shrink-0 w-4 h-4 flex items-center justify-center border transition-colors
                  {rep === 'ok'      ? 'border-[#34d399]/60 text-[#34d399]' :
                   rep === 'err'     ? 'border-[#f87171]/60 text-[#f87171]' :
                   rep === 'sending' ? 'border-[#a78bfa]/60 text-[#a78bfa] animate-pulse' :
                                       'border-[#1e2d3d] text-[#6b7a8d]/50 hover:border-[#34d399]/40 hover:text-[#34d399]'}">
                {#if rep === 'ok'}
                  <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><polyline points="20 6 9 17 4 12"/></svg>
                {:else if rep === 'err'}
                  <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></svg>
                {:else}
                  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 19V5"/><path d="M5 12l7-7 7 7"/>
                  </svg>
                {/if}
              </button>
            </div>
          {/each}
        </div>
      {/if}
      <audio bind:this={audioEl} on:ended={() => playingId = null} on:error={() => playingId = null} preload="none" crossorigin="anonymous"></audio>
    </section>

    <!-- Vibe Docs grid — REMOVED 2026-05-17.
         folio + scripts deleted; ln + recipes moved to footer chips. -->


    <!-- Identity section ('Find me on' + GitHub/Nostr/relay cards) — REMOVED 2026-05-17.
         relay link moved to the footer chips alongside ln + recipes. -->

  </main>

  <!-- Footer -->
  <footer class="border-t border-[#1e2d3d] px-6 py-4">
    <div class="max-w-5xl mx-auto flex flex-wrap items-center justify-between gap-x-4 gap-y-2 text-xs font-mono">
      <div class="flex items-center gap-4">
        {#each footerLinks as l}
          <a href={l.href} class="flex items-center gap-1.5 text-[#6b7a8d]/70 hover:text-[#34d399] transition-colors">
            <span class="shrink-0 inline-flex">{@html l.icon}</span>
            <span>{l.label}<span class="text-[#6b7a8d]/40">.fizx.uk</span></span>
          </a>
        {/each}
      </div>
      <span class="text-[#34d399]/60">✦ built with svelte</span>
    </div>
  </footer>

</div>

<style>
  .hover-emerald:hover {
    border-color: rgb(52 211 153 / 0.4);
  }
  .hover-purple:hover {
    border-color: rgb(167 139 250 / 0.4);
  }
</style>
