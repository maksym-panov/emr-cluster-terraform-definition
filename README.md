# AWS EMR Cluster Terraform Definition

## User Guide

### 1. Install AWS CLI
Open **Git Bash** and run:
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.msi" -o "AWSCLIV2.msi"
msiexec.exe /i AWSCLIV2.msi /quiet /norestart
rm AWSCLIV2.msi
```
Close and reopen Git Bash, then verify:
```bash
aws --version
```

### 2. Install Terraform CLI
Open **Git Bash** and run:
```bash
TERRAFORM_VERSION="1.10.5"
curl -o terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_windows_amd64.zip"
unzip -o terraform.zip -d /usr/local/bin
rm terraform.zip
```
Verify:
```bash
terraform -version
```

### 3. Create AWS account
Go to https://signin.aws.amazon.com/signup?request_type=register

### 4. Create IAM administrator user
See - https://www.youtube.com/watch?v=I88oAVwRnA8
```
Note - from now on DO NOT use your root AWS account you created earlier. Use only this admin user.
```

### 5. Create `aws_access_key_id` and `aws_secret_access_key` for the admin user
See - https://www.youtube.com/watch?v=66dm5_TnKTc (timecode 2:42, ignore "Console password" parts)
```
Note - NEVER share created credentials with other people.
```

### 6. Set AWS credentials on your PC
```shell
aws configure
```
Enter when prompted:
```
AWS Access Key ID [None]: JRAUSDFASSUZ**********
AWS Secret Access Key [None]: yggfdfd32FDvZ9QdH*************
Default region name [None]: eu-central-1
Default output format [None]:
```

### 7. Configure cluster power (instance size)

Copy the example env file and choose a preset:
```shell
cp cluster.env.example cluster.env
```

Open `cluster.env` and uncomment exactly **one** preset block. Available presets:

| Preset   | Instance     | vCPU/node | RAM/node | Price/node/hr | ~Total/hr* |
|----------|-------------|-----------|----------|---------------|------------|
| SMALL    | m5.xlarge   | 4         | 16 GB    | $0.278        | $1.11      |
| MEDIUM   | r5.xlarge   | 4         | 32 GB    | $0.367        | $1.38      |
| **LARGE**| **r5.2xlarge** | **8**  | **64 GB**| **$0.734**    | **$2.48**  |
| XLARGE   | r5.4xlarge  | 16        | 128 GB   | $1.468        | $4.68      |
| XXLARGE  | r5.8xlarge  | 32        | 256 GB   | $2.936        | $9.09      |

\* Total = 1 master (m5.xlarge, fixed) + 2 core + 1 task of chosen type, eu-central-1, On-Demand.

> **LARGE** is the default. To benchmark scalability, repeat steps 8–11 with different presets
> and compare the elapsed time and resource metrics printed at the end of each run.

### 8. Initialize Terraform
```shell
cd /path/to/emr-cluster-terraform-definition
terraform init
```

### 9. Check Terraform execution plan (optional)
```shell
# Unix / Git Bash
./deploy.sh plan

# Windows PowerShell
.\deploy.ps1 plan
```

### 10. Apply Terraform configuration (activate / resize EMR cluster)

> **Always use `deploy.sh` / `deploy.ps1` instead of calling `terraform` directly.**
> The deploy scripts load `cluster.env` and pass the preset variables to Terraform.
> Calling `terraform apply` directly ignores `cluster.env` and uses the defaults.

```shell
# Unix / Git Bash
./deploy.sh apply

# Windows PowerShell
.\deploy.ps1 apply
```
Terraform will show the plan and ask you to confirm. Type `yes` and press Enter.

After `deploy.sh apply` finishes the cluster will be visible at:
https://eu-central-1.console.aws.amazon.com/emr/home?region=eu-central-1#/clusters

> Every time you change the preset in `cluster.env`, re-run `./deploy.sh apply`
> to resize the cluster before submitting a new job.

### 11. Run the WordCount job

On **Windows** (run PowerShell as administrator):
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd C:\path\to\emr-cluster-terraform-definition
.\run.ps1
```

On **Unix / Git Bash**:
```shell
cd /path/to/emr-cluster-terraform-definition
./run.sh
```

The script will:
1. Display the active cluster power preset.
2. Prompt you for an input file — paste either:
   - An **HTTP/HTTPS URL** (the file is downloaded and uploaded to S3 automatically), or
   - An **S3 URL** (used directly, e.g. `s3://my-bucket/data/file.txt`).
3. Submit the WordCount Spark job to the EMR cluster.
4. Poll status until the job completes.
5. Download results to `./wordcount_result/`.
6. Print job metrics:
   - **Elapsed time** (HH:MM:SS)
   - **Memory allocated / available** (CloudWatch, 1-min resolution)
   - **CPU utilisation per node** (CloudWatch, 1-min resolution)

### 12. Destroy EMR cluster
**ATTENTION:** EMR clusters are billed by the second even when idle. Always destroy the cluster when done.

```shell
# Unix / Git Bash
./deploy.sh destroy

# Windows PowerShell
.\deploy.ps1 destroy
```
Type `yes` when prompted.

```
NEVER interrupt deploy destroy execution.
```

---

## Scalability Benchmark Workflow

Use different presets to measure how cluster "power" affects WordCount performance:

1. Set a preset in `cluster.env` → `terraform apply`
2. Run `./run.sh` with the same input file
3. Note the **Elapsed time** and **CPU/Memory metrics** from the output
4. Repeat with the next preset

Recommended test files: 1 GB, 2 GB, 5 GB, 10 GB plain-text corpora
(e.g. [Project Gutenberg](https://www.gutenberg.org/) full dump or Wikipedia XML dump).

---

## What's next?
Examine `run.sh`, `run.ps1`, and `wordcount.py` to understand the full pipeline.
You can extend `wordcount.py` with any PySpark transformation or replace it with
your own script — just update the `SCRIPT_NAME` variable at the top of the run script.

# Good Luck!
