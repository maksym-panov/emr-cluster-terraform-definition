variable "core_instance_type" {
  description = "EC2 instance type for core nodes. Set via CLUSTER_INSTANCE_TYPE in cluster.env."
  type        = string
  default     = "m5.xlarge"
}

variable "core_count" {
  description = "Number of core (HDFS) nodes. Set via CLUSTER_CORE_COUNT in cluster.env."
  type        = number
  default     = 2
}

