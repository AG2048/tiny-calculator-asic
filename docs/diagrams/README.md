# Diagram generation

The diagrams in this directory are generated documentation assets. Edit `generate-diagrams.js`, not the generated SVG or PNG files directly.

## Files

- `architecture.svg/png`: physical pins, internal blocks, handshakes, and external display hardware.
- `button-array.svg/png`: illustrative 4x4 WL/BL switch and diode matrix.
- `fsm-simplified.svg/png`: user-facing calculator phases with their RTL substates grouped inside.
- `fsm-detailed.svg/png`: every `calculator_core` RTL state and transition.

SVG is the source-quality publishing format. PNG copies are tracked for renderers that do not display SVG reliably and for the Tiny Tapeout datasheet pipeline.

## Regenerate

From this directory, install the pinned rasterizer and generate both formats:

```sh
npm install --no-package-lock
npm run generate
```

`generate-diagrams.js` writes all SVG files. `render-png.js` uses [Sharp](https://sharp.pixelplumbing.com/) to rasterize each SVG at its declared width and height without resizing it.

After regeneration, inspect every PNG at full resolution. Check that text is not clipped, wires do not cross labels or state boxes, parallel routes remain distinguishable, and every arrowhead visibly terminates at its intended destination.
