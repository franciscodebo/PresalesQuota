#!/usr/bin/env python3
"""Build the static attainment page.

  python3 scripts/build.py sql              -> prints the aggregation SQL (run it in Superset, database_id 1)
  python3 scripts/build.py html results.json -> writes index.html from the SQL result rows

results.json: the rows returned by the SQL, either a list or {"rows": [...]}.
Goals, upsell and quote estimates come from REF_PATH (default data/ref.private.json, git-ignored: it holds deal-level detail).
OUT overrides the output path (default index.html).
"""
import json, html, sys, datetime, pathlib, os
ROOT = pathlib.Path(__file__).resolve().parent.parent
ref = json.load(open(os.environ.get('REF_PATH') or ROOT / 'data/ref.private.json'))
goals = [r for r in ref if r['kind'] == 'goal']
ups_dids = sorted({r['did'] for r in ref if r['kind'] == 'upsell'})

def make_sql():
    base = open(ROOT / 'scripts/base.sql').read()
    vals = ','.join("('%s','%s')" % (g['k'], g['doms']) for g in goals)
    ids = ','.join("'%s'" % d for d in ups_dids)
    return base + f""",
res AS (
  SELECT did, max(col) AS col, SUM(CASE WHEN dom='operations' THEN a ELSE 0 END) AS o, SUM(CASE WHEN dom='talent' THEN a ELSE 0 END) AS t, SUM(CASE WHEN dom='finance' THEN a ELSE 0 END) AS f
  FROM alloc WHERE dom IN ('operations','talent','finance','ot','sin_lineas','other') GROUP BY did
),
p AS (SELECT * FROM (VALUES {vals}) AS v(k, doms))
SELECT p.k,
  ROUND(SUM(CASE WHEN strpos(r.col, p.k) > 0 AND strpos(p.doms,'operations')>0 AND r.did NOT IN ({ids}) THEN r.o ELSE 0 END)) AS o,
  ROUND(SUM(CASE WHEN strpos(r.col, p.k) > 0 AND strpos(p.doms,'talent')>0 AND r.did NOT IN ({ids}) THEN r.t ELSE 0 END)) AS t,
  ROUND(SUM(CASE WHEN strpos(r.col, p.k) > 0 AND strpos(p.doms,'finance')>0 AND r.did NOT IN ({ids}) THEN r.f ELSE 0 END)) AS f
FROM p CROSS JOIN res r GROUP BY p.k ORDER BY p.k
"""

