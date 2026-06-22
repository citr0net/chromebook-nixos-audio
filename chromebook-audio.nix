# chromebook-audio.nix
#
# NixOS module for chromebook-linux-audio
# Based on https://github.com/WeirdTreeThing/chromebook-linux-audio
#
# Usage — add to your configuration.nix imports and enable:
#
#   imports = [ ./chromebook-audio.nix ];
#   hardware.chromebook-audio.enable = true;
#   hardware.chromebook-audio.platform = "adl"; # set your platform (see below)
#
# Platforms:
#   bdw  - Intel Broadwell    (samus, buddy)
#   byt  - Intel Baytrail
#   bsw  - Intel Braswell
#   skl  - Intel Skylake
#   kbl  - Intel Kabylake
#   apl  - Intel Apollolake
#   glk  - Intel Geminilake
#   cml  - Intel Cometlake
#   jsl  - Intel Jasperlake
#   tgl  - Intel Tigerlake
#   adl  - Intel Alderlake / Alderlake-N (Raptorlake)
#   mtl  - Intel Meteorlake
#   st   - AMD StoneyRidge     (requires kernel >= 6.19)
#   pco  - AMD Picasso/Dali
#   czn  - AMD Cezanne
#   mdn  - AMD Mendocino

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.chromebook-audio;

  # ---------------------------------------------------------------------------
  # Firmware blobs fetched from upstream (pinned)
  # ---------------------------------------------------------------------------
  chromebookAudioSrc = pkgs.fetchFromGitHub {
    owner = "WeirdTreeThing";
    repo  = "chromebook-linux-audio";
    rev   = cfg.audioSrcRevision;
    hash  = cfg.audioSrcHash;
  };

  blobsDir = "${chromebookAudioSrc}/blobs";

  # ---------------------------------------------------------------------------
  # UCM configuration source
  # ---------------------------------------------------------------------------
  ucmConf = pkgs.fetchFromGitHub {
    owner = "WeirdTreeThing";
    repo  = "alsa-ucm-conf-cros";
    rev   = cfg.ucmRevision;
    hash  = cfg.ucmHash;
  };

  # Build a plain store path containing just the ucm2 tree.
  # We do NOT touch alsa-ucm-conf or alsa-lib — that caused a full system
  # rebuild because alsa-lib has a hardcoded symlink into alsa-ucm-conf's
  # store path, which breaks when the hash changes.
  crosUcm2 = pkgs.runCommand "chromebook-cros-ucm2" {} ''
    cp -r ${ucmConf}/ucm2 $out
  '';

  # ---------------------------------------------------------------------------
  # Driver selection helpers
  # ---------------------------------------------------------------------------
  isSST = cfg.platform == "bdw" || cfg.platform == "byt" || cfg.platform == "bsw";
  isAVS = cfg.platform == "skl" || cfg.platform == "kbl" || cfg.platform == "apl";
  isSOF = !(isSST || isAVS);

  atomDriverIsSOF = cfg.atomDriver == "sof";
  forceSOFDriver  = cfg.forceSOFDriver;

  # ---------------------------------------------------------------------------
  # kernel.extraModprobeConfig snippets
  # ---------------------------------------------------------------------------
  avsConf   = "options snd-intel-dspcfg dsp_driver=4\noptions snd-soc-avs ignore_fw_version=1\noptions snd-soc-avs obsolete_card_names=1\n";
  sstConf   = "options snd_intel_dspcfg dsp_driver=2\n";
  sofConf   = "options snd-intel-dspcfg dsp_driver=3\n";
  hifi2Conf = "options snd_sof sof_debug=1\noptions snd_intel_dspcfg dsp_driver=3\n";

  modprobeConfig =
    if isAVS then avsConf
    else if isSST then (if atomDriverIsSOF then hifi2Conf else sstConf)
    else if cfg.platform == "mtl" then sofConf
    else if forceSOFDriver then sofConf
    else sofConf; # default SOF for all other platforms (adl, tgl, glk, etc.)

  # ---------------------------------------------------------------------------
  # Firmware derivations — only built for platforms that need blobs
  # ---------------------------------------------------------------------------
  mdnFirmware = pkgs.runCommand "chromebook-mdn-firmware" {} ''
    install -Dm644 ${blobsDir}/mdn/fw/sof-rmb.ldc  $out/lib/firmware/amd/sof/community/sof-rmb.ldc
    install -Dm644 ${blobsDir}/mdn/fw/sof-rmb.ri   $out/lib/firmware/amd/sof/community/sof-rmb.ri
    install -Dm644 ${blobsDir}/mdn/tplg/sof-rmb-rt5682s-rt1019.tplg \
                                                    $out/lib/firmware/amd/sof-tplg/sof-rmb-rt5682s-rt1019.tplg
  '';

  adlFirmware = pkgs.runCommand "chromebook-adl-firmware" { nativeBuildInputs = [ pkgs.xz pkgs.zstd ]; } ''
    tplgDir=$out/lib/firmware/intel/sof-tplg
    mkdir -p "$tplgDir"

    # Downstream rt1019-rt5682 topology (upstream is broken)
    cp "${blobsDir}/adl/sof-adl-rt1019-rt5682.tplg" "$tplgDir/sof-adl-rt1019-rt5682.tplg"

    # RPL symlinks — RPL devices load tplg with rpl- prefix
    for name in cs35l41 max98357a-rt5682-4ch max98357a-rt5682 max98360a-cs42l42 \
                max98360a-da7219 max98360a-nau8825 max98360a-rt5682-2way \
                max98360a-rt5682-4ch max98360a-rt5682 max98373-nau8825 \
                max98390-rt5682 max98390-ssp2-rt5682-ssp0 nau8825 rt1019-nau8825 \
                rt1019-rt5682 rt5682 rt711 sdw-max98373-rt5682; do
      for ext in .tplg .tplg.xz .tplg.zst; do
        adl="$tplgDir/sof-adl-$name$ext"
        rpl="$tplgDir/sof-rpl-$name$ext"
        if [ -e "$adl" ]; then
          ln -sf "sof-adl-$name$ext" "$rpl"
        fi
      done
    done

    # cs42l42 alias
    for ext in .tplg .tplg.xz .tplg.zst; do
      src="$tplgDir/sof-adl-max98360a-rt5682$ext"
      if [ -e "$src" ]; then
        ln -sf "sof-adl-max98360a-rt5682$ext" "$tplgDir/sof-adl-max98360a-cs42l42$ext"
      fi
    done
  '';

  mtlFirmware = pkgs.runCommand "chromebook-mtl-firmware" {} ''
    tplgDir=$out/lib/firmware/intel/sof-ace-tplg
    mkdir -p "$tplgDir"
    cp "${blobsDir}/mtl/sof-mtl-rt5650.tplg"        "$tplgDir/sof-mtl-rt5650.tplg"
    cp "${blobsDir}/mtl/sof-mtl-rt1019-rt5682.tplg" "$tplgDir/sof-mtl-rt1019-rt5682.tplg"
  '';

  extraFirmwarePackages =
    optional (cfg.platform == "mdn") mdnFirmware
    ++ optional (cfg.platform == "adl") adlFirmware
    ++ optional (cfg.platform == "mtl") mtlFirmware;

  # ---------------------------------------------------------------------------
  # AVS: zero-byte max98357a topology to protect speakers by default
  # ---------------------------------------------------------------------------
  avsTopologyPatch = pkgs.runCommand "chromebook-avs-topo-patch" {} ''
    mkdir -p $out/lib/firmware/intel/avs
    touch $out/lib/firmware/intel/avs/max98357a-tplg.bin
  '';

