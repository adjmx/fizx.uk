# fizx.uk

> Personal hub — relay status, vibe projects, recent smpl samples, Nostr login.

**Live**: <https://fizx.uk>

## Stack

- [SvelteKit](https://svelte.dev/) + Svelte 5 + TypeScript
- [@sveltejs/adapter-static](https://kit.svelte.dev/docs/adapter-static)
- Tailwind CSS

## Nostr

- **Login**: NIP-07 (browser extension) + NIP-55 (Amber callback URI)
- `kind:1063` — NIP-94 file metadata — subscription for the recent samples panel (own / mentions / public, prioritized)

NostrLogin (NIP-07 + NIP-55). NIP-11 + WebSocket probe of `wss://relay.fizx.uk` for the status card.

## Develop

```bash
npm install
npm run dev
```

## Build + deploy

```bash
npm run build   # → build/
rsync -avz --delete -e "ssh -p 2121" build/ root@88.218.206.187:/var/www/fizx.uk/
```

VPS: `88.218.206.187`. Full server / nginx / SSL / DNS notes for the wider deployment live in the local `code_gh/adjmx/CLAUDE.md` (not pushed; this README is the public-facing summary).
