# NixOS Updates

Shows what an update would bring, like `apt list --upgradable` on Debian:
the flake inputs that have new commits, the package versions of your NixOS
configuration that change with them (`brave 1.97.59 → 1.98.60`), and pending
Flatpak updates. The bar widget shows the count, the panel the details.

Checking changes nothing: `flake.lock` stays as it is, nothing is built or
installed. Updating is up to you, through the command you set for the panel's
**Update** button.

## Plugin

| Field | Value |
| --- | --- |
| ID | `dmopp/nixos-updates` |
| Entries | Bar widget: `updates`; panels: `panel` (compact), `details` (full list); service: `service` |

## Requirements

- `nix` with flakes (the plugin passes `--extra-experimental-features "nix-command flakes"`
  itself) and support for `nix flake update --output-lock-file` and
  `nix eval --reference-lock-file`. Tested with Nix 2.34.
- `sh`, `cat`, `cmp`, `cp`, `mv`, `rm`, `grep`, `sed`, `tail`, `tr` (coreutils,
  diffutils).
- Optional: `flatpak` for the Flatpak list.
- Optional: `xdg-open` to open the commit comparison of an input from the panel.

## Usage

1. Enable the plugin and add the bar widget `dmopp/nixos-updates:updates`.
2. Open the settings (Settings → Plugins → gear). **Flake directory** defaults
   to `/etc/nixos`; **NixOS configuration** defaults to the hostname.
3. Set **Update command** to whatever you use to update, for example
   `nix flake update --flake /etc/nixos && sudo nixos-rebuild switch --flake /etc/nixos && flatpak update -y`.
   It runs in a terminal from the panel's **Update** button.

The first check runs a minute after the plugin starts when the last one is
older than the check interval; the result of the last check is kept across
restarts. A change of `flake.lock` or of a Flatpak installation (after you
updated) triggers a new check about 20 seconds later.

Left-click the widget for the panel:

- **Flake inputs with new commits**: old and new revision, source and commit
  dates. Click an input hosted on GitHub, GitLab or Codeberg to open the
  comparison of both revisions in the browser.
- **Package changes**: every entry of `environment.systemPackages` plus the
  kernel whose version changes, appears or disappears.
- **Flatpak updates**: system and user installation, installed and new
  version (runtimes without a version show "new build").
- **Check now** and **Update**.

The compact panel shows at most eight rows across all sections; with more,
one **Show the full list** button below them (or the maximize button in the
header) opens the details window: one table with name, installed and new
version and details for every update (for packages: major, minor or patch
update, downgrade, new or removed), a search field (name, version or source)
and a filter by kind.

```sh
noctalia msg panel-toggle dmopp/nixos-updates:panel
noctalia msg panel-toggle dmopp/nixos-updates:details
```

The widget count is the number of package changes plus Flatpak updates; when
package versions are not compared (turned off, or the evaluation failed), the
number of changed inputs takes their place. Errors turn the glyph red and show
up in the tooltip and the panel.

## Settings

Plugin settings:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `flake_dir` | `folder` | `/etc/nixos` | Directory with `flake.nix` and `flake.lock`. Only read. Empty: only Flatpaks. |
| `nixos_configuration` | `string` | `""` | Attribute under `nixosConfigurations` to evaluate. Empty: the hostname. |
| `check_packages` | `bool` | `true` | Evaluate the configuration with the current and the updated lock and compare package versions. |
| `check_flatpak` | `bool` | `true` | List pending Flatpak updates of the system and user installations. |
| `check_interval_hours` | `int` | `6` | Hours between two checks (1-168). |
| `update_command` | `string` | `""` | Shell command for the **Update** button, run in a terminal. Empty: the button opens the settings instead. |
| `notify` | `bool` | `true` | Notify when a check finds updates that were not pending before. |
| `ignored_inputs` | `string_list` | `[]` | Advanced. Input names left out of the input list. |

Widget settings:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `glyph` | `glyph` | `package` | Glyph of the widget |
| `show_count` | `bool` | `true` | Show the number of updates |
| `show_zero` | `bool` | `false` | Show `0` when up to date |
| `hide_when_up_to_date` | `bool` | `false` | Hide the widget while nothing is pending and there is no error |
| `highlight_color` | `color` | `primary` | Glyph color while updates are pending |

## IPC

```sh
noctalia msg plugin dmopp/nixos-updates:service all check    # check now
noctalia msg plugin dmopp/nixos-updates:service all update   # run the update command in a terminal
```

## Notes

- **How the check works** (`scripts/check.sh`, started with `runStream` as it
  can take longer than the 60 s limit of `runAsync`):
  1. `nix flake update --flake <flake_dir> --output-lock-file <data>/new.lock`
     resolves every input to its latest revision and writes the result to the
     plugin data directory, not to `flake.lock`.
  2. `nix eval --json --no-write-lock-file --reference-lock-file <lock> '<flake_dir>#nixosConfigurations."<name>".config' --apply …`
     reads name and version of every `environment.systemPackages` entry and of
     `boot.kernelPackages.kernel`, once with `flake.lock` and once with
     `new.lock`. Nothing is built. Each result is cached with a copy of its
     lock and only evaluated again when that lock changed; when both locks are
     equal the second evaluation is skipped.
  3. `flatpak list` and `flatpak remote-ls --system|--user --updates`.
- **Network:** `nix` fetches the inputs' latest revisions (and, on the first
  evaluation of a new nixpkgs, its source) like `nix flake update` does;
  `flatpak remote-ls` fetches the remotes' metadata. The plugin itself makes no
  HTTP requests. Nothing runs while `shell.offline_mode` is on.
- **CPU:** an evaluation of the NixOS configuration takes a few seconds to a
  minute, depending on the configuration; with the cache above that happens
  only when a lock changed.
- **Files read:** `<flake_dir>/flake.nix` and `flake.lock` (through `nix`),
  `/var/lib/flatpak/.changed` and `~/.local/share/flatpak/.changed` (modification
  time only).
- **Files written:** only in the plugin data directory
  (`noctalia.pluginDataDir()`): `new.lock`, `packages-old.json`,
  `packages-new.json` with their `.lock` copies, `flatpak-installed.tsv`,
  `flatpak-updates.tsv`, and `result.json` with the last result.
- **Processes:** `sh scripts/check.sh` (with the `nix` and `flatpak` calls
  above), `xdg-open <compare url>` on a click on an input, and the configured
  update command in a terminal on **Update**.
- Only packages listed in `environment.systemPackages` (and the kernel) are
  compared, not their dependencies or services. Home Manager packages are not
  included.
