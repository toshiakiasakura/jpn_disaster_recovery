# Migration-rate methods

How the notebooks currently calculate migration rates by age and cohort around the 2011 Tohoku and 2016 Kumamoto earthquakes. This covers `src/3r_migration_kumamoto.ipynb`, `src/4r_residual_migration.ipynb` and `src/5r_ungroup2d.ipynb`, plus the variant in `src/6r_no_offset.ipynb`, which is still in progress. Data sources are in `doc/data.md`, and caveats are in `doc/caution.md`. The design is still provisional: it is under review with the statistician (protocol §0).

## 1. Overview

We use two estimators.

- **A. Direct rates (3r).** Movers come from 住民基本台帳人口移動報告. Municipal 5-year age detail exists only from 2014, so this works for Kumamoto only.
- **B. Residual net migration (4r, 5r).** Net migration = population change + deaths. It needs only population and deaths by age, so it also works for 2011. It gives net migration only, not in- and out-migration separately.

For Kumamoto 2014–2020 both are available, and A is used to check B (§7).

| Notebook | Event | Population counts | Baseline (last count before the quake) | Quake interval |
|---|---|---|---|---|
| 3r (direct) | Kumamoto, 45 municipalities | 1 Jan 2014 … 2025; movers for calendar years 2014–2025 | 2016-01-01 | calendar 2016 |
| 4r/5r (residual) | Tohoku, 123 municipalities (岩手 33, 宮城 34, 福島 56) | 2006-03-31 … 2016-01-01 | 2010-03-31 | 2010-03-31 → 2011-03-31 |
| 4r/5r (residual) | Kumamoto, 45 municipalities | 2011-03-31 … 2021-01-01 (5r fig. 8: to 2026-01-01) | 2016-01-01 | 2016-01-01 → 2017-01-01 |

Municipalities are those listed in `1_市町村一覧` under 東日本 and 福島 (Tohoku) or 熊本.

## 2. Data and basis

All series are restricted to Japanese nationals and both sexes (`sex == "計"`), so that numerators and denominators match.

- **Movers:** `dt/idou_age_sex_5yr_long.qs2`, filtered to `mover == "japanese"` and `level == "municipality"`. The 2014–2017 tables publish only this basis.
  - 転入 (in) and 転出 (out) count moves between municipalities only.
  - The `origin_unknown` band is dropped.
- **Population:** `dt/jumin_age_sex_5yr_long.qs2`, filtered to `basis == "japanese"`.
  - Counts are on 31 March up to 2012 and on 1 January from 2013.
  - The top band is 80+ through 2014 and 100+ from 2015.
- **Deaths:** `dt/deaths_age_sex_5yr_long.qs2` (人口動態統計, deaths of Japanese by place of residence, by calendar year). The top band is 100+. Deaths of unknown age are dropped, because they cannot be assigned to a cohort.
- **National single-year shape:** `dt/natpop_japanese_single_year.csv` (人口推計, Japanese population on 1 October, available to 2020).

See `doc/data.md` §3–6.

## 3. From 5-year bands to single years of age

Every series is split into single years 0–104 with the penalized composite link model, `ungroup::pclm` (Rizzi et al. 2015). The fit is done separately for each municipality × year × series.

- **Open bands:** the open top band is spread up to age 104 (`top_age = 105`).
- **Zero bands:** these are set to 1e-4, as the package advises.
- **Smoothing:** λ is chosen by BIC.

| Series | 3r | 4r (default for the residual) | 5r variant | 6r variant (in progress) |
|---|---|---|---|---|
| Population | plain 1D `pclm` | 1D `pclm` with national offset, rescaled to band totals | `pclm2D` (age × time) with national offset, rescaled | 1D `pclm` and `pclm2D`, no offset, rescaled |
| Deaths | — | plain 1D `pclm` | 1D from 4r | 1D from 4r |
| Movers | plain 1D `pclm` | plain 1D `pclm` (only for the validation) | 1D from 4r | 1D from 4r |

### National offset (population, 4r/5r)

A one-year residual subtracts two single-year splits taken a year apart. It is therefore very sensitive to sharp differences in cohort size that 5-year bands hide. Examples are the small 1945–46 births next to the 1947–49 baby boom, and 1966 (丙午).

- **Effect of plain pclm:** it smooths these cliffs away. That produced spurious swings of about ±60–65 per 1,000 at ages 60–69.
- **How the offset helps:** pclm then smooths only the ratio of municipal to national population, so the cliffs come from the national shape.
- **Offset at a count date** (`offset_count(y, ref)`): with *N*<sub>y−1</sub>(*a*) the national population on 1 October of *y*−1, the offset is *w*·*N*<sub>y−1</sub>(*a*) + (1−*w*)·*N*<sub>y−1</sub>(*a*−1).
  - *w* = 0.75 for 1 January counts (a quarter-year later) and 0.5 for 31 March counts (half a year later).
  - The national 100+ count is spread over ages 100–104 in the proportions 0.40 / 0.27 / 0.17 / 0.10 / 0.06.
