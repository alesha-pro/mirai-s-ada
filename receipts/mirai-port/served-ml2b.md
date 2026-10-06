# Served receipt from `logs/product.log`

```
requests with >= 16 generated tokens: 478 (of 481 tasks seen)
decode tok/s      : n=478 median 73.9 p10 61.8 p90 82.6
prompt tok/s      : n=264 median 911.4 p10 525.9 p90 1066.7 (prompts >= 256 tokens)
draft acceptance  : n=478 median 83.2 p10 63.5 p90 97.3 %   mean draft len n=478 median 2.7 p10 2.3 p90 3.0
pooled acceptance : 82.8 % (564918 / 682156 drafted tokens)
by generation length:
     16-256   tokens: decode n=202 median 70.9 p10 61.6 p90 80.8; acceptance n=202 median 78.7 p10 60.5 p90 95.2 %
    256-2048  tokens: decode n=185 median 75.1 p10 59.7 p90 83.0; acceptance n=185 median 84.7 p10 63.8 p90 97.0 %
   2048-8192  tokens: decode n=59 median 79.1 p10 68.1 p90 83.3; acceptance n=59 median 93.1 p10 71.2 p90 97.9 %
   8192-inf   tokens: decode n=32 median 78.0 p10 65.5 p90 82.6; acceptance n=32 median 87.5 p10 67.3 p90 99.0 %
total generated   : 905,969 tokens in 3.45 h of decode time = 73.0 tok/s wall-pooled
```
