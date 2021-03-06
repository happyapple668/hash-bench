#!/bin/bash

if [ "$1" = "-h" -o "$1" = "--help" -o "$1" = "--h" -o "$1" = "" -o "$2" = "" ]; then
cat <<EOF
Usage: plot FILE DIR
Plots the FILE into the output DIR, including a summary README.md.

Arguments:
  FILE   Input CSV (usually jmh-result.csv)
  DIR    To write output (existing files will be removed)

EOF
exit 1;
fi

set -e

hash gplot.pl 2>/dev/null || { printf "gplot not found\n"; exit 1; }
hash dos2unix 2>/dev/null || { printf "dos2unix not found\n"; exit 1; }
hash grep 2>/dev/null || { printf "grep not found\n"; exit 1; }
hash cut 2>/dev/null || { printf "cut not found\n"; exit 1; }
hash uniq 2>/dev/null || { printf "uniq not found\n"; exit 1; }
hash sed 2>/dev/null || { printf "sed not found\n"; exit 1; }
hash tr 2>/dev/null || { printf "tr not found\n"; exit 1; }
hash sort 2>/dev/null || { printf "sort not found\n"; exit 1; }
hash head 2>/dev/null || { printf "head not found\n"; exit 1; }

FILE=$1
DIRECTORY=$2

if [ ! -f "${FILE}" ]; then
    echo "Input file not found (use -h for help)"
    exit 1
fi

if [ ! -d "${DIRECTORY}" ]; then
    echo "Output directory must exist (use -h for help)"
    exit 1
fi

dos2unix -q ${FILE}

BUFFERS=$(cut -d , -f 1 ${FILE} | sort | uniq | grep -v Benchmark | sed 's/au.com.acegi.hashbench.HashBench.with//g'  | sed 's/\"//g' | tr '\n' ' ')
ALGOS=$(cut -d , -f 8 ${FILE} | sort | uniq | grep -v Param | tr '\n' ' ')
HASHES=$(cut -d , -f 8 ${FILE} | grep -v Param | cut -d '-' -f 1 | sort | uniq | tr '\n' ' ')
IMPLS=$(cut -d , -f 8 ${FILE} | grep -v Param | sed 's/.*-\(.*\)/\1/g' | sort | uniq | tr '\n' ' ')
LENGTHS=$(cut -d , -f 9 ${FILE} | sort -n | uniq | grep -v Param | tr '\n' ' ')

