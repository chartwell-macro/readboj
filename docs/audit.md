# Official-source and R-package audit

Audit date: 2026-08-02 (Australia/Sydney)

## Decision

`bojapi` 0.1.0 is the strongest existing R client and is the reference for the
new 2026 API. It passed representative exact-code retrieval, null preservation,
250-code batching, cursor pagination and typed-error review. It failed the full
provider gate materially: no official bulk catalogue/files, no Tankan dated
release assets, no raw-response snapshot/hash contract, normalized metadata
caches rather than replayable source bytes, one-language normalization of the
bilingual Japanese response, and no hard row/byte bound for the approximately
99 MB Tankan JSON catalogue. `bbk` 0.12.0 and legacy `BOJ` 0.3.4 cover less.

The selected implementation is therefore standalone `readboj`, not a cosmetic
wrapper. It retains the exact official body/file bytes and semantic identity,
uses the official API without an aggregator fallback, and adds the missing
official surfaces.

Registry/source artefacts pinned during the decision gate were CRAN `bojapi`
0.1.0 (2026-07-24; source SHA-256
`9604c6f08e380debc9f85f053e6406d551a8ef15427de7dcc384c92bfde90236`),
CRAN `bbk` 0.12.0 (2026-07-10; source SHA-256
`4b182097d454520c226109e0f4a83800bd67c30065dab4641ed64adfdeaa55c0`),
and CRAN `BOJ` 0.3.4 (2025-01-19; source SHA-256
`dfeff6fa4f87fd676d9bfa6d25001e8da38018e44319c7321a655663879c8777`).
DBnomics is an aggregator cross-check only and is never a fallback source.

## Coverage matrix

The affirmative machine-readable matrix in `docs/coverage-matrix.csv` records
each route/file family, observed catalogue size, dimensions/frequencies,
historical range, update/revision behavior, owning parser, live canary and the
specific upstream capability that is genuinely unavailable. It is the
normative coverage inventory; the summary below highlights the integration
boundary.

| Surface | Official identity | readboj 0.1.0 | Gap / truth condition |
|---|---|---|---|
| Database catalogue | 50 codes in API manual dated 2026-02-18 | Versioned bilingual registry | Manual changes require package update |
| Metadata | `getMetadata` | Bilingual CP932/UTF-8 parse, raw cache, bounded chunk search | `CO` eager load requires explicit opt-in |
| Exact observations | `getDataCode` | 250-code batching, exact cursor, null rows, hashes | Latest revised history; no as-of parameter |
| Layer observations | `getDataLayer` | Exact cursor, wildcards, page/cell bounds | Official 1,250 pre-frequency layer cap remains |
| Policy and rates | IR01-IR04, FM01-FM09 | Full statistical API coverage | MPM decisions are separate HTML/PDF documents |
| Money and credit | MD01-MD14, LA01-LA05 | Full statistical API coverage | No automatic splicing across discontinued codes |
| Balance sheets | BS01-BS02 and related OB databases | Full statistical API coverage | Published series breaks remain distinct |
| FX | FM08-FM09 | Daily/monthly/reference series | Reference rates are not executable prices |
| Tankan long-run | CO database | Exact retrieval; disk-backed bounded search | Latest revised series, not survey vintages |
| Tankan releases | Dated comprehensive-data archive, 2000 onward | Release/asset discovery, exact download/hash | Workbooks retained, arbitrary table inference out of scope |
| Bulk | Official download catalogue (16 English ZIP links observed) | Catalogue, exact download/hash, bounded ZIP/CSV parse | Selected latest files only; prior FOF by BoJ request |
| Revisions/vintages | API/bulk `LAST_UPDATE`; dated Tankan assets | Immutable local observations plus exact dated assets | Local snapshots are not labelled official first releases |

## Representative evidence

The live audit used official endpoints in English and Japanese. `FM08/FXERM07`
returned the same series identity in both languages and January-June 2026
values. Raw response SHA-256 values captured during the gate were
`2fbd3ebabdf2e190eef94cb2a2d2fd86a2b576956ed8ea45d96d9460b86e819f`
(data), `7a1ccdcfa075cc7c64b7fb1efc6c76923708750bb13d0a8dc308cd5bbd3ca352`
(English metadata) and
`49f4b3cafaf73f3bb317a25b93a69e149192084e20a8df298225eafa1a6d8d12`
(Japanese metadata). The API response `DATE` is volatile; readboj therefore
reports both raw SHA-256 and a semantic JSON SHA-256 excluding only `DATE`.

Observed metadata series counts included IR01 2, FM01 4, MD01 14, MD02 154,
BS01 38, FM08 58, LA01 3,599 and CO 166,513. CO English CSV was about 59.6 MB
decompressed; JSON was about 99.1 MB. A live MD10 layer request returned 250
series with `NEXTPOSITION=255`; following exactly returned another 250 and
`NEXTPOSITION=507`, proving cursors are not inferred offsets.

Official bulk sample SHA-256 values on the audit date were:
`cgpi_m_en.zip` `f242b28205015dd29923e7ef9d718c3a2a564baced09696b7228ba9c45b37d92`,
`fof.zip` `030413173011521e6f0c7548ddf207dfcb732170f56002932717b97bbb28c854`,
`co.zip` `e7cda21f175299c75ed93e8eb97d0f7bb034850340109fa1f25af3f253aed082`,
and `bp_m_en.zip` `4d20df50afc676526e2e6724d7ce6173c3f29d1380c35b7216bbfdb49892ccb4`.

## Sources

- API manual: <https://www.stat-search.boj.or.jp/info/api_manual_en.pdf>
- API notice: <https://www.stat-search.boj.or.jp/info/api_notice_en.pdf>
- Bulk catalogue: <https://www.stat-search.boj.or.jp/info/dload_en.html>
- Tankan archive: <https://www.boj.or.jp/en/statistics/tk/zenyo/index.htm>
- Copyright: <https://www.boj.or.jp/en/about/copyright.htm>
- CRAN bojapi: <https://cran.r-project.org/package=bojapi>
- CRAN bbk: <https://cran.r-project.org/package=bbk>
- CRAN BOJ: <https://cran.r-project.org/package=BOJ>
