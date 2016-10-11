#!/bin/sh
# Purpose: Combine a large number of text files (either .txt or .csv formats) together
# This assumes that all files are formatted in the exact same way (e.g. output from a loop or parallelized jobs)
# Output: one file with all of the text files appended together

cd "strPath"
 
mkdir result
one_file=("results_"*."csv")
sed -n -e '1p' "$one_file" > result/results_"hiv_adjust"."csv"
 
for i in "results_"*."csv"; do
  sed -e '1d' "${i}" >> result/results_"hiv_adjust"."csv"
done
