| family | item | seed | ML2b mirai-raw | ML2b mirai-layer | ML2e-low mirai-raw | ML2e-low mirai-layer | moved |
| --- | --- | ---: | :---: | :---: | :---: | :---: | --- |
| coding | suite-tar-01 | 1 | fail | fail | fail | pass | mirai-layer: fail->pass |
| coding | suite-tar-01 | 2 | pass | fail | fail | pass | mirai-raw: pass->fail; mirai-layer: fail->pass |
| coding | suite-tar-01 | 3 | fail | fail | fail | pass | mirai-layer: fail->pass |
| coding | suite-tar-01 | 4 | fail | fail | fail | pass | mirai-layer: fail->pass |
| coding | xfer-mime-01 | 1 | fail | fail | pass | fail | mirai-raw: fail->pass |
| coding | xfer-mime-01 | 2 | fail | fail | pass | fail | mirai-raw: fail->pass |
| coding | xfer-mime-01 | 3 | fail | fail | pass | fail | mirai-raw: fail->pass |
| coding | xfer-mime-01 | 4 | fail | fail | pass | fail | mirai-raw: fail->pass |
| coding | xfer-zip-01 | 1 | pass | fail | pass | pass | mirai-layer: fail->pass |
| coding | xfer-zip-01 | 2 | pass | pass | fail | pass | mirai-raw: pass->fail |
| coding | xfer-zip-01 | 3 | pass | pass | fail | pass | mirai-raw: pass->fail |
| coding | xfer-zip-01 | 4 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | digits | 1 | fail | pass | fail | pass |  |
| computation | digits | 2 | fail | pass | fail | pass |  |
| computation | digits | 3 | fail | pass | fail | pass |  |
| computation | knapsack | 1 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | knapsack | 2 | pass | pass | fail | pass | mirai-raw: pass->fail |
| computation | knapsack | 3 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | lcs | 1 | fail | pass | fail | pass |  |
| computation | lcs | 2 | fail | pass | fail | pass |  |
| computation | lcs | 3 | fail | pass | fail | pass |  |
| computation | sales | 1 | fail | pass | fail | pass |  |
| computation | sales | 2 | pass | pass | pass | pass |  |
| computation | sales | 3 | pass | pass | pass | pass |  |
| computation | weblog | 1 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | weblog | 2 | fail | pass | pass | pass | mirai-raw: fail->pass |
| computation | weblog | 3 | pass | pass | fail | pass | mirai-raw: pass->fail |
| workspace | chain | 1 | pass | pass | - | - |  |
| workspace | chain | 2 | pass | pass | - | - |  |
| workspace | copy | 1 | pass | pass | - | - |  |
| workspace | copy | 2 | pass | pass | - | - |  |
| workspace | dedupeH | 1 | pass | pass | - | - |  |
| workspace | dedupeH | 2 | pass | pass | - | - |  |
| workspace | invoiceH | 1 | pass | pass | - | - |  |
| workspace | invoiceH | 2 | pass | pass | - | - |  |
| workspace | ledgerH | 1 | pass | pass | - | - |  |
| workspace | ledgerH | 2 | pass | pass | - | - |  |

| run / arm | coding | computation | workspace | total | tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| ML2b mirai-raw | 4/12 | 4/15 | 10/10 | 18/37 | 508,451 |
| ML2b mirai-layer | 3/12 | 15/15 | 10/10 | 28/37 | 393,918 |
| ML2e-low mirai-raw | 6/12 | 6/15 | 0/10 | 12/27 | 593,619 |
| ML2e-low mirai-layer | 8/12 | 15/15 | 0/10 | 23/27 | 379,993 |

ML2b: rescues 12, losses 2 (mirai-layer vs mirai-raw)

ML2e-low: rescues 15, losses 4 (mirai-layer vs mirai-raw)
