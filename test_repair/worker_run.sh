#!/bin/bash

TEST_DURATION=60  
CRASH_TIME=20     
OUTPUT_DIR="worker_results_2"
K6_OUTPUT_FILE="k6_metrics.csv"
WORKER_PORT=2302
CRASH_PORT=2302   
WARMUP_REQUESTS=200  

if [ ! -f "worker_load_test.js" ]; then
    echo "ERROR: worker_load_test.js not found."
    exit 1
fi

sed -i "s/const CRASH_TIME_SECONDS = [0-9]*;/const CRASH_TIME_SECONDS = $CRASH_TIME;/" worker_load_test.js
echo "K6 script crash time set to $CRASH_TIME seconds"

mkdir -p $OUTPUT_DIR

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WORKER_PORT/api/books" -H "XDN: bookcatalog")
if [ $? -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
    echo "Worker on port $WORKER_PORT is active"
else
    echo "ERROR: Worker on port $WORKER_PORT is not active (HTTP status: $HTTP_CODE)"
    exit 1
fi

echo -e "\n=== Starting Worker Warm-up Phase ==="
echo "Warming up Worker on port $WORKER_PORT..."

start_time=$(date +%s.%N)

for ((i=1; i<=$WARMUP_REQUESTS; i++)); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WORKER_PORT/api/books" -H "XDN: bookcatalog")
    
    if [ $((i % 100)) -eq 0 ]; then
        echo "  Progress: $i/$WARMUP_REQUESTS requests completed"
    fi
done

end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
rps=$(echo "$WARMUP_REQUESTS / $duration" | bc)

echo " Worker warm-up completed ($WARMUP_REQUESTS requests in $(printf "%.2f" $duration) seconds, $(printf "%.2f" $rps) req/sec)"

sleep 2
echo -e "=== Warm-up Phase Completed ===\n"

crash_worker() {
    local port=$1
    
    echo "$(date +%H:%M:%S) Crashing worker on port: $port"
    
    fuser -k $port/tcp
    
    if [ $? -eq 0 ]; then
        echo "$(date +%H:%M:%S) Successfully crashed worker on port $port"
    else
        echo "$(date +%H:%M:%S) Failed to crash worker on port $port"
    fi
}

echo $CRASH_TIME > $OUTPUT_DIR/crash_times.txt

echo -e "=== Starting Worker Load Test (Duration: ${TEST_DURATION}s) ===\n"

k6 run --out csv=$OUTPUT_DIR/$K6_OUTPUT_FILE worker_load_test.js &
K6_PID=$!
TEST_START_TIME=$(date +%s)

(
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - TEST_START_TIME))
    SLEEP_TIME=$((CRASH_TIME - ELAPSED))
    
    if [ $SLEEP_TIME -lt 0 ]; then
        SLEEP_TIME=0
    fi
    
    sleep $SLEEP_TIME
    
    CRASH_EXACT_TIME=$(date +%s)
    CRASH_ELAPSED=$((CRASH_EXACT_TIME - TEST_START_TIME))
    echo "Actual crash time is $CRASH_ELAPSED seconds into the test"
    
    crash_worker $CRASH_PORT
) &

echo "Worker test is running..."
wait $K6_PID
echo -e "\n=== Worker Load Test Completed ===\n"

echo "Generating Worker throughput visualization"
python3 worker_visualize_results.py --k6-output $OUTPUT_DIR/$K6_OUTPUT_FILE --crash-times $OUTPUT_DIR/crash_times.txt --output $OUTPUT_DIR/throughput.png

echo -e "\n=== Worker test completed successfully! ==="
