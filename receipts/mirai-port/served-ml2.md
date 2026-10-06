# Served receipt from `logs/product.log`

```
requests with >= 16 generated tokens: 525 (of 527 tasks seen)
decode tok/s      : n=525 median 74.4 p10 63.4 p90 82.9
prompt tok/s      : n=326 median 700.4 p10 544.3 p90 816.9 (prompts >= 256 tokens)
draft acceptance  : n=525 median 83.3 p10 64.0 p90 97.9 %   mean draft len n=525 median 2.7 p10 2.3 p90 3.0
pooled acceptance : 83.5 % (592749 / 709997 drafted tokens)
by generation length:
     16-256   tokens: decode n=222 median 72.8 p10 62.2 p90 82.6; acceptance n=222 median 82.5 p10 64.3 p90 97.1 %
    256-2048  tokens: decode n=199 median 73.1 p10 63.3 p90 83.1; acceptance n=199 median 79.9 p10 62.2 p90 97.5 %
   2048-8192  tokens: decode n=73 median 80.8 p10 67.7 p90 83.0; acceptance n=73 median 94.1 p10 69.4 p90 99.1 %
   8192-inf   tokens: decode n=31 median 76.7 p10 66.0 p90 82.7; acceptance n=31 median 85.5 p10 66.7 p90 99.0 %
total generated   : 947,756 tokens in 3.52 h of decode time = 74.7 tok/s wall-pooled
```
