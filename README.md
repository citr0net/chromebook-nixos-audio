<h1 align="center">chromebook-nixos-audio</h1>
<p align="center">
  A NixOS module for enabling audio support on Chromebooks running NixOS.<br>
  Forked from <a href="https://github.com/WeirdTreeThing/chromebook-linux-audio">WeirdTreeThing/chromebook-linux-audio</a> — adapted specifically for NixOS.
</p>

---

> [!INFO]
> This was vibecoded by Claude Sonnet 4.6, but it works surprisingly well

## Overview

This repository provides a self-contained NixOS module (`chromebook-audio.nix`) that wires up Chromebook audio hardware on a full NixOS installation. It handles:

- Kernel DSP driver selection (SST / AVS / SOF) based on your platform
- Firmware blob installation for Intel Alderlake, Meteorlake, and AMD Mendocino
- ChromeOS UCM (Use-Case Manager) profiles so ALSA and WirePlumber see your sound card correctly
- A WirePlumber headroom fix that prevents audio crashes on many devices
- ALSA sound card state initialisation on boot via a systemd service

> **Note:** A full NixOS install is required. Live USB sessions will not work.

---

## Supported Platforms

| Code  | Platform                              |
|-------|---------------------------------------|
| `bdw` | Intel Broadwell (samus, buddy)        |
| `byt` | Intel Baytrail                        |
| `bsw` | Intel Braswell                        |
| `skl` | Intel Skylake                         |
| `kbl` | Intel Kabylake                        |
| `apl` | Intel Apollolake                      |
| `glk` | Intel Geminilake                      |
| `cml` | Intel Cometlake                       |
| `jsl` | Intel Jasperlake                      |
| `tgl` | Intel Tigerlake                       |
| `adl` | Intel Alderlake / Alderlake-N (Raptorlake) |
| `mtl` | Intel Meteorlake                      |
| `st`  | AMD StoneyRidge *(kernel ≥ 6.19 required)* |
| `pco` | AMD Picasso/Dali                      |
| `czn` | AMD Cezanne                           |
| `mdn` | AMD Mendocino                         |

