# Vendored Rend community assets

These files are sourced from the Rend community's [Nanoware/RendRevival](https://github.com/Nanoware/RendRevival) and the Last Hope community (Discord: https://discord.gg/gUJyZEXxyq), with particular credit to Farlier for the index-server reverse-engineering and DLL customization.

- `PhysX3Cooking_x64.dll` — the `dll-configurable-index-server-url` edition. Overlaid at `Engine/Binaries/ThirdParty/PhysX3/Win64/VS2015/` when `REND_MODE=modded`. Reads its index/auth endpoints from `Authentication.ini`. Requires `-NoEAC`.
- `config/` — default gameplay config (`config.ini`, `Game.ini`, `Server.ini`, `Engine.ini`) derived from RendRevival `config/vanilla-last-hope/`, plus an `Authentication.ini` endpoint template.

Update these by re-vendoring from RendRevival; the image bakes the DLL as its last layer so a DLL refresh rebuilds only that layer.
