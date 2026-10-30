# noctalia-nixos-updates

Development repo for the Noctalia plugin [`dmopp/nixos-updates`](nixos-updates/README.md):
pending flake input, package and Flatpak updates on NixOS, like `apt list --upgradable`.

- `nixos-updates/` - the plugin, laid out for
  [noctalia-dev/community-plugins](https://github.com/noctalia-dev/community-plugins)
  (submit that directory as is).
- `i18n/de.json` - German strings. Community plugins ship `translations/en.json`
  only; other languages go through [Noctalia Translate](https://i18n.noctalia.dev),
  so enter these there once the plugin is merged.

Local use:

```sh
noctalia msg plugins source add nixos-updates-local path ~/coding-projects/noctalia-nixos-updates
noctalia msg plugins enable dmopp/nixos-updates
```

Tests of the comparisons (not part of the plugin directory):

```sh
nix shell nixpkgs#luau -c luau tests/diff.luau
```

Written with help from Claude Code.
