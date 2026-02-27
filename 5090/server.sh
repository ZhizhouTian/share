#!/bin/bash
seqs=$1
echo ${seqs}

NCCL_P2P_LEVEL=SYS \
NCCL_P2P_DISABLE=0 \
VLLM_WORKER_MULTIPROC_METHOD=spawn \
VLLM_MLA_DISABLE=1 \
VLLM_USE_V1=1 \
vllm serve \
	/home/ubuntu/.cache/modelscope/hub/models/deepseek-ai/DeepSeek-R1-Distill-Llama-70B \
       --block-size 16 \
       --dtype float16 \
       --enable-chunked-prefill \
       --max-model-len 4096 \
       --tensor-parallel-size 8 \
       --trust-remote-code \
       --disable-log-requests \
       --disable-log-stats \
       --max-num-seqs ${seqs} \
       --max-num-batched-tokens 10240 \
       --enable-prefix-caching \
       --port 8888

    #   --gpu-memory-utilization 0.95 \
