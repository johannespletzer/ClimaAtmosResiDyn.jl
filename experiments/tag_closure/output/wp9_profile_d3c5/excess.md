## Job `prof88_a`, node `hpdar07c05s08`, commit `d3c5e42f`

Timed block, ms per step: untagged 4.829, water 7.036, energy 5.609, both 14.094. Excess 6.277 ms; bytes per step excess 2204554. Samples: untagged 53611, water 44747, energy 57632, both 50478.

### By phase

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| other | 2.493 | 3.672 | 2.896 | 7.185 | 3.111 | 0.056 | 49.6% | 0 |
| implicit tendency | 0.593 | 0.995 | 0.839 | 2.542 | 1.301 | 0.032 | 20.7% | 539008 |
| explicit tendency | 0.323 | 0.481 | 0.393 | 1.592 | 1.041 | 0.024 | 16.6% | 769642 |

These rows hold 86.9% of the excess, 6.277 ms.

### By call

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| other | 2.493 | 3.672 | 2.896 | 7.185 | 3.111 | 0.056 | 49.6% | 0 |
| implicit tendency > macro expansion (implicit_tendency.jl) | 0.593 | 0.995 | 0.839 | 2.542 | 1.301 | 0.032 | 20.7% | 539008 |
| explicit tendency > macro expansion (remaining_tendency.jl) | 0.323 | 0.481 | 0.393 | 1.592 | 1.041 | 0.024 | 16.6% | 769642 |

These rows hold 86.9% of the excess, 6.277 ms.

### By tag entry

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| (not tag code) | 4.827 | 6.619 | 5.186 | 13.035 | 6.057 | 0.075 | 96.5% | 2018569 |

These rows hold 96.5% of the excess, 6.277 ms.

### By frame

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| (outside src) | 2.481 | 3.598 | 2.867 | 7.118 | 3.134 | 0.055 | 49.9% | 0 |
| utils/tracer_processes.jl:138 #142 | 0.000 | 0.000 | 0.000 | 1.238 | 1.238 | 0.019 | 19.7% | 435456 |
| utils/variable_manipulations.jl:242 #129 | 0.000 | 0.000 | 0.000 | 1.018 | 1.018 | 0.017 | 16.2% | 338688 |

These rows hold 85.9% of the excess, 6.277 ms.

## Job `prof88_b`, node `hpdar09c05s05`, commit `d3c5e42f`

Timed block, ms per step: untagged 6.993, water 10.018, energy 11.204, both 22.340. Excess 8.111 ms; bytes per step excess 2205370. Samples: untagged 20848, water 17582, energy 15625, both 19032.

### By phase

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| other | 3.611 | 5.191 | 5.787 | 11.417 | 4.050 | 0.147 | 49.9% | 0 |
| implicit tendency | 0.904 | 1.419 | 1.595 | 4.030 | 1.920 | 0.084 | 23.7% | 539008 |
| explicit tendency | 0.448 | 0.820 | 0.902 | 2.530 | 1.255 | 0.065 | 15.5% | 769642 |

These rows hold 89.1% of the excess, 8.111 ms.

### By call

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| other | 3.611 | 5.191 | 5.787 | 11.417 | 4.050 | 0.147 | 49.9% | 0 |
| implicit tendency > macro expansion (implicit_tendency.jl) | 0.904 | 1.419 | 1.595 | 4.030 | 1.920 | 0.084 | 23.7% | 539008 |
| explicit tendency > macro expansion (remaining_tendency.jl) | 0.447 | 0.820 | 0.901 | 2.530 | 1.255 | 0.065 | 15.5% | 769642 |

These rows hold 89.1% of the excess, 8.111 ms.

### By tag entry

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| (not tag code) | 6.991 | 9.413 | 10.334 | 20.665 | 7.910 | 0.198 | 97.5% | 2026609 |

These rows hold 97.5% of the excess, 8.111 ms.

### By frame

| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| (outside src) | 3.591 | 5.115 | 5.721 | 11.296 | 4.051 | 0.147 | 49.9% | 0 |
| utils/tracer_processes.jl:138 #142 | 0.000 | 0.000 | 0.000 | 1.998 | 1.998 | 0.048 | 24.6% | 435456 |
| utils/variable_manipulations.jl:242 #129 | 0.000 | 0.000 | 0.000 | 1.634 | 1.634 | 0.044 | 20.1% | 338688 |

These rows hold 94.7% of the excess, 8.111 ms.

## Keys in the 80% rows of every job (smallest share over the jobs)

| table | key | share |
|:--|:--|--:|
| tag_entry | (not tag code) | 96.5% |
| frame | (outside src) | 49.9% |
| phase | other | 49.6% |
| call | other | 49.6% |
| call | implicit tendency > macro expansion (implicit_tendency.jl) | 20.7% |
| phase | implicit tendency | 20.7% |
| frame | utils/tracer_processes.jl:138 #142 | 19.7% |
| frame | utils/variable_manipulations.jl:242 #129 | 16.2% |
| phase | explicit tendency | 15.5% |
| call | explicit tendency > macro expansion (remaining_tendency.jl) | 15.5% |
