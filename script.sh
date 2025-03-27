#!/bin/bash

# k6 run tes.js --env SERVICE=webkv --env CONSISTENCY=LINEARIZABILITY
k6 run tes.js --env SERVICE=webkv --env CONSISTENCY=EVENTUAL --env BASE_URL='http://localhost:2302/api/kv'

#  xdn service info webkv