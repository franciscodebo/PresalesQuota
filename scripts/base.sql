WITH d AS (
  SELECT CAST(id AS varchar) AS did, deal_name AS dn, stage AS st, CAST(date(close_date) AS varchar) AS cd,
         upper(COALESCE(market,'')) AS mk, pipeline_name AS pipe,
         COALESCE(amount_euros,0) AS amt, all_collaborator_names AS names,
         lower(array_join(all_collaborator_names,';')) AS col
  FROM data_lake_gold.sales_fact_sales_deals
  WHERE close_date >= DATE '2026-10-01' AND close_date < DATE '2027-01-01'
    AND lower(stage) LIKE 'closed won%'
    AND COALESCE(is_deleted,false)=false
    AND upper(COALESCE(market,'')) IN ('ES','IT','FR','PT','DE','ROW')
    AND regexp_like(lower(array_join(all_collaborator_names,';')),'joshua metcalf|gabriela fontes|lucas denis|rebecca oberstadt|martina friedman|judit gal|pauline moutaux|christian gross|martina montinaro|federico d.orsi|eudald font|carlota colina|louis wincker|samuel piteo|karla westerkamp|nicky anup')
),
li0 AS (
  SELECT CAST(dl.deal_id AS varchar) AS did, dl.product_slug AS slug, dl.resolution AS res,
         regexp_replace(lower(COALESCE(li.name,'')),'[^a-z0-9 +]','') AS nm, COALESCE(li.amount,0) / CAST(count(*) OVER (PARTITION BY dl.deal_id, dl.line_item_id) AS double) AS amt
  FROM data_lake_silver.revops_deal_line_items dl
  LEFT JOIN data_lake_silver.revops_line_item li ON CAST(li.id AS varchar)=CAST(dl.line_item_id AS varchar)
  WHERE CAST(dl.deal_id AS varchar) IN (SELECT did FROM d)
),
lib AS (
  SELECT did, amt, nm, slug, res,
    CASE
      WHEN nm IN ('factorial people essential','factorial people essentials') THEN 'B_essential'
      WHEN nm IN ('factorial people scale','people scale de') THEN 'B_scale'
      WHEN nm IN ('factorial people finance','factorial people + finance') THEN 'B_people_finance'
      WHEN nm IN ('factorial people it','factorial people + it') THEN 'B_people_it'
      WHEN nm IN ('factorial finance it','factorial finance + it') THEN 'B_finance_it'
      WHEN nm = 'factorial finance' THEN 'B_finance'
      WHEN nm = 'factorial it' THEN 'B_it'
      WHEN nm = 'factorial suite' THEN 'B_suite'
      WHEN nm IN ('factorial core','factorial core de') THEN 'B_core'
      WHEN nm = 'one company credits' THEN 'company'
      ELSE NULL END AS bundle
  FROM li0
),
li1 AS (
  SELECT did, amt, bundle AS dom FROM lib WHERE bundle = 'company'
  UNION ALL
  SELECT lib.did, lib.amt * t.share AS amt, t.dom
  FROM lib JOIN d ON d.did = lib.did
  CROSS JOIN UNNEST(
    CASE CONCAT(lib.bundle, CASE WHEN d.mk IN ('ES','PT') THEN '|a' ELSE '|b' END)
      WHEN 'B_core|a' THEN ARRAY[ROW('operations',0.360),ROW('talent',0.180),ROW('finance',0.180),ROW('it',0.180),ROW('company',0.100)]
      WHEN 'B_core|b' THEN ARRAY[ROW('operations',0.360),ROW('talent',0.180),ROW('finance',0.180),ROW('it',0.180),ROW('company',0.100)]
      WHEN 'B_essential|a' THEN ARRAY[ROW('operations',0.900),ROW('company',0.100)]
      WHEN 'B_essential|b' THEN ARRAY[ROW('operations',0.900),ROW('company',0.100)]
      WHEN 'B_scale|a' THEN ARRAY[ROW('operations',0.394),ROW('talent',0.366),ROW('finance',0.141),ROW('company',0.100)]
      WHEN 'B_scale|b' THEN ARRAY[ROW('operations',0.341),ROW('talent',0.403),ROW('finance',0.155),ROW('company',0.100)]
      WHEN 'B_finance|a' THEN ARRAY[ROW('operations',0.464),ROW('finance',0.436),ROW('company',0.100)]
      WHEN 'B_finance|b' THEN ARRAY[ROW('operations',0.393),ROW('finance',0.507),ROW('company',0.100)]
      WHEN 'B_it|a' THEN ARRAY[ROW('it',0.900),ROW('company',0.100)]
      WHEN 'B_it|b' THEN ARRAY[ROW('it',0.900),ROW('company',0.100)]
      WHEN 'B_people_finance|a' THEN ARRAY[ROW('operations',0.300),ROW('talent',0.279),ROW('finance',0.221),ROW('company',0.200)]
      WHEN 'B_people_finance|b' THEN ARRAY[ROW('operations',0.257),ROW('talent',0.303),ROW('finance',0.241),ROW('company',0.200)]
      WHEN 'B_people_it|a' THEN ARRAY[ROW('operations',0.255),ROW('talent',0.236),ROW('finance',0.091),ROW('it',0.218),ROW('company',0.200)]
      WHEN 'B_people_it|b' THEN ARRAY[ROW('operations',0.215),ROW('talent',0.254),ROW('finance',0.098),ROW('it',0.234),ROW('company',0.200)]
      WHEN 'B_finance_it|a' THEN ARRAY[ROW('operations',0.264),ROW('finance',0.248),ROW('it',0.288),ROW('company',0.200)]
      WHEN 'B_finance_it|b' THEN ARRAY[ROW('operations',0.211),ROW('finance',0.273),ROW('it',0.316),ROW('company',0.200)]
      WHEN 'B_suite|a' THEN ARRAY[ROW('operations',0.227),ROW('talent',0.211),ROW('finance',0.168),ROW('it',0.195),ROW('company',0.200)]
      WHEN 'B_suite|b' THEN ARRAY[ROW('operations',0.190),ROW('talent',0.224),ROW('finance',0.178),ROW('it',0.207),ROW('company',0.200)]
      ELSE ARRAY[] END
  ) AS t(dom, share)
  WHERE lib.bundle IS NOT NULL AND lib.bundle <> 'company'
  UNION ALL
  SELECT did, amt,
    CASE
      WHEN slug IN ('core','time_off','time_tracking','time_planning','compensations','benefits','salary_advance','policies','payroll','professionals') THEN 'operations'
      WHEN slug IN ('performance','recruitment','trainings','lms','engagement','complaints','space','campus','culture_fit_assessments') THEN 'talent'
      WHEN slug IN ('expenses','projects','headcount','procurement','sales_invoicing','accounts_payable','financial_workspace','salary_review') THEN 'finance'
      WHEN slug = 'one' THEN 'one'
      WHEN slug LIKE 'it_%' OR slug='software_management' THEN 'it'
      WHEN slug IS NOT NULL THEN 'integrations'
      WHEN res='service' OR res='missing_line_item' THEN 'service'
      WHEN regexp_like(nm,'onboarding|formaci|implement|consult|beratung|session|sess|sesi|data entry|training|schulung|placeholder|plan success|sql service|do not use|project manager|conseil|paie|nmina|buste|gehalt') THEN 'service'
      WHEN regexp_like(nm,'salary review|gastos|despesas|spese|spesen|expenses|notes de frais|projet|projec|procure|headcount|invoic|quadro de colab') THEN 'finance'
      WHEN regexp_like(nm,'complaint|canal seguro|denuncia|whistle|\bats\b|lms|engaj|engag|recrut|recruit|performance|treinamento|talent|desempenho|pesquisa|survey|avalia') THEN 'talent'
      WHEN regexp_like(nm,'\bone\b|\bia\b|\bai\b') THEN 'one'
      WHEN regexp_like(nm,'mdm|saas|inventrio de ti|inventario|factorial it|sentinel|software|threatdown|edr') THEN 'it'
      WHEN regexp_like(nm,'silae|sage|zkteco|suprema|primavera|sap\b|microsoft|phc|navision|integra') THEN 'integrations'
      WHEN regexp_like(nm,'planning|zeitplan|turnos|escalas|plano|pacote|base factorial|compensa|bookkeeper|payroll|essencial|completo|premium|core|business|enterprise|starter|frias|ferias|ponto|ausncias|ausencias|rh|dp\b|polticas|time off') THEN 'operations'
      ELSE 'other' END AS dom
  FROM lib WHERE bundle IS NULL
),
lw AS (SELECT did, CASE WHEN dom IN ('one','it','integrations') THEN 'ot' ELSE dom END AS dom, SUM(amt) AS w FROM li1 WHERE dom <> 'service' GROUP BY 1, 2),
tw AS (SELECT did, SUM(w) AS wt FROM lw GROUP BY did),
alloc AS (
  SELECT d.did, d.dn, d.st, d.cd, d.mk, d.pipe, d.names, d.col, d.amt AS deal_amt,
         CASE WHEN COALESCE(tw.wt,0) > 0 THEN lw.dom ELSE 'sin_lineas' END AS dom,
         CASE WHEN COALESCE(tw.wt,0) > 0 THEN d.amt * lw.w / tw.wt ELSE d.amt END AS a
  FROM d LEFT JOIN tw ON tw.did=d.did
  LEFT JOIN lw ON lw.did=d.did AND tw.wt > 0
)
