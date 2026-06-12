# map-decals

Place persistent decals on the map from a menu (CS:S)

## Dependencies

- [printer](https://github.com/happydez/printer)
- [flags-core](https://github.com/happydez/flags-core)

## flags-core

Each decal in `configs/fun/map-decals.cfg` defines its own access flag (its `flags` key),
so the available flags are auto-detected from that config. The plugin also uses a per-player
**limit** (max decals placed), which you set per group.

Grant it via flags-core, e.g. in `configs/flags/flags-groups.cfg` (`limit` -1 = unlimited):

```
"VIP"
{
    "map-decals" { "flags" "ab" "limit" "128" }
}
```
