#!/bin/bash

# ---------------------------------------------------------------------------
# Load cluster power configuration from cluster.env
# Copy cluster.env.example → cluster.env and choose a preset before running.
# ---------------------------------------------------------------------------
if [ -f cluster.env ]; then
  set -a
  # shellcheck source=cluster.env.example
  source cluster.env
  set +a
else
  echo "Warning: cluster.env not found."
  echo "Copy cluster.env.example to cluster.env and uncomment a preset."
  echo "Continuing with Terraform defaults (LARGE / r5.2xlarge)."
fi

export TF_VAR_core_instance_type="${CLUSTER_INSTANCE_TYPE:-r5.2xlarge}"
export TF_VAR_core_count="${CLUSTER_CORE_COUNT:-2}"
export TF_VAR_task_count="${CLUSTER_TASK_COUNT:-1}"

echo ""
echo "Cluster power: ${TF_VAR_core_instance_type} | core=${TF_VAR_core_count} | task=${TF_VAR_task_count}"
echo ""

S3_BUCKET="s3://emr-spark-scripts-bucket"
SCRIPT_NAME="wordcount.py"
OUTPUT_PATH="$S3_BUCKET/wordcount_result"

# Prompt user for input file URL
echo "Enter the input file URL."
echo "  - S3 URL   (e.g. s3://my-bucket/data/file.txt)"
echo "  - HTTP URL (e.g. https://example.com/data.txt)"
read -rp "URL: " INPUT_URL

if [[ -z "$INPUT_URL" ]]; then
  echo "No URL provided. Exiting."
  exit 1
fi

