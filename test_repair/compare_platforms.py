import argparse
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

def parse_args():
    parser = argparse.ArgumentParser(description='Compare XDN and Worker performance')
    parser.add_argument('--xdn-output', required=True, help='Path to XDN K6 output CSV file')
    parser.add_argument('--worker-output', required=True, help='Path to Worker K6 output CSV file')
    parser.add_argument('--crash-time', type=float, default=20, help='Crash time in seconds')
    parser.add_argument('--output', required=True, help='Output image file path')
    return parser.parse_args()

def process_k6_data(file_path, platform_name):
    try:
        k6_data = pd.read_csv(file_path, low_memory=False)
        
        min_timestamp = k6_data['timestamp'].min()
        k6_data['elapsed_time'] = k6_data['timestamp'].apply(
            lambda x: float(x) - float(min_timestamp)
        )
        k6_data['second'] = k6_data['elapsed_time'].apply(lambda x: int(x))
        
        successful_reqs = k6_data[k6_data['metric_name'] == 'checks'].copy()
        
        if len(successful_reqs) == 0:
            all_reqs = k6_data[k6_data['metric_name'] == 'http_reqs'].copy()
            
            failed_reqs = k6_data[k6_data['metric_name'] == 'http_req_failed'].copy()
            failed_by_second = failed_reqs.groupby('second')['metric_value'].sum().reset_index()
            failed_by_second_dict = dict(zip(failed_by_second['second'], failed_by_second['metric_value']))
            
            total_by_second = all_reqs.groupby('second')['metric_value'].sum().reset_index()
            
            successful_by_second = []
            for _, row in total_by_second.iterrows():
                second = row['second']
                total = row['metric_value']
                failed = failed_by_second_dict.get(second, 0)
                successful = max(0, total - failed)
                successful_by_second.append({'second': second, 'metric_value': successful})
            
            throughput_by_second = pd.DataFrame(successful_by_second)
        else:
            throughput_by_second = successful_reqs.groupby('second')['metric_value'].sum().reset_index()
        
        max_second = max(throughput_by_second['second'])
        all_seconds = pd.DataFrame({'second': range(0, max_second + 1)})
        throughput_by_second = pd.merge(all_seconds, throughput_by_second, on='second', how='left').fillna(0)
        
        throughput_by_second = throughput_by_second.sort_values('second')
        
        return throughput_by_second['second'].values, throughput_by_second['metric_value'].values, max_second
        
    except Exception as e:
        print(f"Error processing {platform_name} metrics: {e}")
        return np.array([]), np.array([]), 0

def calculate_statistics(throughputs, platform_name, crash_time):
    if len(throughputs) == 0:
        print(f"No valid data for {platform_name}")
        return 0, 0
    
    print(f"\n{platform_name} Statistics (Successful Requests Only):")
    print(f"Average throughput: {np.mean(throughputs):.2f} req/s")
    print(f"Max throughput: {np.max(throughputs):.2f} req/s")
    print(f"Min throughput: {np.min(throughputs):.2f} req/s")
    
    before_crash = []
    after_crash = []
    
    for i, t in enumerate(throughputs):
        if i < crash_time:
            before_crash.append(t)
        else:
            after_crash.append(t)
    
    before_avg = 0
    if before_crash:
        before_avg = np.mean(before_crash)
        print(f"Before crash: Avg Throughput={before_avg:.2f} req/s")
    
    after_avg = 0
    if after_crash:
        after_avg = np.mean(after_crash)
        print(f"After crash: Avg Throughput={after_avg:.2f} req/s")
        
    return before_avg, after_avg

def main():
    args = parse_args()
    
    print(f"Reading XDN metrics from {args.xdn_output}")
    xdn_timestamps, xdn_throughputs, xdn_max_second = process_k6_data(args.xdn_output, "XDN")
    
    print(f"Reading Worker metrics from {args.worker_output}")
    worker_timestamps, worker_throughputs, worker_max_second = process_k6_data(args.worker_output, "Worker")
    
    plt.figure(figsize=(14, 10))
    
    if len(xdn_timestamps) > 0:
        plt.plot(xdn_timestamps, xdn_throughputs, 'b-', linewidth=2, label='XDN')
    
    if len(worker_timestamps) > 0:
        plt.plot(worker_timestamps, worker_throughputs, 'g-', linewidth=2, label='Cloudflare Worker')
    
    plt.ylabel('Successful Requests per Second', fontsize=12)
    plt.xlabel('Time since test start (s)', fontsize=12)
    plt.title('XDN vs Cloudflare Worker Performance Comparison', fontsize=14)
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.legend(fontsize=12)
    
    crash_time = args.crash_time
    plt.axvline(x=crash_time, color='r', linestyle='--', linewidth=2)
    
    all_throughputs = np.concatenate([xdn_throughputs, worker_throughputs]) if len(xdn_timestamps) > 0 and len(worker_timestamps) > 0 else (xdn_throughputs if len(xdn_timestamps) > 0 else worker_throughputs)
    
    if len(all_throughputs) > 0:
        max_throughput = np.max(all_throughputs) * 0.8
    else:
        max_throughput = 200
    
    plt.text(crash_time + 1, max_throughput, 
            "Server\ncrashed", 
            verticalalignment='top',
            fontsize=12)
    
    max_second = max(xdn_max_second, worker_max_second, 60)
    
    if len(all_throughputs) > 0:
        y_max = max(np.max(all_throughputs) * 1.1, 250)
    else:
        y_max = 250
        
    plt.ylim(0, y_max)
    plt.xlim(0, max_second + 5)
    
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    
    plt.savefig(args.output, dpi=300, bbox_inches='tight')
    print(f"Comparison graph saved to {args.output}")
    
    xdn_before, xdn_after = calculate_statistics(xdn_throughputs, "XDN", crash_time)
    worker_before, worker_after = calculate_statistics(worker_throughputs, "Cloudflare Worker", crash_time)
    
    if len(xdn_throughputs) > 0 and len(worker_throughputs) > 0:
        print("\nPerformance Comparison (Before Crash):")
        if xdn_before > worker_before:
            pct_diff = ((xdn_before - worker_before) / worker_before) * 100
            print(f"XDN outperforms Cloudflare Worker by {pct_diff:.2f}% ({xdn_before:.2f} vs {worker_before:.2f} req/s)")
        else:
            pct_diff = ((worker_before - xdn_before) / xdn_before) * 100
            print(f"Cloudflare Worker outperforms XDN by {pct_diff:.2f}% ({worker_before:.2f} vs {xdn_before:.2f} req/s)")
        
        print("\nRecovery Behavior:")
        if xdn_after > worker_after:
            print(f"XDN has better post-crash throughput: {xdn_after:.2f} req/s vs Worker's {worker_after:.2f} req/s")
        else:
            print(f"Worker has better post-crash throughput: {worker_after:.2f} req/s vs XDN's {xdn_after:.2f} req/s")

if __name__ == "__main__":
    main()
