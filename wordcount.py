from __future__ import print_function

import sys
from operator import add

from pyspark.sql import SparkSession

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: wordcount <input_path> [output_path]", file=sys.stderr)
        sys.exit(-1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "s3://emr-spark-scripts-bucket/wordcount_result"

    spark = SparkSession \
        .builder \
        .appName("PythonWordCount") \
        .getOrCreate()

    lines = spark.read.text(input_path).rdd.map(lambda r: r[0])

    counts = lines.flatMap(lambda x: x.split(" ")) \
                  .map(lambda x: (x, 1)) \
                  .reduceByKey(add)

    counts.saveAsTextFile(output_path)

    spark.stop()
