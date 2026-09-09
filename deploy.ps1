if (Test-Path "cluster.env") {
    Get-Content "cluster.env" | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
        $parts = $_ -split "=", 2
        [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
    }
} else {
    Write-Host "Warning: cluster.env not found. Copy cluster.env.example to cluster.env."
    Write-Host "Using defaults: m5.xlarge, 2 core nodes."
}

$env:TF_VAR_core_instance_type = if ($env:CLUSTER_INSTANCE_TYPE) { $env:CLUSTER_INSTANCE_TYPE } else { "m5.xlarge" }
$env:TF_VAR_core_count         = if ($env:CLUSTER_CORE_COUNT)     { $env:CLUSTER_CORE_COUNT }     else { "2" }

Write-Host "Deploying with: $($env:TF_VAR_core_instance_type) x$($env:TF_VAR_core_count) core nodes"
Write-Host ""

terraform @args
