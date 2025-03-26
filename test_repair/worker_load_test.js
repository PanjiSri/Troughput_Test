import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';

export const options = {
    // scenarios: {
    //     constant_vus: {
    //         executor: 'constant-vus',
    //         vus: 1,
    //         duration: '60s',
    //     },
    // },
    // systemTags: ['scenario', 'status', 'method', 'url'],

    scenarios: {
        constant_load: {
            executor: 'constant-arrival-rate',
            rate: 200,
            timeUnit: '1s',
            duration: '60s',
            preAllocatedVUs: 50,
            maxVUs: 100,
        },
    },
    systemTags: ['scenario', 'status', 'method', 'url'],
};

const CRASH_TIME_SECONDS = 20;
const CRASHED_PORT = 2302;

const ALL_REPLICAS = [2302];
const ACTIVE_REPLICAS = [];

let testStartTime = null;

export default function () {
    if (testStartTime === null) {
        testStartTime = new Date().getTime();
    }
    
    const currentTime = Math.floor((new Date().getTime() - testStartTime) / 1000);
    
    let availablePorts;
    if (currentTime < CRASH_TIME_SECONDS) {
        availablePorts = ALL_REPLICAS;
    } else {
        availablePorts = ACTIVE_REPLICAS;
        if (availablePorts.length === 0) {
            console.log(`time=${currentTime},status=0,duration=0,platform=Worker`);
            return;
        }
    }
    
    const selectedPort = availablePorts[Math.floor(Math.random() * availablePorts.length)];
    const url = `http://localhost:${selectedPort}/api/books`;
    
    const params = {
        headers: {
            'XDN': 'bookcatalog',
            'Platform': 'Worker',
        },
    };  

    const response = http.get(url, params);
    
    check(response, {
        'status is 200': (r) => r.status === 200,
    });
    
    console.log(`time=${currentTime},status=${response.status},duration=${response.timings.duration},platform=Worker`);
}
