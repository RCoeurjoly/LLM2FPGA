| strategy | family | raw bits/w | scales | zero % | top1 | top1 match | top5 overlap | top10 overlap | float top1 rank | norm RMSE | base3 words | promote |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| int8_per_tensor | int8 | 8.000 | 1 | 1.5 | 213 | yes | 5 | 10 | 1 | 0.0111 |  | yes |
| ternary_per_row_t0.25_least_squares | ternary | 1.585 | 10000 | 15.7 | 213 | yes | 2 | 4 | 1 | 0.5240 | 32000 | no |
| ternary_per_row_t0.25_mean_abs | ternary | 1.585 | 10000 | 15.7 | 213 | yes | 2 | 4 | 1 | 0.5371 | 32000 | no |
| ternary_per_row_t1_least_squares | ternary | 1.585 | 10000 | 57.4 | 98 | no | 4 | 6 | 8 | 0.4523 | 32000 | no |
| ternary_per_row_t1_mean_abs | ternary | 1.585 | 10000 | 57.4 | 98 | no | 3 | 5 | 3 | 0.5853 | 32000 | no |
| ternary_per_row_t0.75_least_squares | ternary | 1.585 | 10000 | 44.9 | 9927 | no | 3 | 5 | 6 | 0.4315 | 32000 | no |
| ternary_per_row_t0.75_mean_abs | ternary | 1.585 | 10000 | 44.9 | 9927 | no | 3 | 5 | 6 | 0.5306 | 32000 | no |
| ternary_global_t0.75_least_squares | ternary | 1.585 | 1 | 45.1 | 9927 | no | 3 | 6 | 7 | 0.4414 | 32000 | no |
| ternary_global_t0.75_mean_abs | ternary | 1.585 | 1 | 45.1 | 9927 | no | 3 | 6 | 7 | 0.5391 | 32000 | no |
| ternary_per_row_grid_lsq | ternary | 1.585 | 10000 | 45.5 | 9163 | no | 3 | 6 | 9 | 0.4325 | 32000 | no |
| ternary_global_t0.5_least_squares | ternary | 1.585 | 1 | 31.1 | 721 | no | 2 | 5 | 6 | 0.4656 | 32000 | no |
| ternary_global_t0.5_mean_abs | ternary | 1.585 | 1 | 31.1 | 721 | no | 2 | 5 | 6 | 0.5148 | 32000 | no |
| ternary_per_row_t0.5_least_squares | ternary | 1.585 | 10000 | 30.8 | 8365 | no | 2 | 7 | 7 | 0.4595 | 32000 | no |
| ternary_per_row_t0.5_mean_abs | ternary | 1.585 | 10000 | 30.8 | 9163 | no | 2 | 6 | 8 | 0.5102 | 32000 | no |
| ternary_global_t1_least_squares | ternary | 1.585 | 1 | 57.5 | 98 | no | 2 | 3 | 11 | 0.4575 | 32000 | no |
| ternary_global_t1_mean_abs | ternary | 1.585 | 1 | 57.5 | 98 | no | 2 | 3 | 11 | 0.5883 | 32000 | no |
| ternary_global_t1.25_least_squares | ternary | 1.585 | 1 | 68.1 | 15 | no | 2 | 4 | 21 | 0.5125 | 32000 | no |
| ternary_global_t1.25_mean_abs | ternary | 1.585 | 1 | 68.1 | 15 | no | 2 | 4 | 21 | 0.6533 | 32000 | no |
| ternary_global_t0.25_least_squares | ternary | 1.585 | 1 | 15.9 | 2198 | no | 1 | 2 | 15 | 0.5299 | 32000 | no |
| ternary_global_t0.25_mean_abs | ternary | 1.585 | 1 | 15.9 | 2198 | no | 1 | 2 | 15 | 0.5419 | 32000 | no |
| ternary_global_t0_mean_abs | ternary | 1.585 | 1 | 0.0 | 8927 | no | 0 | 2 | 31 | 0.6081 | 32000 | no |
| ternary_global_t0_least_squares | ternary | 1.585 | 1 | 0.0 | 8927 | no | 0 | 2 | 31 | 0.6081 | 32000 | no |
