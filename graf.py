import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
import glob
import os

FOLDER_NAME = 'tes1'

def combine_csv_files(file_pattern=None):
    if file_pattern is None:
        file_pattern = f'{FOLDER_NAME}/xdn_results_*.csv'
    
    files = glob.glob(file_pattern)
    
    if not files:
        print(f"No file, file pattern : {file_pattern}")
        return None
    
    print(f"{len(files)} Files: {', '.join(files)}")
    
    dfs = []
    for file in files:
        df = pd.read_csv(file)
        
        required_columns = ['consistency', 'get_latency', 'post_latency', 'delete_latency', 'overall_latency']
        missing_columns = [col for col in required_columns if col not in df.columns]
        
        if missing_columns:
            print(f"Warning: File {file} missing columns: {missing_columns}")
            if 'consistency' in missing_columns:
                model = file.split('_')[-1].split('.')[0].upper()
                df['consistency'] = model
            
            for col in missing_columns:
                if col != 'consistency':
                    df[col] = 0
            
            if 'overall_latency' in missing_columns and all(col in df.columns for col in ['get_latency', 'post_latency', 'delete_latency']):
                df['overall_latency'] = (df['get_latency'] + df['post_latency'] + df['delete_latency']) / 3
        
        for col in ['get_latency', 'post_latency', 'delete_latency', 'overall_latency']:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')
        
        dfs.append(df)
    
    combined_df = pd.concat(dfs, ignore_index=True)
    
    output_path = os.path.join(FOLDER_NAME, 'xdn_combined_results.csv')
    os.makedirs(FOLDER_NAME, exist_ok=True)  
    combined_df.to_csv(output_path, index=False)
    print(f"Combined results saved to {output_path}")
    
    return combined_df

def visualize_results(df):
   
    df = df.drop_duplicates(subset=['consistency'], keep='first')
    
    if 'overall_latency' in df.columns:
        df = df.sort_values('overall_latency')
    
    fig, ax = plt.subplots(figsize=(12, 8))
    
    bar_width = 0.2
    index = np.arange(len(df))
    
    ax.bar(index - bar_width, df['get_latency'], bar_width, label='GET', color='#3498db')
    ax.bar(index, df['post_latency'], bar_width, label='POST', color='#2ecc71')
    ax.bar(index + bar_width, df['delete_latency'], bar_width, label='DELETE', color='#e74c3c')
    
    for i, v in enumerate(df['get_latency']):
        ax.text(i - bar_width, v + 2, f"{v:.1f}", ha='center', fontsize=9)
    for i, v in enumerate(df['post_latency']):
        ax.text(i, v + 2, f"{v:.1f}", ha='center', fontsize=9)
    for i, v in enumerate(df['delete_latency']):
        ax.text(i + bar_width, v + 2, f"{v:.1f}", ha='center', fontsize=9)
    
    ax.set_xlabel('Consistency Model', fontsize=14)
    ax.set_ylabel('Average Latency (ms)', fontsize=14)
    ax.set_title('XDN Consistency Models: Latency Comparison', fontsize=16)
    ax.set_xticks(index)
    ax.set_xticklabels(df['consistency'], rotation=45, ha='right')
    
    ax.legend()
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    
    y_max = max(df[['get_latency', 'post_latency', 'delete_latency']].max()) * 1.2
    ax.set_ylim(0, y_max)
    
    plt.tight_layout()
    
    output_path = os.path.join(FOLDER_NAME, 'xdn_latency_comparison.png')
    os.makedirs(FOLDER_NAME, exist_ok=True) 
    plt.savefig(output_path, dpi=300)
    print(f"Generated chart: {output_path}")
    
    print("\nSummary Results:")
    print("----------------")
    for _, row in df.iterrows():
        print(f"{row['consistency']}:")
        print(f"  GET:     {row['get_latency']:.2f} ms")
        print(f"  POST:    {row['post_latency']:.2f} ms")
        print(f"  DELETE:  {row['delete_latency']:.2f} ms")
        print(f"  Overall: {row['overall_latency']:.2f} ms")
        print()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        files = sys.argv[1:]
        print(f"Processing files: {', '.join(files)}")
        dfs = []
        for file in files:
            df = pd.read_csv(file)
            dfs.append(df)
        
        combined_df = pd.concat(dfs, ignore_index=True)
        visualize_results(combined_df)
    else:
        print(f"No files specified. Path : '{FOLDER_NAME}/xdn_results_*.csv'")
        df = combine_csv_files()
        if df is not None:
            visualize_results(df)