- **Rescaling:** the fitted values are rescaled within each band, so every published band total is kept exactly.
- **Fallback:** if a fit gives non-finite or non-positive values, the national within-band shares are used instead.
- **Effect on noise:** the offset roughly halves the noise at the band edges, to about ±15–30 per 1,000, but cannot remove it.
- **Deaths:** these are added, not differenced, so they use plain pclm. Offset fits give negative values below about 160 deaths a year.

### 2D variant (5r)

- **Fit:** one `pclm2D` fit per municipality over the event window.
  - Bands are harmonised to 0–4 … 75–79, 80+.
  - The national offset is used at each count date.
  - λ for age and λ for time are chosen by BIC in [0.1, 1e5], with `kr = 2`.
  - The fit is rescaled to the band totals.
- **Deaths and movers stay 1D**, so that the 2011 and 2016 spikes are not smoothed over time.
- **5r figure 8** extends Kumamoto to 2026, beyond the end of the national shape. It therefore uses plain `pclm2D` without the offset. Read the residual there only up to about age 40.

## 4. Cohorts and the Lexis approximation

- **Crediting movers and deaths to cohorts.** Movers (or deaths) in year *t* are reported by age *x* at the event. The cohort aged *x* at the start of the interval is credited with

  > ½ · (M(*x*) + M(*x*+1))

  This assumes events are spread evenly over the year.
- **Cohort label.** A cohort is labelled by its age at the baseline count: *a*<sub>0</sub> = *x* − (*t* − baseline year).
  - Intervals before the baseline are a **back-cast**: they trace the same people backwards.
  - Ages with *a*<sub>0</sub> < 0 (not yet born) are dropped.
- **Cohort bins in the figures:** 0–4, 5–9, …, 35–39, 40–49, 50–59, 60–69, 70–84. The heatmaps use 5-year bins up to 80–84.
- **Pooling:** rates for a bin or a group of municipalities are pooled. Numerators and denominators are summed before dividing.
- **Groups:**
  - Tohoku: 岩手・宮城 with 全壊率 ≥ 1; 福島 municipalities with an evacuation order (避難指示); the other listed municipalities.
  - Kumamoto: high damage (全壊率 ≥ 1: 益城町, 西原村, 南阿蘇村, 嘉島町, 御船町); 熊本市; the other listed municipalities.

## 5. Direct rates (3r, Kumamoto)

**Cohort rates (figures 4–7).** For a cohort in calendar year *t*:

> out-rate(*t*) = 1000 · Σ credited out-movers(*t*) ÷ Σ P(*x*, 1 January *t*)
>
> in-rate(*t*) has the same form with in-movers; net = in-rate − out-rate

- Sums run over the single ages in the cohort bin, and over municipalities when a group is pooled.
- Each year uses its own 1 January denominator.

**Fixed-age profiles (figure 3).** These use the published 5-year bands, without ungrouping. The top band is 80+.

- For a band and period, rate = 1000 · Σ movers ÷ Σ 1 January population over the period's years. This is a person-year-weighted mean.
- Periods: before (2014–15), the quake year (2016), after (2017–19) and later (2020–25).

The 2016 calendar year includes about 3½ months before the April quake.

**Change from the pre-quake baseline (figures 8–10).** These also use the published bands.

- change(*b*, *t*) = net rate(*b*, *t*) − base(*b*), in points per 1,000 per year. base(*b*) is the mean of the band's 2014 and 2015 net rates, (rate<sub>2014</sub> + rate<sub>2015</sub>) / 2.
- Figure 8 pools each 3r group; figure 10 shows the same values as line plots (one panel per group, one line per age band). Figure 9 compares each municipality with its own baseline, for ages 25–29, 40–44 and 60–64.

## 6. Residual net migration (4r, 5r)

### 6.1 Matching deaths to the intervals between counts

Deaths are counted by calendar year *y* (D<sub>y</sub>). Population counts are on 31 March up to 2012 and on 1 January from 2013. Each interval between counts gets:

| Interval | Deaths used | Length (`span`) |
|---|---|---|
| 31 Mar *y* → 31 Mar *y*+1 (up to 2011) | 0.75·D<sub>y</sub> + 0.25·D<sub>y+1</sub> | 1 |
| 2012-03-31 → 2013-01-01 | 0.75·D<sub>2012</sub> | 0.75 |
| 1 Jan *y* → 1 Jan *y*+1 (2013 on) | D<sub>y</sub> | 1 |

**Tohoku 2011 excess deaths.** At each age, the 2011 deaths are split into a usual level and an excess:

- usual level B = (D<sub>2009</sub> + D<sub>2010</sub>) / 2;
- excess E = D<sub>2011</sub> − B.

The two Tohoku intervals around the quake then get:

