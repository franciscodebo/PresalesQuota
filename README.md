# Pre-sales quota tracker, Q4 2026

Static snapshot of the **Attainment vs goal** view. It contains no deal-level information.

Open `index.html` locally, or enable GitHub Pages (Settings > Pages > Deploy from branch > `main` / root) for a URL.

## How it is updated

A scheduled Claude task regenerates `index.html`:

1. `python3 scripts/build.py sql` prints the aggregation query (runs against Superset, database_id 1).
2. The result rows are saved as JSON and `python3 scripts/build.py html results.json` rewrites `index.html`.
3. The task commits and pushes.

Goals, upsell and quote estimates live in `data/ref.private.json`, which is git-ignored on purpose (it holds deal-level detail) and is never committed. The update job reads it from the source dashboard and passes it with `REF_PATH`.

Interim figures: attribution is still being validated with the PBI team and the official tracker will be in Power BI on 13.11.26.
