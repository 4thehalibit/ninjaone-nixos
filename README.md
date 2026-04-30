# ninjaone-nixos

NixOS module for the NinjaOne remote access client (`ncplayer`).

Extracts the binary from a user-supplied `.deb`, wraps it in an FHS environment to satisfy its library dependencies, and registers the `ninjarmm://` URL scheme so browsers can launch remote sessions directly.

> **Note:** NinjaOne does not distribute `ncplayer` through a public package repository. The `.deb` installer is tenant-specific (tied to your NinjaOne account) and must be downloaded manually from your portal.

## Usage

### 1. Add the flake input

```nix
# flake.nix
inputs.ninjaone.url = "github:4thehalibit/ninjaone-nixos";
```

### 2. Import the module

```nix
imports = [ inputs.ninjaone.nixosModules.default ];
```

### 3. Download your installer

Log in to your NinjaOne portal → **Devices** → **Add Device** → **Linux** → **x64 Debian/Ubuntu** and download the `.deb`. Keep it outside your config repo — it contains your tenant credentials:

```bash
mkdir -p ~/private
mv ~/Downloads/ninjarmm-ncplayer-*_amd64.deb ~/private/ninjarmm-ncplayer_amd64.deb
```

### 4. Enable the module

```nix
programs.ninjaone = {
  enable = true;
  deb_path = /home/youruser/private/ninjarmm-ncplayer_amd64.deb;
  update_alias.enable = true; # optional
};
```

### 5. Rebuild

The absolute `deb_path` requires `--impure`:

```bash
nixos-rebuild switch --impure
```

## Protecting the .deb with the Nix store (recommended)

Keeping the `.deb` in `~/private` works but is vulnerable to accidental deletion. A more durable approach is to add it to the Nix store with a GC root so it survives garbage collection:

```bash
store_path=$(nix store add-path /path/to/ninjarmm-ncplayer_amd64.deb --name ninjarmm-ncplayer_amd64.deb)
sudo nix-store --add-root /nix/var/nix/gcroots/ninjaone -r "$store_path"
echo $store_path
```

Then use the printed store path in your config instead of the `~/private` path:

```nix
programs.ninjaone = {
  enable = true;
  deb_path = /nix/store/<hash>-ninjarmm-ncplayer_amd64.deb;
};
```

The file is now content-addressed in the store and the GC root prevents `nix-collect-garbage` or `nh clean` from removing it. Rebuilds still require `--impure` since the path is outside the flake tree.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `programs.ninjaone.enable` | bool | `false` | Install the NinjaOne remote access client |
| `programs.ninjaone.deb_path` | path | `null` | Path to the `.deb` downloaded from your NinjaOne portal |
| `programs.ninjaone.update_alias.enable` | bool | `false` | Add an `update-ninja` shell alias (see below) |

## Updating

NinjaOne releases updates frequently. To update:

1. Download the new `.deb` from your portal
2. Replace the file at `deb_path`
3. Rebuild with `--impure`

With `update_alias.enable = true`, the `update-ninja` alias copies the latest `.deb` from `~/Downloads` to `deb_path` automatically:

```bash
update-ninja
nixos-rebuild switch --impure
```
