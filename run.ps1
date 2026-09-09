# ---------------------------------------------------------------------------
# Load cluster power configuration from cluster.env
# Copy cluster.env.example -> cluster.env and choose a preset before running.
# ---------------------------------------------------------------------------
if (Test-Path "cluster.env") {
    Get-Content "cluster.env" | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
        $parts = $_ -split "=", 2
        [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
    }
} else {
    Write-Host "Warning: cluster.env not found."
    Write-Host "Copy cluster.env.example to cluster.env and uncomment a preset."
    Write-Host "Continuing with Terraform defaults (LARGE / r5.2xlarge)."
}

$env:TF_VAR_core_instance_type = if ($env:CLUSTER_INSTANCE_TYPE) { $env:CLUSTER_INSTANCE_TYPE } else { "r5.2xlarge" }
$env:TF_VAR_core_count         = if ($env:CLUSTER_CORE_COUNT)     { $env:CLUSTER_CORE_COUNT }     else { "2" }
$env:TF_VAR_task_count         = if ($env:CLUSTER_TASK_COUNT)     { $env:CLUSTER_TASK_COUNT }     else { "1" }

Write-Host ""
Write-Host "Cluster power: $($env:TF_VAR_core_instance_type) | core=$($env:TF_VAR_core_count) | task=$($env:TF_VAR_task_count)"
Write-Host ""

$S3Bucket     = "s3://emr-spark-scripts-bucket"
$ScriptName   = "wordcount.py"
$OutputPath   = "$S3Bucket/wordcount_result"

# Prompt user for input file URL
Write-Host "Enter the input file URL."
Write-Host "  - S3 URL   (e.g. s3://my-bucket/data/file.txt)"
Write-Host "  - HTTP URL (e.g. https://example.com/data.txt)"
$InputUrl = Read-Host "URL"

if (-not $InputUrl) {
    Write-Host "No URL provided. Exiting."
    exit 1
}

# Handle HTTP/HTTPS: download and re-upload to S3
if ($InputUrl -match "^https?://") {
    $TmpFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Write-Host "Downloading file from $InputUrl ..."
    try {
        Invoke-WebRequest -Uri $InputUrl -OutFile $TmpFile -ErrorAction Stop
    } catch {
        Write-Host "Failed to download file: $_"
        exit 1
    }
    $S3InputPath = "$S3Bucket/input/$(Split-Path $TmpFile -Leaf)"
    Write-Host "Uploading to $S3InputPath ..."
    aws s3 cp $TmpFile $S3InputPath --profile default
    Remove-Item $TmpFile -Force
    $InputPath = $S3InputPath
} elseif ($InputUrl -match "^s3://") {
    $InputPath = $InputUrl
} else {
    Write-Host "Unsupported URL scheme. Please provide an s3:// or http(s):// URL."
    exit 1
}

# Upload the WordCount script to S3
aws s3 cp $ScriptName "$S3Bucket/" --profile default

# Retrieve the active EMR cluster ID
$ClusterId = aws emr list-clusters --active --query "Clusters[0].Id" --output text --profile default

if (-not $ClusterId) {
    Write-Host "No active EMR clusters found. Please start an EMR cluster first."
    exit 1
}

Write-Host "Cluster ID: $ClusterId"
Write-Host "Input:      $InputPath"
Write-Host "Output:     $OutputPath"

# Submit the WordCount step
$StepJson = "[{
  `"Type`": `"Spark`",
  `"Name`": `"WordCount`",
  `"ActionOnFailure`": `"CONTINUE`",
  `"Args`": [
    `"--deploy-mode`", `"cluster`",
    `"$S3Bucket/$ScriptName`",
    `"$InputPath`",
    `"$OutputPath`"
  ]
}]"

$StepId = aws emr add-steps --cluster-id $ClusterId --steps $StepJson `
    --query "StepIds[0]" --output text --profile default

Write-Host "Step submitted: $StepId"

# Poll until the step finishes
while ($true) {
    $StepStatus = aws emr describe-step --cluster-id $ClusterId --step-id $StepId `
        --query "Step.Status.State" --output text --profile default
    Write-Host "Status: $StepStatus"
    if ($StepStatus -eq "COMPLETED") {
        Write-Host "WordCount job completed successfully."
        break
    } elseif ($StepStatus -eq "FAILED" -or $StepStatus -eq "CANCELLED") {
        Write-Host "WordCount job failed or was cancelled."
        break
    }
    Start-Sleep -Seconds 5
}

# Download results
aws s3 cp "$OutputPath/" .\wordcount_result --recursive --profile default

Write-Host ""
Write-Host "=============================="
Write-Host " JOB METRICS"
Write-Host "=============================="

# --- Elapsed time ---
Write-Host ""
Write-Host "--- Elapsed Time ---"
$StepStart = aws emr describe-step --cluster-id $ClusterId --step-id $StepId `
    --query "Step.Status.Timeline.StartDateTime" --output text --profile default
$StepEnd = aws emr describe-step --cluster-id $ClusterId --step-id $StepId `
    --query "Step.Status.Timeline.EndDateTime" --output text --profile default

$StartDt  = [datetime]::Parse($StepStart).ToUniversalTime()
$EndDt    = [datetime]::Parse($StepEnd).ToUniversalTime()
$Elapsed  = $EndDt - $StartDt
$ElapsedStr = "{0:D2}:{1:D2}:{2:D2} ({3}s)" -f `
    [int]$Elapsed.Hours, [int]$Elapsed.Minutes, [int]$Elapsed.Seconds, [int]$Elapsed.TotalSeconds

Write-Host "Start:   $StepStart"
Write-Host "End:     $StepEnd"
Write-Host "Elapsed: $ElapsedStr"

$StartCw = $StartDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
$EndCw   = $EndDt.ToString("yyyy-MM-ddTHH:mm:ssZ")

# --- Memory ---
Write-Host ""
Write-Host "--- Memory Allocated (YARN, MB) ---"
aws cloudwatch get-metric-statistics `
  --namespace "AWS/ElasticMapReduce" `
  --metric-name "MemoryAllocatedMB" `
  --dimensions Name=JobFlowId,Value=$ClusterId `
  --start-time $StartCw --end-time $EndCw `
  --period 60 --statistics Average `
  --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,AllocatedMB:Average}" `
  --output table --profile default

Write-Host ""
Write-Host "--- YARN Memory Available (%) ---"
aws cloudwatch get-metric-statistics `
  --namespace "AWS/ElasticMapReduce" `
  --metric-name "YARNMemoryAvailablePercentage" `
  --dimensions Name=JobFlowId,Value=$ClusterId `
  --start-time $StartCw --end-time $EndCw `
  --period 60 --statistics Average `
  --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,AvailablePct:Average}" `
  --output table --profile default

# --- CPU per node ---
Write-Host ""
Write-Host "--- CPU Utilisation per Node (%) ---"
$InstanceIds = (aws emr list-instances --cluster-id $ClusterId `
    --query "Instances[*].Ec2InstanceId" --output text --profile default).Split()

foreach ($InstId in $InstanceIds) {
    if (-not $InstId) { continue }
    Write-Host "  Node: $InstId"
    aws cloudwatch get-metric-statistics `
      --namespace "AWS/EC2" `
      --metric-name "CPUUtilization" `
      --dimensions "Name=InstanceId,Value=$InstId" `
      --start-time $StartCw --end-time $EndCw `
      --period 60 --statistics Average `
      --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,CPU_Pct:Average}" `
      --output table --profile default
}