def build_html(rows):
    sq = {r['k']: (float(r['o']), float(r['t']), float(r['f'])) for r in rows}
    d = []
    for g in goals:
        k, doms = g['k'], g['doms'].split(',')
        o, t, f = sq.get(k, (0, 0, 0))
        by = {'operations': o if 'operations' in doms else 0, 'talent': t if 'talent' in doms else 0, 'finance': f if 'finance' in doms else 0}
        for r in ref:
            if r['kind'] in ('upsell', 'estimate') and k in r['nms'] and r['dom'] in doms and r['a'] > 0:
                by[r['dom']] = by.get(r['dom'], 0) + r['a']
        cred = round(sum(round(v) for v in by.values() if v > 0))
        d.append(dict(person=g['name'], team=g['team'], market=g['market'], goal=g['goal'], credited=cred, pct=cred / g['goal']))
    today = datetime.date.today()
    asof = f"{today.day} {today.strftime('%b %Y')}"
    eur = lambda n: '€' + f"{n:,.0f}"
    pc = lambda p: f"{p*100:.1f}%"
    tot = sum(x['credited'] for x in d); gt = sum(x['goal'] for x in d); ok = sum(x['pct'] >= .7 for x in d)
    status = lambda p: 'capped' if p >= 1.2 else 'ok' if p >= .7 else 'below'
    lab = {'capped': 'At the 120% cap', 'ok': 'Qualifies', 'below': 'Below 70%'}
    cards = ''
    for team in ['Operations', 'Talent', 'Finance']:
        ps = [x for x in d if x['team'] == team]
        cards += f'<section class="team"><h3>{team} <span class="m">{eur(sum(x["credited"] for x in ps))} of {eur(sum(x["goal"] for x in ps))}</span></h3><div class="grid">'
        for x in ps:
            w = min(x['pct'], 1.2) / 1.2 * 100; s = status(x['pct'])
            extra = ' · to reach 70%: ' + eur(max(0, round(.7 * x['goal'] - x['credited']))) if s == 'below' else ''
            cards += f'''<article class="card"><div class="row"><b>{html.escape(x['person'])}</b><span class="pill {s}">{pc(x['pct'])}</span></div>
<div class="sub">{html.escape(x['market'])}</div>
<div class="bar" role="img" aria-label="{pc(x['pct'])} of goal"><i style="width:{w:.1f}%"></i><u style="left:{.7/1.2*100:.2f}%"></u><u class="full" style="left:{1/1.2*100:.2f}%"></u></div>
<div class="foot"><span>{eur(x['credited'])} credited</span><span>Goal {eur(x['goal'])}</span></div>
<div class="sub">{lab[s]}{extra}</div></article>'''
        cards += '</div></section>'
    trs = ''.join(f'<tr><td>{html.escape(x["person"])}</td><td>{x["team"]}</td><td>{html.escape(x["market"])}</td><td class="n">{eur(x["goal"])}</td><td class="n">{eur(x["credited"])}</td><td><span class="pill {status(x["pct"])}">{pc(x["pct"])}</span></td><td class="n">{eur(max(0, round(.7 * x["goal"] - x["credited"])))}</td></tr>' for x in d)
    css = (ROOT / 'scripts/style.css').read_text()
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pre-sales quota tracker, Q4 2026</title>
<style>
{css}</style></head><body><main>
<header><h1>Pre-sales quota tracker, Q4 2026</h1>
<p>{ok} of {len(d)} people with a goal are at or above the 70% threshold. The team has credited {eur(tot)} of {eur(gt)} ({pc(tot/gt)}), counting deals closed up to {asof}.</p></header>
<aside class="note" role="note"><b>*</b> <b>Interim tracker.</b> The Q4 goals are approved. We are completing the data adjustments needed to make the tracking fully accurate, and the attribution will be validated with our PBI team before it becomes official. The official tracker will be available in Power BI by Friday 13.11.26. Until then, this page provides interim visibility, and figures may still change as the validation is completed.</aside>
<section><h2>Attainment against the approved goal</h2>
<p class="mut">Credited euros in each person's own domain, any country, divided by the approved Q4 goal. Snapshot of {asof}; updated by a scheduled job.</p>
<p class="mut legend"><span>Full colour bar = 120% of the goal (cap)</span><span>Dark tick: 70% threshold</span><span>Light tick: 100%</span></p>
{cards}</section>
<section><div class="box"><table><thead><tr><th>Person</th><th>Team</th><th>Market</th><th class="n">Goal</th><th class="n">Credited</th><th>Attainment</th><th class="n">To reach 70%</th></tr></thead><tbody>{trs}</tbody></table></div></section>
<footer>Attainment is credited euros divided by the approved goal. Below the 70% threshold there is no individual variable, and anything above the 120% cap counts as the cap. Some credit comes from deals whose line items were not yet in HubSpot and is estimated from the quote until they are.</footer>
</main></body></html>'''

if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] == 'sql':
        print(make_sql())
    elif len(sys.argv) >= 3 and sys.argv[1] == 'html':
        data = json.load(open(sys.argv[2]))
        rows = data['rows'] if isinstance(data, dict) else data
        if len(rows) != len(goals): sys.exit(f'Expected {len(goals)} rows, got {len(rows)}')
        out = pathlib.Path(os.environ.get('OUT') or ROOT / 'index.html')
        out.write_text(build_html(rows))
        print(out, 'written')
    else:
        sys.exit(__doc__)
