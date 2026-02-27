#python3 /home/ubuntu/.src/github.com/vllm/benchmarks/benchmark_serving.py \
#!/bin/bash

prompts=$1
concurrency=$2

DATASET="/home/zz/.cache/modelscope/hub/datasets/gliang1001/ShareGPT_V3_unfiltered_cleaned_split/ShareGPT_V3_unfiltered_cleaned_split.json"

vllm bench serve \
	--backend vllm \
	--model ~/.cache/modelscope/hub/models/deepseek-ai/DeepSeek-R1-Distill-Llama-70B \
	--host 127.0.0.1 \
	--port 8888 \
	--dataset-name "sharegpt" \
	--dataset-path $DATASET \
	--num-prompts $1 \
	--sharegpt-output-len 1024 \
	--max-concurrency $2 \
	--burstiness 1.0 \
	--percentile-metrics "ttft,tpot,itl" \
	--metric-percentiles "90,99"

#	--served-model-name DeepSeek-R1-Distill-Llama-70B 
#	--endpoint /v1/completions \
