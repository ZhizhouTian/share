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
       --gpu-memory-utilization 0.95 \
       --max-model-len 10240\
       --tensor-parallel-size 8 \
       --trust-remote-code \
       --disable-log-requests \
       --disable-log-stats \
       --max-num-seqs 16 \
       --max-num-batched-tokens 10240 \
       --enable-prefix-caching \
       --port 8888
