provider "aws" {
  region = "eu-central-1" # Frankfurt - closest to Ukraine, which means minimal latency
  access_key = AWS_ACCESS_KEY # Expects AWS_ACCESS_KEY environment variable to be set
  secret_key = AWS_SECRET_KEY # Expects AWS_SECRET_KEY environment variable to be set
}

# S3 bucket for Spark scripts
resource "aws_s3_bucket" "emr-spark-scripts-bucket" {
  bucket = "emr-spark-scripts-bucket"

  lifecycle {
    prevent_destroy = true
  }
}

# IAM service role for EMR Cluster
resource "aws_iam_role" "emr_service_role" {
  name = "EMRServiceRole"

  assume_role_policy = <<EOF
    {
      "Version": "2008-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "elasticmapreduce.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
  EOF

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"]
}

# IAM service role for EMR cluster's EC2 instances
resource "aws_iam_role" "emr_ec2_instance_role" {
  name = "EC2InstanceRoleInEMRCluster"

  assume_role_policy = <<EOF
    {
      "Version": "2008-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
  EOF
}

# Add full access to EMR for all EC2 instances in EMR cluster
resource "aws_iam_role_policy_attachment" "emr_ec2_instance_role_policy_attachment" {
  role       = aws_iam_role.emr_ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticMapReduceFullAccess"
}

# Create profile for EC2 instances and attach instance role to it
resource "aws_iam_instance_profile" "emr_instance_profile" {
  name = "EMRInstanceProfile"
  role = aws_iam_role.emr_ec2_instance_role.name
}

# Create EMR Cluster itself
resource "aws_emr_cluster" "spark_hadoop_cluster" {
  name           = "EMR Spark+Hadoop Cluster"
  release_label  = "emr-7.8.0" # Latest stable EMR release as on 23.03.2025
  applications   = ["Spark", "Hadoop"]
  service_role   = aws_iam_role.emr_service_role.arn

  # Make all EC2 instances in the cluster have emr_instance_profile
  ec2_attributes {
    instance_profile = aws_iam_instance_profile.emr_instance_profile.arn
  }

  # Master nodes group (always only 1 instance)
  master_instance_group {
    name          = "Master Node Instance Group"
    instance_type = "m5.xlarge"
  }

  # Core nodes group
  # r5.2xlarge - RAM-optimized EC2 instance type
  #     - 8 vCPU
  #     - 64 GB RAM
  # Change "r5.2xlarge" if needed - https://aws.amazon.com/ec2/pricing/on-demand/)
  core_instance_group {
    name           = "EMR Core Instance Group"
    instance_type  = "r5.2xlarge"
    instance_count = 1 # Configure base number of instances as needed

    # Increase number of core nodes if the load is too high (more than 75% of CPU is in use)
    auto_scaling_policy {
      constraints {
        min_capacity = 1  # Minimum number of instances
        max_capacity = 10 # Maximum number of instances
      }
      rules {
        name        = "Scale Up Rule"
        description = "Scale up when CPU utilization is high"
        action {
          simple_scaling_policy_configuration {
            adjustment_type = "ChangeInCapacity"
            scaling_adjustment = 1
            cool_down = 120
          }
        }
        trigger {
          cloud_watch_alarm_definition {
            comparison_operator = "GREATER_THAN"
            metric_name = "CPUUtilization"
            period = 120
            statistic = "AVERAGE"
            threshold = 75
            evaluation_periods = 2
          }
        }
      }
    }
  }

}