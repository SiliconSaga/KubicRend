# KubicRend: Wine + SteamCMD image with the Rend server baked in.
# amd64 only (Wine/Steam are x86). Game is a dead title — bake for determinism.
#
# Base: scottyhardy/docker-wine (wine-stable + Xvfb + winetricks + xauth, and an
# entrypoint that provisions the non-root `wineuser` (uid 1010) and its Wine
# prefix AT RUNTIME, then execs CMD). The Rend Wine boot spike proved this base
# runs the UE4 server headless to Match-State InProgress. A leaner self-owned
# WineHQ base is a follow-up hardening; this proven base is what boots today.
#
# `wineuser` does not exist in the image's passwd file at build time (the base
# entrypoint creates it on start), so ALL build steps run as root and hand
# ownership of the baked dirs to uid 1010 at the end.
FROM scottyhardy/docker-wine:latest

USER root

# SteamCMD is a native Linux binary (no Wine needed to run it); needs curl/tar.
# iproute2 -> ss (port checks); procps -> ps (diagnostics).
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates tar iproute2 procps \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/steamcmd /opt/rend /opt/rend-dll /data

RUN curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
      | tar zxvf - -C /opt/steamcmd

# --- Bake the Rend server (Windows depot) at build time --------------------
# Warm up steamcmd first: on a fresh client it self-updates and RESTARTS mid-run,
# which drops the ForcePlatformType flag and yields "Missing configuration" for the
# Windows depot. The warmup absorbs that restart so the real pull runs on an
# already-updated client where the platform flag persists.
RUN /opt/steamcmd/steamcmd.sh +login anonymous +quit ; \
    /opt/steamcmd/steamcmd.sh \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir /opt/rend \
      +login anonymous \
      +app_update 550790 validate \
      +quit \
 && test -f /opt/rend/Otherlands/Binaries/Win64/OtherlandsServer-Win64-Shipping.exe

# --- DLL layer (LAST — refreshes without rebuilding the game layers) --------
# Back up the stock DLL for vanilla mode; stage the modified DLL for modded mode.
RUN cp /opt/rend/Engine/Binaries/ThirdParty/PhysX3/Win64/VS2015/PhysX3Cooking_x64.dll \
       /opt/rend-dll/PhysX3Cooking_x64.stock.dll
COPY vendor/PhysX3Cooking_x64.dll /opt/rend-dll/PhysX3Cooking_x64.dll
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Hand ownership of the baked game + steam dirs to the runtime user (uid 1010).
RUN chown -R 1010:1010 /opt/steamcmd /opt/rend /opt/rend-dll /data

# OPENSSL_ia32cap masks a CPU-feature bit that the game's bundled OpenSSL 1.0.2h
# mis-handles on recent Intel CPUs (validated on an i7-14700F): without it the
# server SEH-crashes under Wine the instant it does TLS to the index server
# (LogServerGatekeeper registration). Same ~0x20000000 workaround the Rend
# client community uses for the Intel-only startup crash. With it, the server
# completes the registration TLS round-trip and stays up (Loki, 2026-09-10).
ENV REND_MODE=modded \
    REND_DIR=/opt/rend \
    OPENSSL_ia32cap="~0x20000000"
# Keep the base ENTRYPOINT (provisions wineuser + prefix, then execs CMD).
# Our launcher is the CMD, so it runs inside that provisioned environment.
CMD ["/usr/local/bin/entrypoint.sh"]
