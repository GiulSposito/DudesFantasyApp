# Deploying the cockpit

The site is fully static — no server, no database, no Node build. Everything
the browser needs is `web/_site/` after a render.

## Local preview

```bash
# from the project root, with data/*.rds up to date
Rscript -e 'source("R/web/build_web_bundle.R"); build_web_bundle()'
quarto preview web
```

## Weekly publish

```bash
Rscript R/pipeline/data_pipeline_espn.R          # refresh espn_db (edit season/week in config/config.yml)
Rscript R/decision/decision_pipeline.R           # or source() + run_decision_pipeline(...)
Rscript -e 'source("R/web/build_web_bundle.R"); build_web_bundle(privacy = "public")'
quarto render web                                # -> web/_site/
```

`privacy = "public"` drops `owner_name` / owner ids. Use `"private"` (the
default) only for a deploy that is not world-readable.

Then serve `web/_site/` from anywhere:

```bash
python3 -m http.server -d web/_site 8000        # or any static host
```

## GitHub Pages

`web/data/` is gitignored and `data/*.rds` never leaves the machine, so Pages
cannot build the bundle in CI. Publish the rendered output from your machine:

```bash
quarto publish gh-pages web
```

This renders and pushes `web/_site/` to the `gh-pages` branch of
`origin` (`DudesFantasyApp`). Enable Pages for that branch in the repo
settings. A private repo's Pages site is still world-readable unless you are on
a plan with private Pages — treat it as public and always publish with
`privacy = "public"`.

## Cloudflare Pages / Netlify / S3

Upload the contents of `web/_site/` as a static site (direct upload, not a Git
build). Same `privacy = "public"` rule applies for any world-readable host.

## Runtime dependencies

Plotly and DuckDB-Wasm load from jsDelivr at runtime (see `web/js/head.html`),
so the published site needs network access on first load. To make it fully
offline, vendor them under `web/vendor/` — see `web/vendor/README.md`.

## Never publish

ESPN cookies (`config/config.yml`, `R/api/example_espn_342842788.R`) or any
`data/*.rds`. The bundle build only ever reads them; `validate_web_bundle()`
and `tests/web/test_privacy_public.R` guard the output.
