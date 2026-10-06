| family | item | seed | ML1 mirai-raw | ML1 mirai-layer | ML2 mirai-raw | ML2 mirai-layer | moved |
| --- | --- | ---: | :---: | :---: | :---: | :---: | --- |
| coding | suite-tar-01 | 1 | fail | pass | fail | pass |  |
| coding | suite-tar-01 | 2 | fail | pass | fail | fail | mirai-layer: pass->fail |
| coding | suite-tar-01 | 3 | fail | pass | fail | pass |  |
| coding | suite-tar-01 | 4 | fail | fail | fail | fail |  |
| coding | xfer-mime-01 | 1 | fail | fail | fail | fail |  |
| coding | xfer-mime-01 | 2 | fail | fail | fail | fail |  |
| coding | xfer-mime-01 | 3 | fail | fail | fail | fail |  |
| coding | xfer-mime-01 | 4 | fail | fail | fail | fail |  |
| coding | xfer-zip-01 | 1 | fail | pass | pass | pass | mirai-raw: fail->pass |
| coding | xfer-zip-01 | 2 | fail | pass | pass | pass | mirai-raw: fail->pass |
| coding | xfer-zip-01 | 3 | fail | pass | pass | pass | mirai-raw: fail->pass |
| coding | xfer-zip-01 | 4 | pass | pass | fail | pass | mirai-raw: pass->fail |
| computation | digits | 1 | fail | pass | fail | pass |  |
| computation | digits | 2 | fail | pass | fail | pass |  |
| computation | digits | 3 | fail | pass | fail | pass |  |
| computation | knapsack | 1 | fail | pass | fail | pass |  |
| computation | knapsack | 2 | pass | pass | pass | pass |  |
| computation | knapsack | 3 | pass | pass | fail | pass | mirai-raw: pass->fail |
| computation | lcs | 1 | fail | pass | fail | pass |  |
| computation | lcs | 2 | fail | pass | fail | pass |  |
| computation | lcs | 3 | fail | pass | fail | pass |  |
| computation | sales | 1 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | sales | 2 | pass | pass | pass | pass |  |
| computation | sales | 3 | fail | pass | fail | pass |  |
| computation | weblog | 1 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | weblog | 2 | fail | pass | fail | pass |  |
| computation | weblog | 3 | pass | pass | pass | pass |  |
| workspace | chain | 1 | pass | pass | pass | pass |  |
| workspace | chain | 2 | pass | pass | pass | pass |  |
| workspace | copy | 1 | fail | fail | fail | fail |  |
| workspace | copy | 2 | pass | pass | pass | pass |  |
| workspace | dedupeH | 1 | pass | pass | pass | pass |  |
| workspace | dedupeH | 2 | pass | pass | pass | pass |  |
| workspace | invoiceH | 1 | fail | fail | fail | fail |  |
| workspace | invoiceH | 2 | pass | pass | pass | pass |  |
| workspace | ledgerH | 1 | pass | pass | pass | pass |  |
| workspace | ledgerH | 2 | pass | pass | pass | pass |  |

| run / arm | coding | computation | workspace | total | tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| ML1 mirai-raw | 1/12 | 4/15 | 8/10 | 13/37 | 488,443 |
| ML1 mirai-layer | 7/12 | 15/15 | 8/10 | 30/37 | 381,391 |
| ML2 mirai-raw | 3/12 | 5/15 | 8/10 | 16/37 | 486,306 |
| ML2 mirai-layer | 6/12 | 15/15 | 8/10 | 29/37 | 376,673 |

ML1: rescues 17, losses 0 (mirai-layer vs mirai-raw)

ML2: rescues 13, losses 0 (mirai-layer vs mirai-raw)
