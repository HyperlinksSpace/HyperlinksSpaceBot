# Program Kit

Program Kit is a production-ready cross-platform starter published from repository root.
It is built around React Native + Expo and is designed to be quickly tested, scaled,
and deployed across popular platforms.

## What You Get

- Expo + React Native app foundation
- Telegram bot support (webhook + local bot scripts) with AI functionality
- Telegram Mini App-ready client structure
- Android and iOS clients
- Windows desktop packaging (`.exe`) with Electron Builder
- CI-oriented release workflow and deployment helpers
- OpenAI functionality and Swap.Coffee for blockchain data retrievement

## Install

### npmjs (public)

```bash
npx @www.hyperlinks.space/program-kit ./new-program
```

### GitHub Packages

```bash
npx @hyperlinksspace/program-kit ./new-program
```

If you install from GitHub Packages, configure `.npmrc` with the `@hyperlinksspace`
registry and token.

## After Scaffold

Copy `npmrc.example` to `.npmrc` so installs match this repo (`legacy-peer-deps`; npm does not ship a real `.npmrc` in the tarball for security):

```bash
cd new-program
cp npmrc.example .npmrc
npm install
npm run start
```

If you prefer not to use a `.npmrc`, you can run **`npm install --legacy-peer-deps`** instead of the copy step.

Then open the project **`fullREADME.md`** for details (env vars, bot setup, build
and release commands).

## Release Channels

- `latest` for stable milestone snapshots
- `next` for rolling preview snapshots

## Notes

- Published from the repository root; the pack includes everything except patterns in [`.npmignore`](./.npmignore) (no `files` whitelist in `package.json`).
- `.npmrc` cannot be published on npm; `npmrc.example` is included so you can copy it locally.
