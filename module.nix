# NixOS module for the NinjaOne remote access client (ncplayer).
# Extracts the binary from a user-supplied .deb, wraps it in an FHS environment
# to satisfy its library dependencies, and registers the ninjarmm:// URL scheme
# so browsers can launch remote sessions directly.
#
# Quick start:
#   1. Add this flake as an input in your flake.nix:
#        ninjaone.url = "github:4thehalibit/ninjaone-nixos";
#   2. Import the module:
#        imports = [ inputs.ninjaone.nixosModules.default ];
#   3. Log in to your NinjaOne portal → Devices → Add Device → Linux → x64 Debian/Ubuntu
#   4. Save the .deb to a path outside your config repo (it is tenant-specific):
#        mkdir -p ~/private && mv ~/Downloads/ninjarmm-ncplayer-*_amd64.deb ~/private/ninjarmm-ncplayer_amd64.deb
#   5. Enable the module and point deb_path at it:
#        programs.ninjaone = {
#          enable = true;
#          deb_path = /home/user/private/ninjarmm-ncplayer_amd64.deb;
#          update_alias.enable = true;        # optional: adds update-ninja alias
#          reset_browser_alias.enable = true; # optional: adds reset-ninja-browser command
#        };
#   6. Rebuild with --impure (required since deb_path is an absolute store path):
#        nixos-rebuild switch --impure
#   7. First-time browser setup:
#        Open your NinjaOne portal in Vivaldi (or any Chromium-based browser) and click
#        Connect on any device. When the browser asks to open NinjaOne Remote Player,
#        click Open. Future connections will launch automatically with no prompt.
#
# To update ncplayer: download the new .deb, move it to the same path, rebuild.
#   With update_alias.enable = true, run `update-ninja` then rebuild.
#
# Troubleshooting — ncplayer stops launching when clicking Connect:
#   The browser's stored protocol handler permission has gone stale. With
#   reset_browser_alias.enable = true, close the browser and run:
#     reset-ninja-browser
#   Then reopen the browser, click Connect, and approve the prompt once.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ninjaone;

  ncplayer-bin = pkgs.stdenv.mkDerivation {
    name = "ninjarmm-ncplayer-bin";
    src = cfg.deb_path;
    nativeBuildInputs = [ pkgs.dpkg ];
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      dpkg-deb -x $src extracted
      cp extracted/opt/ncplayer/bin/ncplayer $out/bin/ncplayer
      chmod +x $out/bin/ncplayer
    '';
  };

  ncplayer-fhs = pkgs.buildFHSEnv {
    name = "ncplayer";
    targetPkgs = pkgs: with pkgs; [
      libdrm
      libgbm
      mesa
      dbus
      stdenv.cc.cc.lib
    ];
    runScript = pkgs.writeShellScript "ncplayer-run" ''
      export QT_QPA_PLATFORM=xcb
      exec ${ncplayer-bin}/bin/ncplayer "$@"
    '';
  };

  ncplayer-desktop = pkgs.writeTextFile {
    name = "ninjarmm-ncplayer-desktop";
    destination = "/share/applications/ninjarmm-ncplayer.desktop";
    text = ''
      [Desktop Entry]
      Type=Application
      Name=NinjaOne Remote Player
      Exec=ncplayer %u
      StartupNotify=false
      MimeType=x-scheme-handler/ninjarmm;
    '';
  };

  reset-ninja-browser = pkgs.writeShellScriptBin "reset-ninja-browser" ''
    ${pkgs.python3}/bin/python3 -c "
import json, os, glob
browsers = ['vivaldi', 'google-chrome', 'chromium']
config_dir = os.path.expanduser('~/.config')
found = False
for browser in browsers:
    pattern = os.path.join(config_dir, browser, '*', 'Preferences')
    for pref_file in glob.glob(pattern):
        try:
            with open(pref_file, 'r+') as f:
                data = json.load(f)
                changed = False
                for origin in data.get('protocol_handler', {}).get('allowed_origin_protocol_pairs', {}).values():
                    if 'ninjarmm' in origin:
                        del origin['ninjarmm']
                        changed = True
                        found = True
                if changed:
                    f.seek(0); json.dump(data, f); f.truncate()
                    print('Reset: ' + pref_file)
        except Exception as e:
            print('Error reading ' + pref_file + ': ' + str(e))
if found:
    print('Done. Reopen your browser and click Connect in the NinjaOne portal to re-approve.')
else:
    print('No stale ninjarmm handler found in any browser profile.')
"
  '';

  deb_dir = builtins.dirOf (toString cfg.deb_path);
  deb_name = builtins.baseNameOf (toString cfg.deb_path);
in
{
  options.programs.ninjaone = {
    enable = lib.mkOption {
      default = false;
      description = "Install the NinjaOne remote access client (ncplayer).";
      type = lib.types.bool;
    };

    deb_path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the NinjaOne ncplayer .deb installer downloaded from your NinjaOne portal.
        The file is copied into the Nix store at evaluation time.

        The installer is tenant-specific (tied to your NinjaOne account) and should NOT be
        committed to a public repository. Use an absolute path outside your config repo:
          mkdir -p ~/private
          mv ~/Downloads/ninjarmm-ncplayer-*_amd64.deb ~/private/ninjarmm-ncplayer_amd64.deb

        Requires --impure at rebuild time due to the absolute path.
      '';
    };

    update_alias = {
      enable = lib.mkOption {
        default = false;
        description = ''
          Add an update-ninja shell alias that copies the latest ninjarmm-ncplayer*.deb
          from ~/Downloads to the configured deb_path, ready for a rebuild.
        '';
        type = lib.types.bool;
      };
    };

    reset_browser_alias = {
      enable = lib.mkOption {
        default = false;
        description = ''
          Add a reset-ninja-browser command that clears the stale ninjarmm:// protocol
          handler permission from Chromium-based browser profiles (Vivaldi, Chrome, Chromium).
          Run this with the browser closed if clicking Connect in the NinjaOne portal stops
          launching ncplayer. After running, reopen the browser and click Connect once to
          re-approve.
        '';
        type = lib.types.bool;
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.deb_path != null) {
    environment.systemPackages = [
      ncplayer-fhs
      ncplayer-desktop
    ] ++ lib.optionals cfg.reset_browser_alias.enable [
      reset-ninja-browser
    ];

    xdg.mime.defaultApplications = {
      "x-scheme-handler/ninjarmm" = "ninjarmm-ncplayer.desktop";
    };

    programs.zsh.shellAliases = lib.mkIf cfg.update_alias.enable {
      update-ninja = ''{ deb=$(ls ~/Downloads/ninjarmm-ncplayer-*.deb 2>/dev/null | sort -V | tail -1) && [ -n "$deb" ] && cp "$deb" "${deb_dir}/${deb_name}" && echo "Updated from $deb — run rebuild to apply." || echo "No ninjarmm-ncplayer*.deb found in ~/Downloads."; }'';
    };
  };
}
