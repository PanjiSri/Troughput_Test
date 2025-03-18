import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';

export const options = {
    //PARALLEL
    scenarios: {
        constant_load: {
            executor: 'constant-arrival-rate',
            rate: 500,
            timeUnit: '1s',
            duration: '60s',
            preAllocatedVUs: 100,
            maxVUs: 200,
        },
    },
    systemTags: ['scenario', 'status', 'method', 'url'],

    // scenarios: {
    //     constant_vus: {
    //         executor: 'constant-vus',
    //         vus: 1,               
    //         duration: '60s',      
    //     },
    // },
    // systemTags: ['scenario', 'status', 'method', 'url'],
};

const FIRST_CRASH_TIME_SECONDS = 20;
const SECOND_CRASH_TIME_SECONDS = 40;
const FIRST_CRASHED_PORT = 2302;
const SECOND_CRASHED_PORT = 2308;

const ALL_REPLICAS = [2302, 2308, 2309];
const AFTER_FIRST_CRASH = [2308, 2309];
const AFTER_SECOND_CRASH = [2309];

let testStartTime = null;

export default function () {
    if (testStartTime === null) {
        testStartTime = new Date().getTime();
    }
    
    const currentTime = Math.floor((new Date().getTime() - testStartTime) / 1000);
    
    let availablePorts;
    if (currentTime < FIRST_CRASH_TIME_SECONDS) {
        availablePorts = ALL_REPLICAS;
    } else if (currentTime < SECOND_CRASH_TIME_SECONDS) {
        availablePorts = AFTER_FIRST_CRASH;
    } else {
        availablePorts = AFTER_SECOND_CRASH;
    }
    
    const selectedPort = availablePorts[Math.floor(Math.random() * availablePorts.length)];
    const url = `http://localhost:${selectedPort}/api/books`;
    
    const params = {
        headers: {
            'XDN': 'bookcatalog',
        },
    };

    const response = http.get(url, params);
    
    check(response, {
        'status is 200': (r) => r.status === 200,
    });
    
    console.log(`time=${currentTime},status=${response.status},duration=${response.timings.duration}`);
}