| Interval | Deaths used |
|---|---|
| 2010-03-31 → 2011-03-31 | 0.75·D<sub>2010</sub> + 0.25·B |
| 2011-03-31 → 2012-03-31 | 0.75·B + 0.25·D<sub>2012</sub> + **E** |

Why E goes in the later interval:

- The register removed the tsunami victims only after 2011-03-31, through death notifications and, from June 2011, presumed deaths of the missing.
- Putting E in the quake interval instead gives impossible net *in*-migration of about +70 per 1,000 in 大槌町 and 陸前高田市.
- For tsunami towns, read the quake interval and year 1 together. Their sum does not depend on this choice. The switch is `excess_to` in the notebook.

### 6.2 Residual and rate

For the single-year cohort aged *x* at the start of an interval:

> NM = P<sub>end</sub>(*x*+1) − P<sub>start</sub>(*x*) + ½·(D(*x*) + D(*x*+1))

- **The 0.75-year interval** (2012-03-31 → 2013-01-01): only three quarters of the cohort has a birthday in it, so P<sub>end</sub> = 0.75·P(*x*+1) + 0.25·P(*x*).
- **Rate** per 1,000 per year, pooled over the ages in a bin and the municipalities in a group:

  > rate = 1000 · Σ NM ÷ Σ (P<sub>start</sub> · span)

  Each interval is computed on its own.
- **Accounting check:** for each municipality and interval, Σ NM over all cohorts should equal (population change + deaths) − (newborns + ½·infant deaths). Newborns and half of the infant deaths are not covered by any starting cohort. For the 0.75-year interval, newborns are weighted by 0.75. The `unexplained` column of the check should be close to 0.

### 6.3 Periods for the fixed-age profiles

The profiles use age at the start of the interval, in 5-year bands up to 80–84.

| Period | Intervals |
|---|---|
| Before | from the first count to the baseline |
| Quake interval | the interval that contains the quake |
| After, years 1–2 | the next two intervals |
| After, later | the remaining intervals (Tohoku years 3–5, Kumamoto 3–4) |

For Tohoku the quake interval ends 20 days after 3/11, so most of the moves show up in "after, years 1–2".

## 7. Uncertainty and validation

### Noise yardstick

For each group × 5-year band, we compute the mean ± 2 SD of the rate over the single pre-quake intervals. Only full-year intervals are used; the 0.75-year interval is excluded.

- A post-quake value outside this band is read as a real change.
- In Tohoku the target ages 0–14 and 20–39 have SDs of about 1–5 per 1,000.
- Kumamoto 15–29 is noisier, with SDs of 9–15.

### Flagged ages

The 1944–50 birth cohorts (the war-end dip next to the baby boom) make one-year residuals unreliable at the ages they pass through:

- 55–74 in the Tohoku window;
- 60–79 in the Kumamoto window.

These ages are shaded or marked ⚠ in the figures.

### Validation against reported migration (Kumamoto 2014–2020)

Reported net migration is computed from 1D-split in- and out-movers, with the same Lexis rule and denominators as the residual. Each cell is a municipality × cohort bin × year.

| | 1D + offset (4r) | 2D + offset (5r) |
|---|---|---|
| Correlation, all cells | 0.72 | 0.73 |
| SD of residual − reported, all cells (per 1,000) | 28.2 | 26.6 |
| SD, municipalities < 5k residents | 50.8 | 48.7 |
| SD, municipalities ≥ 50k residents | 8.5 | 7.7 |
| Correlation, whole municipality-years | 0.97 | 0.97 |

- **By group (4r):** the correlations are 0.83 (high damage), 0.56 (熊本市) and 0.70 (other), with mean differences of 0.3 per 1,000 or less.
- **Yearly totals** agree closely, e.g. 2014: −2,781 (residual) vs −2,779 (reported).
- **2D splits** reduce pre-quake noise by only about 5–15%, so the band-edge noise remains.

### What the residual also absorbs

Besides migration between municipalities, the residual also includes:

- moves to and from abroad;
- register corrections (職権記載・消除);
- fitting error.

In the Fukushima evacuation areas, evacuees who kept their registration are not migrants in the register. The residual therefore understates the real population loss there.

## 8. Current status

- **Default:** the 4r residual (1D `pclm` with the national offset for population; plain pclm for deaths) for both events, and the 3r direct rates for Kumamoto.
- **Sensitivity variants:**
  - 5r: the 2D population split, which gives a small, consistent gain.
  - 6r: no offset, 1D and 2D. Not yet executed, so there are no results.
- **Caches:**
  - `output/3r_pclm_cache.qs2`, `output/4r_pclm_cache.qs2` and `output/5r_pclm2d_cache.qs2`. Run 4r before 5r and 6r.
  - The 5r figure-8 fits are cached separately in `output/5r_pclm_kumamoto_2011_2026.qs2`.
  - Delete a cache to refit.