Not sure which platform your Chromebook uses? Check the [Chrultrabook docs](https://docs.chrultrabook.com/docs/devices.html).

---

## Quick Start

**1. Copy `chromebook-audio.nix` into your NixOS config directory**

```bash
cp chromebook-audio.nix /etc/nixos/chromebook-audio.nix
```

**2. Add the module to your `configuration.nix`**

```nix
imports = [
  ./chromebook-audio.nix
];

hardware.chromebook-audio = {
  enable   = true;
  platform = "adl";   # ← replace with your platform code from the table above

  # Pin the upstream firmware source to a specific commit for reproducibility.
  # Set audioSrcRevision to a commit SHA, then run `nixos-rebuild` with the
  # placeholder hash below — Nix will error and print the correct hash.
  audioSrcRevision = "main";            # replace with a commit SHA
  audioSrcHash     = lib.fakeHash;      # replace after first build failure

  ucmRevision = "standalone";           # replace with a commit SHA
  ucmHash     = lib.fakeHash;           # replace after first build failure
};
```

**3. Rebuild**

```bash
sudo nixos-rebuild switch
```

**4. Reboot** and test your audio.

---

## All Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | `false` | Enable the module. |
| `platform` | `enum` | — | **Required.** Your Chromebook's platform code (see table above). |
| `atomDriver` | `"sst"` \| `"sof"` | `"sst"` | For Baytrail/Braswell/Broadwell devices only. Try `"sst"` first; fall back to `"sof"` if it does not work. |
| `forceSOFDriver` | `bool` | `false` | Force-enable the SOF driver via modprobe. Needed on some HP devices where `sys_vendor` is not `"Google"`. |
| `enableAVSSpeakers` | `bool` | `false` | Enable speaker output on AVS (Skylake/Kabylake/Apollolake) devices with a `max98357a` amplifier. **⚠ Keep volume below 50% — high volume can permanently damage speakers.** |
| `increaseAlsaHeadroom` | `bool` | `true` | Sets `api.alsa.headroom = 2048` in WirePlumber, fixing instability and crashes on many devices. |
| `audioSrcRevision` | `str` | `"main"` | Git revision of [chromebook-linux-audio](https://github.com/WeirdTreeThing/chromebook-linux-audio) to fetch firmware blobs from. Pin to a commit SHA for reproducibility. |
| `audioSrcHash` | `str` | `lib.fakeHash` | SRI hash of the firmware repo at the chosen revision. Run with `lib.fakeHash` first; Nix will print the correct hash in the error message. |
| `ucmRevision` | `str` | `"standalone"` | Git revision of [alsa-ucm-conf-cros](https://github.com/WeirdTreeThing/alsa-ucm-conf-cros) to use. |
| `ucmHash` | `str` | `lib.fakeHash` | SRI hash of the UCM repo at the chosen revision. |

---

## How It Works

### Driver selection

The module automatically selects the correct kernel DSP driver based on your platform:

- **SST** — used for Broadwell, Baytrail, and Braswell (unless `atomDriver = "sof"`)
- **AVS** — used for Skylake, Kabylake, and Apollolake
- **SOF** — used for all other platforms (Geminilake, Cometlake, Tigerlake, Alderlake, Meteorlake, and all AMD platforms)

Driver options are written to `boot.extraModprobeConfig`.

### Firmware blobs

For platforms that need firmware files not present in the standard Linux firmware tree, the module fetches them from the upstream [chromebook-linux-audio](https://github.com/WeirdTreeThing/chromebook-linux-audio) repository and installs them into `/lib/firmware` via `hardware.firmware`:

- **ADL (Alderlake)** — `sof-adl-rt1019-rt5682.tplg` plus RPL symlinks and a `cs42l42` alias
- **MTL (Meteorlake)** — `sof-mtl-rt5650.tplg` and `sof-mtl-rt1019-rt5682.tplg`
- **MDN (Mendocino)** — `sof-rmb.ldc`, `sof-rmb.ri`, and `sof-rmb-rt5682s-rt1019.tplg`

### UCM profiles

ChromeOS UCM profiles are written to `/etc/alsa/ucm2` directly, without touching `alsa-ucm-conf` or `alsa-lib`. This avoids triggering a full system rebuild, since `alsa-lib` contains a hardcoded symlink into `alsa-ucm-conf`'s store path.

### Boot-time ALSA init

A `systemd` oneshot service (`chromebook-alsactl-init`) runs `alsactl init` after `sound.target` to restore sound card state on every boot.

---

## Included Files

```
chromebook-audio.nix          # NixOS module — the main file
blobs/
  adl/
    sof-adl-rt1019-rt5682.tplg      # Alderlake topology (downstream patch)
  mtl/
    sof-mtl-rt1019-rt5682.tplg      # Meteorlake topology
    sof-mtl-rt5650.tplg             # Meteorlake topology (rt5650 codec)
  mdn/
    fw/
      sof-rmb.ldc                   # Mendocino firmware
      sof-rmb.ri                    # Mendocino firmware image
    tplg/
      sof-rmb-rt5682s-rt1019.tplg   # Mendocino topology
```

---

## Troubleshooting

**No audio after reboot**
Run `alsactl init` manually and check `journalctl -u chromebook-alsactl-init` for errors.

**Build fails with a hash mismatch**
Set `audioSrcRevision` (or `ucmRevision`) to a pinned commit SHA, leave the corresponding hash as `lib.fakeHash`, rebuild, and copy the correct hash from the Nix error output.

**Baytrail/Braswell/Broadwell device — no audio**
Try switching `atomDriver` from `"sst"` to `"sof"`.

**HP device where audio is not detected**
Set `forceSOFDriver = true`.

**AVS device — speakers silent**
Set `enableAVSSpeakers = true`. **Keep the system volume below 50%** until a proper software limiter is in place — excessive volume can permanently damage the speakers.

**AMD StoneyRidge (`st`) not working**
This platform requires kernel 6.19 or newer. Add `boot.kernelPackages = pkgs.linuxPackages_6_19;` (or a newer package set) to your config.

---

## Credits

- [WeirdTreeThing](https://github.com/WeirdTreeThing/chromebook-linux-audio) — upstream `chromebook-linux-audio` project and firmware blobs
- [Chrultrabook project](https://docs.chrultrabook.com) — device documentation and community support
- [citr0net](https://github.com/citr0net/chromebook-nixos-audio) — NixOS module adaptation

---

## License

This project follows the licensing of the upstream [chromebook-linux-audio](https://github.com/WeirdTreeThing/chromebook-linux-audio) repository. Please refer to that project for full license details.
