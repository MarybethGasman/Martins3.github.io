#!/usr/bin/env bash

# 开始之前
# sudo su
# echo 0 > /proc/sys/kernel/perf_event_paranoid
# echo 0 > /proc/sys/kernel/kptr_restrict
# echo 100000 > /proc/sys/kernel/perf_event_max_sample_rate

WORKDIR=/home/maritns3/core/vn/tmp/flame

set -eu
set -o xtrace
function usage() {
  echo "Usage :   [options] [--]

    Options:
    -h|help       Display this message
    -g|grep       Only display what you care about
    -c|cmd        The command to perf"
}

target=""
cmd=""
while getopts "hg:c:" opt; do
  case $opt in
  c) cmd=${OPTARG} ;;
  h)
    usage
    exit 0
    ;;
  g) target=${OPTARG} ;;
  *)
    echo -e "\n  Option does not exist : OPTARG\n"
    usage
    exit 1
    ;;
  esac # --- end of case ---
done
shift $((OPTIND - 1))

echo "cmd=$cmd"
echo "grep=$target"

stackcollapse_pl=${WORKDIR}/stackcollapse-perf.pl
flamegraph_pl=${WORKDIR}/flamegraph.pl
img=${WORKDIR}/flamegraph_dd.svg
perf_data=${WORKDIR}/perf_data.out

if [[ ! -d ${WORKDIR} ]]; then
  mkdir -p ${WORKDIR}
  wget https://raw.githubusercontent.com/brendangregg/FlameGraph/master/stackcollapse-perf.pl -O ${stackcollapse_pl}
  wget https://raw.githubusercontent.com/brendangregg/FlameGraph/master/flamegraph.pl -O ${flamegraph_pl}
fi

perf record -a -g ${cmd}
perf script | perl ${stackcollapse_pl} > ${perf_data}

if [[ -z ${target} ]]; then
  perl ${flamegraph_pl} --title "martins3" >${img} < ${perf_data}
else
  grep "${target}" ${perf_data} | perl ${flamegraph_pl} --title "trace" >${img}
fi
microsoft-edge-dev "${img}"