rm -f ${DIRECTORY}/*
cp ${FILE} ${DIRECTORY}

# Extract buffer-specific, algorithm-specific performance
for BUFFER in ${BUFFERS}; do
    for ALGO in ${ALGOS}; do
        OUTPUT=${DIRECTORY}/${BUFFER}-${ALGO}.dat
        grep "${BUFFER}.*,${ALGO}," ${FILE} | cut -d , -f 5,9 | sed -e 's/,/ /g' >> ${OUTPUT}
    done
done

# Plot algo-specific performance as length increases (all algos)
for ALGO in ${ALGOS}; do
    PNG=${DIRECTORY}/${ALGO}.png
    OPTS=""
    COUNTER=1
    for BUFFER in ${BUFFERS}; do
        ((COUNTER++))
        INPUT=${DIRECTORY}/${BUFFER}-${ALGO}.dat
        OPTS+="-name ${BUFFER} -using 2:1 ${INPUT} "
    done
    gplot.pl -outfile ${PNG} -type png -title "${ALGO} by Slice Length" -xlabel "Bytes" -ylabel "ns/hash" -set "xtics nomirror rotate by -270; set key top left" -style linespoints ${OPTS}
done

length_performance() {
    # length outputFile algoList
    for ALGO in $3; do
        echo -n "${ALGO}" >> $2
        for BUFFER in ${BUFFERS}; do
            INPUT=${DIRECTORY}/${BUFFER}-${ALGO}.dat
            SCORE=$(grep " ${1}$" ${INPUT} | cut -d ' ' -f 1)
            echo -n " ${SCORE}" >> $2
        done
        echo "" >> $2
    done
    sort -n -k 2 ${2} -o ${2}
}

# Extract length-specific performance (all algos)
for LENGTH in ${LENGTHS}; do
    OUTPUT=${DIRECTORY}/${LENGTH}.dat
    length_performance ${LENGTH} ${OUTPUT} "${ALGOS}"
done

# Plot length-specific performance (all algos, fast only)
for LENGTH in ${LENGTHS}; do
    FULL_INPUT=${DIRECTORY}/${LENGTH}.dat
    TOP=30
    INPUT=${DIRECTORY}/${LENGTH}-fastest.dat
    cat ${FULL_INPUT} | head -n ${TOP} > ${INPUT}
    PNG=${DIRECTORY}/${LENGTH}.png
    OPTS=""
    COUNTER=1
    for BUFFER in ${BUFFERS}; do
        ((COUNTER++))
        OPTS+="-name ${BUFFER} -using (5*column(0)):${COUNTER}:xtic(1) ${INPUT} "
    done
    gplot.pl -outfile ${PNG} -type png -title "Hash of ${LENGTH} Byte Slice (Fastest ${TOP})" -xlabel "" -ylabel "ns/hash (log scale)" -set "logscale y; set xtics nomirror rotate by -270; set key top left" -pointsize 1 -style points ${OPTS}
done

# Extract length-specific performance by hash family
for LENGTH in ${LENGTHS}; do
    for HASH in ${HASHES}; do
        OUTPUT=${DIRECTORY}/${LENGTH}-${HASH}.dat
        INCLUDE=$(echo "${ALGOS}" | tr ' ' '\n' | grep "^${HASH}-" | tr '\n' ' ')
        length_performance ${LENGTH} ${OUTPUT} "${INCLUDE}"
    done
done

# Plot length-specific performance by hash family
for LENGTH in ${LENGTHS}; do
    for HASH in ${HASHES}; do
        INPUT=${DIRECTORY}/${LENGTH}-${HASH}.dat
        PNG=${DIRECTORY}/${LENGTH}-${HASH}.png
        OPTS=""
        COUNTER=1
        for BUFFER in ${BUFFERS}; do
            ((COUNTER++))
            OPTS+="-name ${BUFFER} -using (5*column(0)):${COUNTER}:xtic(1) ${INPUT} "
        done
        gplot.pl -outfile ${PNG} -type png -title "${HASH} of ${LENGTH} Byte Slice" -xlabel "" -ylabel "ns/hash" -set "xtics nomirror rotate by -270; set key top left" -pointsize 1 -style points ${OPTS}
    done
done

md_table() {
    # table heading row
    echo -n "| $1 | " >> ${INDEX}
    for BUFFER in ${BUFFERS}; do
        echo -n " ${BUFFER} |" >> ${INDEX}
    done
    echo "" >> ${INDEX}
    # table heading separator row
    echo -n "| --- | " >> ${INDEX}
    for BUFFER in ${BUFFERS}; do
        echo -n "---: | " >> ${INDEX}
    done
    echo "" >> ${INDEX}
}

# Summary page
INDEX=${DIRECTORY}/README.md
echo "# Hash-Bench Results" >> ${INDEX}
echo "## Contents" >> ${INDEX}
echo "### Latency by Byte Slice Length" >> ${INDEX}
# table heading row
echo -n "| Hash | " >> ${INDEX}
for LENGTH in ${LENGTHS}; do
    echo -n "${LENGTH} |" >> ${INDEX}
done
echo "" >> ${INDEX}
# table heading separator row
echo -n "| --- | " >> ${INDEX}
for LENGTH in ${LENGTHS}; do
    echo -n ":---: | " >> ${INDEX}
done
echo "" >> ${INDEX}
# table data rows
echo -n "| All | " >> ${INDEX}
for LENGTH in ${LENGTHS}; do
    echo -n "[*](#${LENGTH}-byte-slice-latency-all-hashes) | " >> ${INDEX}
done
echo "" >> ${INDEX}
for HASH in ${HASHES}; do
    echo -n "| ${HASH} | " >> ${INDEX}
    for LENGTH in ${LENGTHS}; do
        echo -n "[*](#${LENGTH}-byte-slice-latency-${HASH}) | " >> ${INDEX}
    done
    echo "" >> ${INDEX}
done
echo "### Latency by Algorithm" >> ${INDEX}
for ALGO in ${ALGOS}; do
    echo " * [${ALGO}](#${ALGO}-latency)" >> ${INDEX}
done
echo "" >> ${INDEX}
echo "---" >> ${INDEX}

latency_by_length() {
    # inputFile
    SORTED_ALGOS=$(grep -v '#' $1 | cut -f 1 -d ' ')
    for ALGO in $SORTED_ALGOS; do
        echo -n "| [${ALGO}](#${ALGO}-latency)" >> ${INDEX}
        for BUFFER in ${BUFFERS}; do
            SCORE=$(grep ".*${BUFFER}.*${ALGO},${LENGTH}$" ${FILE} | cut -d ',' -f 5)
            echo -n " | ${SCORE}" >> ${INDEX}
        done
        echo " |" >> ${INDEX}
    done
    echo "" >> ${INDEX}
    echo "---" >> ${INDEX}
}

# Summary page latency by byte slice
for LENGTH in ${LENGTHS}; do
    ## all hashes
    echo "### ${LENGTH} Byte Slice Latency (All Hashes)" >> ${INDEX}
    echo "![plot](${LENGTH}.png)" >> ${INDEX}
    echo "" >> ${INDEX}
    md_table "Algorithm"
    latency_by_length ${DIRECTORY}/${LENGTH}.dat

    ## by hash
    for HASH in ${HASHES}; do
        echo "### ${LENGTH} Byte Slice Latency (${HASH})" >> ${INDEX}
        echo "![plot](${LENGTH}-${HASH}.png)" >> ${INDEX}
        echo "" >> ${INDEX}
        md_table "Algorithm"
        latency_by_length ${DIRECTORY}/${LENGTH}-${HASH}.dat
    done
done

# Summary page latency by algorithm
for ALGO in ${ALGOS}; do
    echo "### ${ALGO} Latency" >> ${INDEX}
    echo "![plot](${ALGO}.png)" >> ${INDEX}
    echo "" >> ${INDEX}
    md_table "Length"
    for LENGTH in ${LENGTHS}; do
        echo -n "| [${LENGTH}](#${LENGTH}-byte-slice-latency-all-hashes)" >> ${INDEX}
        for BUFFER in ${BUFFERS}; do
            SCORE=$(grep ".*${BUFFER}.*${ALGO},${LENGTH}$" ${FILE} | cut -d ',' -f 5)
            echo -n " | ${SCORE}" >> ${INDEX}
        done
        echo " |" >> ${INDEX}
    done
    echo "" >> ${INDEX}
    echo "---" >> ${INDEX}
done

rm ${DIRECTORY}/*.dat

echo "Generated from [JMH CSV](${FILE}) on $(date -Ru) by [Hash-Bench](https://github.com/benalexau/hash-bench)." >> ${INDEX}
