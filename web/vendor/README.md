# web/vendor/ — offline third-party assets (optional)

By default the cockpit loads Plotly and DuckDB-Wasm from jsDelivr at runtime
(`web/js/head.html`). That keeps the repo small but needs network on first load.

To make the published site fully offline, vendor the assets here (no Node
required — plain `curl`):

```bash
mkdir -p web/vendor/plotly web/vendor/duckdb
curl -L -o web/vendor/plotly/plotly.min.js \
  https://cdn.jsdelivr.net/npm/plotly.js-dist-min@2.35.2/plotly.min.js

# DuckDB-Wasm: the ESM module + the mvp/eh wasm bundles and workers
base=https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.29.0/dist
for f in duckdb-browser.mjs \
         duckdb-mvp.wasm  duckdb-browser-mvp.worker.js \
         duckdb-eh.wasm   duckdb-browser-eh.worker.js ; do
  curl -L -o "web/vendor/duckdb/$f" "$base/$f"
done
```

Then in `web/js/head.html` point the import map at
`./vendor/duckdb/duckdb-browser.mjs` and the Plotly `<script src>` at
`./vendor/plotly/plotly.min.js`, and in `web/js/data.js` replace
`duckdb.getJsDelivrBundles()` with an explicit `{ mainModule, mainWorker }`
map built from `./vendor/duckdb/…` URLs.

`web/vendor/` is **not** gitignored — commit it if you vendor. Expect ~15 MB
(mostly the two `.wasm` files).