in {
  # ---------------------------------------------------------------------------
  # Option declarations
  # ---------------------------------------------------------------------------
  options.hardware.chromebook-audio = {
    enable = mkEnableOption "Chromebook Linux audio support";

    platform = mkOption {
      type    = types.enum [ "bdw" "byt" "bsw" "skl" "kbl" "apl" "glk" "cml" "jsl" "tgl" "adl" "mtl" "st" "pco" "czn" "mdn" ];
      default = null;
      example = "adl";
      description = ''
        Intel/AMD platform code for your Chromebook.
        Check the Chrultrabook docs or the comments at the top of this file.
      '';
    };

    atomDriver = mkOption {
      type    = types.enum [ "sst" "sof" ];
      default = "sst";
      description = ''
        For Baytrail / Braswell / Broadwell (bdw/byt/bsw) platforms, choose
        between the SST and SOF drivers. Try "sst" first; if it does not work,
        switch to "sof".
      '';
    };

    forceSOFDriver = mkOption {
      type    = types.bool;
      default = false;
      description = ''
        Force-enable the SOF driver via modprobe. Required on some HP devices
        where sys_vendor is not "Google".
      '';
    };

    enableAVSSpeakers = mkOption {
      type    = types.bool;
      default = false;
      description = ''
        On AVS (Skylake/Kabylake/Apollolake) devices with a max98357a amplifier,
        enable speaker output. WARNING: can permanently damage speakers if volume
        is too high. Keep volume below 50% until a proper limiter is in place.
      '';
    };

    increaseAlsaHeadroom = mkOption {
      type    = types.bool;
      default = true;
      description = ''
        Set api.alsa.headroom = 2048 in WirePlumber. Fixes instability and
        crashes on various devices.
      '';
    };

    audioSrcRevision = mkOption {
      type    = types.str;
      default = "main";
      description = ''
        Git revision of github.com/WeirdTreeThing/chromebook-linux-audio to use
        for firmware blobs. Pin to a commit SHA for reproducibility.
        When changing this you MUST also update audioSrcHash.
      '';
    };

    audioSrcHash = mkOption {
      type    = types.str;
      default = lib.fakeHash;
      description = ''
        SRI hash of the chromebook-linux-audio repo at the chosen revision.
        Run nix build with the wrong/fake hash to get the correct one from the error.
      '';
    };

    ucmRevision = mkOption {
      type    = types.str;
      default = "standalone";
      description = ''
        Git revision (branch, tag, or commit SHA) of
        github.com/WeirdTreeThing/alsa-ucm-conf-cros to use.
        When changing this you MUST also update ucmHash.
      '';
    };

    ucmHash = mkOption {
      type    = types.str;
      default = lib.fakeHash;
      description = ''
        SRI hash of the UCM repository at the chosen revision.
        Run nix build with the wrong/fake hash to get the correct one from the error.
      '';
    };
  };

  # ---------------------------------------------------------------------------
  # Implementation
  # ---------------------------------------------------------------------------
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.platform != null;
        message   = "hardware.chromebook-audio.platform must be set.";
      }
      {
        assertion = cfg.platform != "st";
        message   = ''
          AMD StoneyRidge (st) requires kernel >= 6.19.
          Use boot.kernelPackages = pkgs.linuxPackages_6_19 or newer,
          then set hardware.chromebook-audio.platform = "st".
        '';
      }
    ];

    # --- kernel modprobe options -------------------------------------------
    boot.extraModprobeConfig = modprobeConfig;

    # --- firmware blobs ----------------------------------------------------
    hardware.firmware = extraFirmwarePackages
      ++ optional (isAVS && !cfg.enableAVSSpeakers) avsTopologyPatch;

    # --- sof-firmware for SOF platforms ------------------------------------
    hardware.enableAllFirmware = mkDefault isSOF;

    # --- WirePlumber headroom fix ------------------------------------------
    services.pipewire.wireplumber.configPackages = mkIf cfg.increaseAlsaHeadroom [
      (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-increase-headroom.conf" ''
        monitor.alsa.rules = [
          {
            matches = [
              {
                node.name = "~alsa_output.*"
              }
            ]
            actions = {
              update-props = {
                api.alsa.headroom = 2048
              }
            }
          }
        ]
      '')
    ];

    # --- Initialise the sound card on boot ---------------------------------
    systemd.services.chromebook-alsactl-init = {
      description = "Initialise Chromebook ALSA sound card state";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "sound.target" ];
      serviceConfig = {
        Type             = "oneshot";
        ExecStart        = "${pkgs.alsa-utils}/bin/alsactl init";
        SuccessExitStatus = [ 0 99 ];
      };
    };

    # --- ChromeOS UCM profiles ---------------------------------------------
    # Written directly to /etc/alsa/ucm2 so ALSA and WirePlumber find them
    # without touching alsa-ucm-conf or alsa-lib (which would trigger a full
    # system rebuild due to alsa-lib's hardcoded symlink into alsa-ucm-conf).
    environment.etc."alsa/ucm2".source = crosUcm2;

    # --- Required packages -------------------------------------------------
    environment.systemPackages = [ pkgs.alsa-utils ];
  };
}
