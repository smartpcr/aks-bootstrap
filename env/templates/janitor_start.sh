#!/bin/sh

set -e

# Handle SIGTERM to gracefully exit, instead of letting kubernetes timeout and send SIGKILL.
trap "echo 'Exiting after receiving SIGTERM' ; exit 0" SIGTERM
trap "echo 'Exiting after receiving SIGINT' ; exit 0" SIGINT

LOGDIR="/geneva/geneva_logs"
LOGFILES="${LOGDIR}/mdsd.info ${LOGDIR}/mdsd.warn ${LOGDIR}/mdsd.err ${LOGDIR}/mdsd.qos"

# Truncate log files if they are > 100Mib
for file in ${LOGFILES} ; do
  echo "Checking size of file: ${file}"
  if [[ `stat -c "%s" "${file}"` -ge 100000000 ]] ; then
    echo "Truncating file ${file}..."
    truncate -s0 "${file}"
  fi
done

# Install logrotate
apk add logrotate

# Run it forever
while true ; do
  logrotate /janitor/logrotate_mdsd.conf
  sleep 600
done
