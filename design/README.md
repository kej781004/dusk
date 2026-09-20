# Design source

Where the icon came from and how to regenerate it, so this isn't a stray
folder full of unexplained PNGs a year from now.

- **`reference-3icons.png`** — the approved concept, generated in ChatGPT:
  a laptop with a crescent-moon screen, three colourways. This is the visual
  language everything else in this folder is redrawn from — don't diverge
  from its proportions without a reason.
- **`render_icon.py`** — redraws that shape as clean vector-quality art
  (not a resample of the ChatGPT PNG, which has soft AI-generation edges) and
  produces the 1024px app-icon master. Run `python3 render_icon.py out.png
  1024 black` (or `indigo`) to regenerate it, then rebuild the `.icns`:
  ```sh
  mkdir AppIcon.iconset
  for s in 16 32 64 128 256 512 1024; do
    sips -z $s $s out.png --out AppIcon.iconset/icon_${s}x${s}.png
    [ $s -le 512 ] && sips -z $((s*2)) $((s*2)) out.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
  done
  rm AppIcon.iconset/icon_64x64*.png   # not a standard iconset size
  iconutil -c icns AppIcon.iconset -o ../Resources/AppIcon.icns
  ```
- **`preview_menubar.py`** — the same shape redrawn at actual 18×18pt menu
  bar scale (the app-icon version would look like a blurry smudge shrunk
  that far down), proofed against a mock menu bar before the numbers were
  ported into `Sources/Dusk/StatusIcon.swift`. Useful if the glyph ever needs
  adjusting again — much faster to iterate on than recompiling Swift.

Brand colour: `#4A3AFA` (sampled from the approved reference), used for both
the "on" menu bar glyph and nowhere else yet.
