# readboj 0.2.0 initial public release — 25 October 2026

The public repository starts from one clean initial commit under Chartwell Macro.
No history from the earlier development repository is imported. Support, bug
reports and security concerns go to chartwellmacro@gmail.com.

## Runtime and data

The original statistics API, bulk and Tankan implementations are preserved.
The Outlook release includes saved numeric history, bounded raw retrieval,
atomic incremental updates and calendar-aware maintenance.

The initial public release also repairs saved-content checksum portability
between R 4.5 and R 4.6. Checksums use explicit serialization version 2 and
canonical vector copies. Readers first verify the ordinary explicit-v2 digest,
then the canonical representation where needed. Neither path accepts an
unchecked object. Maintenance state and persisted identity receipts use the
same canonical hashing contract.

Windows updater locks use a read-only process query. Signal-zero probing is
reserved for Unix, because Windows treats pskill calls as process termination.
The extraction deadline fixture uses an external shell process with the same
hard deadline and typed timeout/parse-error assertions.

The 67,640-byte numeric bundle retains all 4,142 rows, 5 explicit missing values,
74 editions (October 2000 to July 2026), dates, types, identities and source
provenance. Every non-checksum field and attribute is identical to the earlier
bundle. The executable parser fingerprint is unchanged.

- File SHA256: `4a5d9af94f134e8879c34e4e610e48354a9686e0904bdc4830a969d623c493fc`
- Content SHA256: `1933f6789e21b0428573cdb0ffa345e239385aa5355dddac34ade63991d9984c`

An actual pre-fix bundle is retained as a regression fixture. Legacy checksums
remain accepted where their original representation can be reproduced. On a
runtime that cannot reproduce a legacy checksum, the existing typed fallback
warning selects the valid package baseline and preserves the older stored
object bytes. New snapshots and maintenance records use canonical checksums.

## Release gates

The initial public source must pass the full local suite, independent review,
and the GitHub R/OS matrix before replacing the initial publication state.
Tests cover unchanged values/provenance, both serialization options, actual
legacy data, corruption rejection, maintenance persistence, live/dead Windows
process lookup and the existing update, concurrency and deadline workflows.
Current run evidence is available from the repository's GitHub Actions page.

Source: Bank of Japan. Exact source URLs/hashes and semantic notes accompany the
tables. MIT applies to package code. Official source terms govern data reuse;
see `inst/NOTICE/outlook-source.txt` and `docs/outlook.md`.
