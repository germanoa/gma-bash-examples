#!/bin/bash

hosts="host1 host2 hostn"
c=100
i=100

for i in `seq 0 $i`
do
  for h in $hosts
  do
      now=$(date --rfc-3339=seconds)
      latency=$(ping $h -q -c $c |grep '^rtt' |cut -d'=' -f2 |tr -s '/' ',' |sed -e 's/ms//' |sed -e 's/ *//')
      echo "$now,$h,$latency"
  done
done
