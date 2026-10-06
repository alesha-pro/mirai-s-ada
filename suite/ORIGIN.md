# Origin

Vendored from the Bonsai serve repo (`professorpalmer/bonsai-ada-surgery`, commit 3628b6a) on 2026-10-04, unchanged.
The suite runs against any OpenAI-compatible endpoint and pairs two endpoints request by request; it needs the
`layer/` sandbox runtime (`layer\fetch_runtime.ps1`) to grade coding tasks. The Mirai S scoreboards live in
`bench/ML1/`; the Bonsai ones stay in the Bonsai repo's `suite/README.md`.
