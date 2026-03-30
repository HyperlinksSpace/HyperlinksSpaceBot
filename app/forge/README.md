# Electron Forge (Windows)

This folder contains an Electron Forge config that packages your existing Electron main process:

- `./windows/build.cjs`

## Build

From `app/`, run:

```bash
npm run make:win:forge
```

This will:
1. Build the Expo web `dist/`
2. Run `electron-forge make` with the stock Windows NSIS maker.

## Notes

Your current `electron-builder` pipeline includes custom NSIS hook files (for installer UI/log mirroring).
Electron Forge's stock NSIS maker does not replicate that custom behavior automatically.

## Updater Metadata Policy

This project intentionally uses pipeline-specific updater metadata names for Forge releases:

- `latest_forge.yml`
- `zip-latest_forge.yml`

Why:
1. Prevents accidental cross-consumption between `electron-builder` and Forge release assets.
2. Makes dual-pipeline operation deterministic when both release lines coexist.
3. Allows CI to enforce explicit contracts per pipeline.

CI preflight checks in the Forge release workflow enforce this naming policy before publishing.

