# Origin

Vendored from the Bonsai serve repo (`professorpalmer/bonsai-ada-surgery`, commit 3628b6a, the state tagged
`bundle-20261004`) on 2026-10-04: `bonsai_layer.py`, `apicards.py`, `apicards_v2.py`, `apilint.py`, `sandbox_path.py`,
`fetch_runtime.ps1`, `wasi-python/`. The layer is model-agnostic by design and measured so (Bonsai: suite 17 -> 28/29 of
37; Mirai S: 13 -> 30 of 37, docs/REPORT.md). Changes for Mirai are made here and, when they are generic, offered back
to the Bonsai repo as plain patches. Nothing Mirai-specific goes the other way.

The env var the launcher uses for the key check is still `BONSAI_LAYER_KEY` (the module's name); renaming it is
cosmetic and not done.

2026-10-05 (E18, DECISIONS 21:10): diverges from the Bonsai copy in two places, measured here first: apilint reports
names looked up on a class or called on a fresh stdlib instance that the class does not have (with idiom hints), and
apicards triggers email, email.policy and email.parser on MIME requests, orders the task family before the generic
helpers and caps at 6 cards. To be offered back to the public layer with its own measurement if the MIME family moves.
