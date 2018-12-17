#!/bin/bash
# Packs logs and stores them in s3.

errchk() {
  if [ ! $1 == 0 ] ; then
    echo '*** ERROR ***' 1>&2
    echo $2 1>&2
    echo 'Exiting.' 1>&2
    exit 1
  fi
}

path=$(dirname $0)

if [ ! -e ${path}/../config.sh ] ; then
  echo Configuration file ${path}/../config.sh not found.
  exit 1
fi

. $path/../config.sh

# Load map id if not specified as parameter.
map_id="$1"
if [ -z ${map_id} ] ; then
    echo "usage $(basename $0) <map id>."
    exit 1
fi

dt=$(date +%Y-%m-%d_%H-%M-%S)
logfile="${tmp_dir}/${map_id}_log_${dt}.tgz"
if [ -e "${logfile}" ] ; then
    rm "${logfile}"
fi
tar czf "${logfile}" -C "${map_logs_dir}" .

echo "Uploading ${logfile}"
aws s3 --region "$region" cp "${logfile}" "s3://${bucket}/${bucket_logs_dir}/"
errchk $? "aws s3 cp call failed for s3://${bucket}/${bucket_logs_dir}/${map_id}_log_${dt}.tgz."

rm "${logfile}" 
