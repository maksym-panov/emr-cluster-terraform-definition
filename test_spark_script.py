# This script calculates an approximation
# of the mathematical constant π (Pi)
# using the Monte Carlo method
# and saves the result to an S3 bucket

from pyspark import SparkContext

sc = SparkContext(appName="SparkPi")

NUM_SAMPLES = 1000000

def inside(p):
    import random
    x = random.random() * 2 - 1
    y = random.random() * 2 - 1
    return x * x + y * y <= 1


count = sc.parallelize(range(0, NUM_SAMPLES)) \
    .filter(inside) \
    .count()

pi_value = 4.0 * count / NUM_SAMPLES
print("Pi is roughly %f" % pi_value)

# Save the result to S3, coalescing to one partition explicitly
result_rdd = sc.parallelize([f"Pi is roughly {pi_value}"])
result_rdd.repartition(1).saveAsTextFile("s3://emr-spark-scripts-bucket/pi_result")

sc.stop()
