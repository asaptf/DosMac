# DosMac project site

Public GitHub Pages site: https://asaptf.github.io/DosMac/

- Privacy policy: https://asaptf.github.io/DosMac/privacy/
- Support: https://asaptf.github.io/DosMac/support/

The privacy and support documents in `docs/` are the content source. `scripts/build-website.py` renders them into static HTML, checks local links and anchors, and reuses the app's original icon. The site has no JavaScript, analytics, third-party fonts, forms, account service or application downloads.

Build with `python3 scripts/build-website.py`. Preview with `python3 -m http.server 8016 --directory build/website`. Pushes affecting the site or its source documents publish through `.github/workflows/pages.yml`; deployment uses GitHub Pages with HTTPS. Only `build/website` is uploaded, never native builds, disk images, source packages or signing material.
