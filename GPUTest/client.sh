#python3 /home/ubuntu/.src/github.com/vllm/benchmarks/benchmark_serving.py \
#!/bin/bash

prompts=$1
concurrency=$2

vllm bench serve \
	--backend vllm \
	--model /home/ubuntu/.cache/modelscope/hub/models/deepseek-ai/DeepSeek-R1-Distill-Llama-70B \
	--host 127.0.0.1 \
	--port 8888 \
	--dataset-name "sharegpt" \
	--dataset-path "/home/ubuntu/.src/github.com/share/GPUTest/ShareGPT_V3_unfiltered_cleaned_split.json"\
	--num-prompts $1 \
	--sharegpt-output-len 2048 \
	--max-concurrency $2 \
	--burstiness 1.0 \
	--percentile-metrics "ttft,tpot,itl" \
	--metric-percentiles "90,99" \
	--endpoint-type vllm 

#	--served-model-name DeepSeek-R1-Distill-Llama-70B 
#	--endpoint /v1/completions \
