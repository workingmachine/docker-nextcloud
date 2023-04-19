#!/usr/bin/env bash
set -eu

response="some response"
cnt=0
hostname=$(hostname)
req_path="/index.php/apps/richdocuments/ajax/admin.php"
url="http://${hostname}/custom_apps/richdocumentscode/proxy.php?req=${req_path}"

sleep 3
while [[ (${cnt} < 10) && -n "${response}" ]]; do
  response=$(curl \
           --silent \
           --show-error \
           "${url}")
  sleep 1
  ((cnt+=1))
done

printf "%s\n" "${0##*/}: $(date +"%F %T,%3N") cnt: ${cnt}"

exit 0
