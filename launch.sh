#!/bin/bash

export XDN_CONTROL_PLANE=localhost
xdn launch webkv --image=fadhilkurnia/xdn-webkv --state=/app/data/ --deterministic=true --consistency=EVENTUAL