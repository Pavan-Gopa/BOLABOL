# BOLABOL landing page

Production-oriented static landing page for BOLABOL.

## Design goals

- fast, dependency-free HTML/CSS/vanilla JS;
- dark macOS-native visual language;
- product-first messaging rather than a second README;
- prominent HUD demo and direct DMG download;
- clear local-first / optional-cloud positioning;
- visible Five-Person Grant and Freedom Clock;
- responsive layout and reduced-motion support.

## Local preview

From the repository root:

```bash
cd website
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

## Deployment

The site has no build step. Serve the contents of `website/` as the web root.

The intended public destination is:

`https://local.ai/bolabol`

For a Hugging Face Static Space, place `index.html`, `styles.css`, and `app.js` at the Space root and use Static HTML as the Space SDK.

Example Space README metadata:

```yaml
---
title: BOLABOL
emoji: 🎙️
colorFrom: gray
colorTo: purple
sdk: static
pinned: false
license: other
short_description: Native AI voice input for Apple Silicon Macs.
---
```

BOLABOL uses its own BSL 1.1 configuration with the Five-Person Grant and Freedom Clock, so the Space metadata uses `license: other`; the canonical legal text remains in the main BOLABOL repository.

## Assets

This first deployment-ready version references the canonical BOLABOL screenshots and HUD animation from the public GitHub repository. For a fully self-contained deployment, mirror those assets into the final host and change the URLs to local paths.