# Handle HTTP/HTTPS: download the file and re-upload to S3
if [[ "$INPUT_URL" == http://* || "$INPUT_URL" == https://* ]]; then
  TMP_FILE=$(mktemp /tmp/wordcount_input.XXXXXX.txt)
  echo "Downloading file from $INPUT_URL ..."
  curl -fsSL "$INPUT_URL" -o "$TMP_FILE"
  if [ $? -ne 0 ]; then
    echo "Failed to download file."
    rm -f "$TMP_FILE"
    exit 1
  fi
  S3_INPUT_PATH="$S3_BUCKET/input/$(basename "$TMP_FILE")"
  echo "Uploading to $S3_INPUT_PATH ..."
  aws s3 cp "$TMP_FILE" "$S3_INPUT_PATH" --profile default
  rm -f "$TMP_FILE"
  INPUT_PATH="$S3_INPUT_PATH"
elif [[ "$INPUT_URL" == s3://* ]]; then
  INPUT_PATH="$INPUT_URL"
else
  echo "Unsupported URL scheme. Please provide an s3:// or http(s):// URL."
  exit 1
fi

# Upload the WordCount script to S3
aws s3 cp "$SCRIPT_NAME" "$S3_BUCKET/" --profile default

# Retrieve the active cluster ID
CLUSTER_ID=$(aws emr list-clusters --active --query "Clusters[0].Id" --output text --profile default)

if [ -z "$CLUSTER_ID" ]; then
  echo "No active EMR clusters found. Please start an EMR cluster first."
  exit 1
fi

echo "Cluster ID: $CLUSTER_ID"
echo "Input:      $INPUT_PATH"
echo "Output:     $OUTPUT_PATH"

# Submit the WordCount step
STEP_ID=$(aws emr add-steps --cluster-id "$CLUSTER_ID" --steps "[{
  \"Type\": \"Spark\",
  \"Name\": \"WordCount\",
  \"ActionOnFailure\": \"CONTINUE\",
  \"Args\": [
    \"--deploy-mode\", \"cluster\",
    \"$S3_BUCKET/$SCRIPT_NAME\",
    \"$INPUT_PATH\",
    \"$OUTPUT_PATH\"
  ]
}]" --query "StepIds[0]" --output text --profile default)

echo "Step submitted: $STEP_ID"

# Poll until the step finishes
while true; do
  STEP_STATUS=$(aws emr describe-step --cluster-id "$CLUSTER_ID" --step-id "$STEP_ID" \
    --query "Step.Status.State" --output text --profile default)
  echo "Status: $STEP_STATUS"
  if [[ "$STEP_STATUS" == "COMPLETED" ]]; then
    echo "WordCount job completed successfully."
    break
  elif [[ "$STEP_STATUS" == "FAILED" || "$STEP_STATUS" == "CANCELLED" ]]; then
    echo "WordCount job failed or was cancelled."
    break
  fi
  sleep 5
done

# Download results
aws s3 cp "$OUTPUT_PATH/" ./wordcount_result --recursive --profile default

echo ""
echo "=============================="
echo " JOB METRICS"
echo "=============================="

# --- Elapsed time ---
echo ""
echo "--- Elapsed Time ---"
START=$(aws emr describe-step --cluster-id "$CLUSTER_ID" --step-id "$STEP_ID" \
  --query "Step.Status.Timeline.StartDateTime" --output text --profile default)
END=$(aws emr describe-step --cluster-id "$CLUSTER_ID" --step-id "$STEP_ID" \
  --query "Step.Status.Timeline.EndDateTime" --output text --profile default)

ELAPSED=$(python3 -c "
from datetime import datetime, timezone
import re

def parse_dt(s):
    s = re.sub(r'\.\d+', '', s)
    s = re.sub(r'([+-]\d{2}):(\d{2})$', '', s)
    s = s.replace('Z', '').replace('+0000', '')
    return datetime.strptime(s.strip(), '%Y-%m-%dT%H:%M:%S').replace(tzinfo=timezone.utc)

s = parse_dt('$START')
e = parse_dt('$END')
d = int((e - s).total_seconds())
print(f'{d//3600:02d}:{d%3600//60:02d}:{d%60:02d} ({d}s)')
")

echo "Start:   $START"
echo "End:     $END"
echo "Elapsed: $ELAPSED"

START_CW=$(date -u -d "$START" +%FT%TZ 2>/dev/null || echo "$START")
END_CW=$(date -u -d "$END" +%FT%TZ 2>/dev/null || echo "$END")

# --- Memory ---
echo ""
echo "--- Memory Allocated (YARN, MB) ---"
aws cloudwatch get-metric-statistics \
  --namespace "AWS/ElasticMapReduce" \
  --metric-name "MemoryAllocatedMB" \
  --dimensions Name=JobFlowId,Value="$CLUSTER_ID" \
  --start-time "$START_CW" --end-time "$END_CW" \
  --period 60 --statistics Average \
  --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,AllocatedMB:Average}" \
  --output table --profile default

echo ""
echo "--- YARN Memory Available (%) ---"
aws cloudwatch get-metric-statistics \
  --namespace "AWS/ElasticMapReduce" \
  --metric-name "YARNMemoryAvailablePercentage" \
  --dimensions Name=JobFlowId,Value="$CLUSTER_ID" \
  --start-time "$START_CW" --end-time "$END_CW" \
  --period 60 --statistics Average \
  --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,AvailablePct:Average}" \
  --output table --profile default

# --- CPU per node ---
echo ""
echo "--- CPU Utilisation per Node (%) ---"
INSTANCE_IDS=$(aws emr list-instances --cluster-id "$CLUSTER_ID" \
  --query "Instances[*].Ec2InstanceId" --output text --profile default)

for INST in $INSTANCE_IDS; do
  echo "  Node: $INST"
  aws cloudwatch get-metric-statistics \
    --namespace "AWS/EC2" \
    --metric-name "CPUUtilization" \
    --dimensions Name=InstanceId,Value="$INST" \
    --start-time "$START_CW" --end-time "$END_CW" \
    --period 60 --statistics Average \
    --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,CPU_Pct:Average}" \
    --output table --profile default
done
