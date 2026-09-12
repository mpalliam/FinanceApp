# App Icon Source

`AppIcon.swift` renders the 1024×1024 icon in `FinanceNotebook/Assets.xcassets`.
It is kept here as the source of truth so the icon can be regenerated or
adjusted without redrawing it by hand. It is **not** a member of the app target
and ships nothing.

Regenerate with:

```bash
swift Artwork/AppIcon.swift FinanceNotebook/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Design: a ledger page on deep green, with a binding edge, three ruled lines and
a single bold currency mark. Flat colour and one focal glyph, so it stays
readable at Home Screen size. Rendered without an alpha channel, which Apple
requires for app icons.
