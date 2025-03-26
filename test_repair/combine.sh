#!/bin/bash

python3 compare_platforms.py \
  --xdn-output xdn_results/k6_metrics.csv \
  --worker-output worker_results/k6_metrics.csv \
  --crash-time 20 \
  --output platform_comparison.png