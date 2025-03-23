# AWS EMR Cluster Terraform Definition

## User Guide

### 1. Install AWS CLI
See - https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

### 2. Install Terraform CLI
See - https://www.geeksforgeeks.org/setup-terraform-on-linux-and-windows-machine/

### 3. Create AWS account 
Go to https://signin.aws.amazon.com/signup?request_type=register

### 4. Create IAM administrator user
See - https://www.youtube.com/watch?v=I88oAVwRnA8
```
Note - from now on DO NOT use your root AWS account you created earlier. Use only this admin user 
```

### 5. Create `aws_access_key_id` and `aws_secret_access_key` for created admin user
See - https://www.youtube.com/watch?v=66dm5_TnKTc
Timecode - 2:42 (ignore "Console password" parts since it's not relevant in our case)
```
Note - NEVER share created credentials with other people
```
 
### 6. Set AWS credentials on your PC
1. Execute:
```
aws configure
```
2. Enter credentials (for 'Default output format' just press Enter):
```
AWS Access Key ID [None]: JRAUSDFASSUZ**********
AWS Secret Access Key [None]: yggfdfd32FDvZ9QdH*************
Default region name [None]: eu-central-1
Default output format [None]: 
```

### 7. Initialize Terraform
```shell
cd /path/to/emr-cluster-terraform-definition
terraform init
```

### 8. Check Terraform execution plan (Optional)
```shell
terraform plan
```

### 9. Apply Terraform configuration (i.e. activate EMR cluster)
```shell
terraform apply
```

Note that Terraform will show you execution plan again and ask whether you
want to execute it. You should type 'yes' and press Enter.

After execution of `terraform apply` is finished you should be able to 
see your EMR Cluster up and running in AWS Management Console.

https://eu-central-1.console.aws.amazon.com/emr/home?region=eu-central-1#/clusters

### 10. Run test script
On Windows (run PowerShell as administrator):
```shell
Set-ExecutionPolicy Bypass -Scope Process -Force

cd C:\path\to\emr-cluster-terraform-definition

.\run.ps1
```

On Unix systems:
```shell
cd /path/to/emr-cluster-terraform-definition

./run.sh
```

Wait until script execution is completed and check whether 
`result_pi` subdirectory appeared in your `emr-cluster-terraform-definition` directory.

It should contain files `_SUCCESS` and `part-00000`. `part-00000` contains result of script execution.

### 11. Destroy EMR cluster
ATTENTION: EMR cluster is extremely expensive to maintain. NEVER forget to destroy it when your work is done.

```shell
terraform destroy
```

Note - Terraform will ask if you really want to destroy the configuration. Type 'yes' and press Enter.

Note 2 - NEVER INTERRUPT `terraform destroy` EXECUTION

## What's next?
Now you can examine files `run.sh`, `run.ps1` and `test_spark_script.py` to understand what 
you should do to execute your Spark/Hadoop scripts. You can either manually run all AWS CLI
commands or write your own `run.sh` scripts based on this example or even change its contents
based on your needs.

# Good Luck!