# Set S3 bucket and script path
$S3Bucket = "s3://emr-spark-scripts-bucket/"
$ScriptName = "test_spark_script.py"
$S3ScriptPath = "$S3Bucket$ScriptName"
$LocalResultDir = ".\pi_result"

# Upload the Spark script to S3
aws s3 cp $ScriptName $S3Bucket --profile default

# Retrieve the active EMR cluster ID
$ClusterId = aws emr list-clusters --active --query "Clusters[0].Id" --output text --profile default

# Check if the cluster ID was retrieved
if (-not $ClusterId) {
    Write-Host "No active EMR clusters found. Please start an EMR cluster first."
    exit 1
}

Write-Host "Cluster ID: $ClusterId"

# Add a step to the EMR cluster to run the Spark script
$StepId = aws emr add-steps --cluster-id $ClusterId --steps "[{
  `"Type`": `"Spark`",
  `"Name`": `"Spark job`",
  `"ActionOnFailure`": `"CONTINUE`",
  `"Args`": [
    `"--deploy-mode`", `"cluster`",
    `"$S3ScriptPath`"
  ]
}]" --query "StepIds[0]" --output text --profile default

Write-Host "Spark job submitted to cluster $ClusterId with Step ID $StepId."

# Check the job status continuously
while ($true) {
    # Get the current status of the step
    $StepStatus = aws emr describe-step --cluster-id $ClusterId --step-id $StepId --query "Step.Status.State" --output text --profile default

    # Display the current status
    Write-Host "Current step status: $StepStatus"

    # Check if the step is completed (either SUCCESS or FAILED)
    if ($StepStatus -eq "COMPLETED") {
        Write-Host "Spark job completed successfully."
        break
    } elseif ($StepStatus -eq "FAILED" -or $StepStatus -eq "CANCELLED") {
        Write-Host "Spark job failed or was cancelled."
        break
    }

    Start-Sleep -Seconds 5
}

# Download the result from S3
aws s3 cp "$S3Bucket/pi_result/" $LocalResultDir --recursive --profile default
