#!/bin/bash

# Upload the Spark script to S3
aws s3 cp test_spark_script.py s3://emr-spark-scripts-bucket/ --profile default

# Retrieve the active cluster ID
CLUSTER_ID=$(aws emr list-clusters --active --query "Clusters[0].Id" --output text --profile default)

# Check if the cluster ID was retrieved
if [ -z "$CLUSTER_ID" ]; then
  echo "No active EMR clusters found. Please start an EMR cluster first."
  exit 1
fi

echo "Cluster ID: $CLUSTER_ID"

# Add a step to the EMR cluster to run the Spark script
STEP_ID=$(aws emr add-steps --cluster-id "$CLUSTER_ID" --steps '[{
  "Type": "Spark",
  "Name": "Spark job",
  "ActionOnFailure": "CONTINUE",
  "Args": [
    "--deploy-mode", "cluster",
    "s3://emr-spark-scripts-bucket/test_spark_script.py"
  ]
}]' --query "StepIds[0]" --output text --profile default)

echo "Spark job submitted to cluster $CLUSTER_ID with Step ID $STEP_ID."

# Check the job status continuously
while true; do
  # Get the current status of the step
  STEP_STATUS=$(aws emr describe-step --cluster-id "$CLUSTER_ID" --step-id "$STEP_ID" --query "Step.Status.State" --output text --profile default)

  # Display the current status
  echo "Current step status: $STEP_STATUS"

  # Check if the step is completed (either SUCCESS or FAILED)
  if [[ "$STEP_STATUS" == "COMPLETED" ]]; then
    echo "Spark job completed successfully."
    break
  elif [[ "$STEP_STATUS" == "FAILED" || "$STEP_STATUS" == "CANCELLED" ]]; then
    echo "Spark job failed or was cancelled."
    break
  fi

  sleep 5
done

aws s3 cp s3://emr-spark-scripts-bucket/pi_result/ ./pi_result --recursive --profile default

