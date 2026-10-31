# Qwen3.8 Flash DGX UltraFast (v16b), packaged for the cluster.
#
# Base: the recipe's measured image (qwen38-flash-dgx:iter6d-20260910),
# built unchanged by its own recipe/build/image/build.sh from the pinned
# public vLLM image. This layer only adds files, so the serving path stays
# the measured one:
#   - the drafter builder (recipe/build/model/*.py), run by the
#     build-drafter init container of the cebra-ai-inference Deployment
#     instead of `docker run`
#   - the 65,536-id MTP draft vocabulary, unpacked (launch.sh does this on
#     the host and bind-mounts it)
#
# Build context: a checkout of dime-online/qwen3.8-Flash-DGX-UltraFast at
# the commit pinned in scripts/build-and-push.sh (which builds the base
# first; don't build this file on its own).
# Apache-2.0; LICENSE and NOTICE are kept in /opt/ultrafast.
ARG BASE=qwen38-flash-dgx:iter6d-20260910
FROM ${BASE}

COPY LICENSE NOTICE /opt/ultrafast/
COPY recipe/build/model/ /opt/ultrafast/build-model/
COPY recipe/config/v16b/draft-vocab-ids-K65536.txt.gz /tmp/draft-vocab.txt.gz
RUN gzip -dc /tmp/draft-vocab.txt.gz > /opt/ultrafast/draft-vocab-ids-K65536.txt \
 && rm /tmp/draft-vocab.txt.gz \
 && test "$(wc -l < /opt/ultrafast/draft-vocab-ids-K65536.txt)" -eq 65536 \
 && rm -f /opt/ultrafast/build-model/build.sh
