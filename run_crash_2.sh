#!/bin/bash

TEST_DURATION=60
FIRST_CRASH_TIME=20
SECOND_CRASH_TIME=40
OUTPUT_DIR="Crash2_test_4"
K6_OUTPUT_FILE="k6_metrics.csv"
REPLICA_PORTS=(2302 2308 2309)
FIRST_CRASH_PORT=2302
SECOND_CRASH_PORT=2308
WARMUP_REQUESTS=200

if [ ! -f "load_crash_2.js" ]; then
    echo "ERROR: load_crash_2.js not found."
    exit 1
fi

sed -i "s/const FIRST_CRASH_TIME_SECONDS = [0-9]*;/const FIRST_CRASH_TIME_SECONDS = $FIRST_CRASH_TIME;/" load_crash_2.js
sed -i "s/const SECOND_CRASH_TIME_SECONDS = [0-9]*;/const SECOND_CRASH_TIME_SECONDS = $SECOND_CRASH_TIME;/" load_crash_2.js
sed -i "s/const FIRST_CRASHED_PORT = [0-9]*;/const FIRST_CRASHED_PORT = $FIRST_CRASH_PORT;/" load_crash_2.js
sed -i "s/const SECOND_CRASHED_PORT = [0-9]*;/const SECOND_CRASHED_PORT = $SECOND_CRASH_PORT;/" load_crash_2.js
echo "K6 script crashes: $FIRST_CRASH_TIME and $SECOND_CRASH_TIME seconds"

mkdir -p $OUTPUT_DIR

ACTIVE_REPLICAS=()

for port in "${REPLICA_PORTS[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/api/books" -H "XDN: bookcatalog")
    if [ $? -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
        echo "Replica on port $port is active"
        ACTIVE_REPLICAS+=($port)
    else
        echo "Problem on port $port (HTTP status: $HTTP_CODE)"
    fi
done

if [ ${#ACTIVE_REPLICAS[@]} -eq 0 ]; then
    echo "ERROR: No active replicas found. Exiting."
    exit 1
fi

for CRASH_PORT in $FIRST_CRASH_PORT $SECOND_CRASH_PORT; do
    if [[ ! " ${ACTIVE_REPLICAS[*]} " =~ " ${CRASH_PORT} " ]]; then
        echo "The port scheduled for crash ($CRASH_PORT) is not active"
        exit 1
    fi
done

export ACTIVE_REPLICAS="[${ACTIVE_REPLICAS[*]}]"
echo "Active replicas: $ACTIVE_REPLICAS"

echo -e "\n=== Starting Warm-up Phase ==="
for port in "${ACTIVE_REPLICAS[@]}"; do
    echo "Warming up replica on port $port..."
    
    start_time=$(date +%s.%N)
    
    for ((i=1; i<=$WARMUP_REQUESTS; i++)); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/api/books" -H "XDN: bookcatalog")
        
        if [ $((i % 100)) -eq 0 ]; then
            echo "  Progress: $i/$WARMUP_REQUESTS requests completed"
        fi
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    rps=$(echo "$WARMUP_REQUESTS / $duration" | bc)
    
    echo " Replica $port: warm-up completed ($WARMUP_REQUESTS requests in $(printf "%.2f" $duration) seconds, $(printf "%.2f" $rps) req/sec)"
done

sleep 2
echo -e "=== Warm-up Phase Completed ===\n"

crash_replica() {
    local port=$1
    
    echo "$(date +%H:%M:%S) Crashing replica on port: $port"
    
    fuser -k $port/tcp
    
    if [ $? -eq 0 ]; then
        echo "$(date +%H:%M:%S) Successfully crashed replica on port $port"
    else
        echo "$(date +%H:%M:%S) Failed to crash replica on port $port"
    fi
}

echo "$FIRST_CRASH_TIME $SECOND_CRASH_TIME" > $OUTPUT_DIR/crash_times.txt

echo -e "=== Starting Load Test (Duration: ${TEST_DURATION}s) ===\n"

k6 run --out csv=$OUTPUT_DIR/$K6_OUTPUT_FILE load_crash_2.js &
K6_PID=$!
TEST_START_TIME=$(date +%s)

# First crash
(
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - TEST_START_TIME))
    SLEEP_TIME=$((FIRST_CRASH_TIME - ELAPSED))
    
    if [ $SLEEP_TIME -lt 0 ]; then
        SLEEP_TIME=0
    fi
    
    sleep $SLEEP_TIME
    
    CRASH_EXACT_TIME=$(date +%s)
    CRASH_ELAPSED=$((CRASH_EXACT_TIME - TEST_START_TIME))
    echo "Actual first crash time is $CRASH_ELAPSED seconds into the test"
    
    crash_replica $FIRST_CRASH_PORT
) &

# Second crash
(
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - TEST_START_TIME))
    SLEEP_TIME=$((SECOND_CRASH_TIME - ELAPSED))
    
    if [ $SLEEP_TIME -lt 0 ]; then
        SLEEP_TIME=0
    fi
    
    sleep $SLEEP_TIME
    
    CRASH_EXACT_TIME=$(date +%s)
    CRASH_ELAPSED=$((CRASH_EXACT_TIME - TEST_START_TIME))
    echo "Actual second crash time is $CRASH_ELAPSED seconds into the test"
    
    crash_replica $SECOND_CRASH_PORT
) &

echo "Test is running..."
wait $K6_PID
echo -e "\n=== Load Test Completed ===\n"

echo "Generating throughput visualization"
python3 crash2.py --k6-output $OUTPUT_DIR/$K6_OUTPUT_FILE --crash-times $OUTPUT_DIR/crash_times.txt --output $OUTPUT_DIR/throughput.png

echo -e "\n=== Test completed successfully! ==="