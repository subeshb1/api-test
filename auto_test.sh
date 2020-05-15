#!/bin/bash
set -o pipefail

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BOLD=$(tput bold)
RESET=$(tput sgr0)

ACTION=""

FILE=""

VERBOSE=0

COMMAND_NAME="auto_test"

ACCESS_TOKEN=""
ID_TOKEN=""
URL=""

echo_v() {
  if [ $VERBOSE -eq 1 ]; then
    echo $1
  fi
}

run() {
  cat $FILE | jq empty
  if [ $? -ne 0 ]; then
    exit
  fi
  URL=$(jq -r '.url' $FILE)
  ACCESS_TOKEN=$(jq -r '.accessToken' $FILE)
  ID_TOKEN=$(jq -r '.idToken' $FILE)

  case $1 in
  all)
    api_factory "$(jq -r '.testCases | keys[]' $FILE)"
    ;;
  *)
    api_factory $@
    ;;
  esac
}

api_factory() {
  for TEST_CASE in $@; do
    echo "${BOLD}Running Case:${RESET} $TEST_CASE"
    echo_v "${BOLD}Description: ${RESET}$(jq -r ".testCases.$TEST_CASE.description" $FILE)"
    echo_v
    ROUTE=$(jq -r ".testCases.$TEST_CASE.path" $FILE)
    BODY="$(jq -r ".testCases.$TEST_CASE.body" $FILE)"
    QUERY_PARAMS=$(cat $FILE | jq -r ".testCases.$TEST_CASE | select(.query != null) | .query  | to_entries | map(\"\(.key)=\(.value|tostring)\") | join(\"&\") | \"?\" + . ")
    METHOD="$(jq -r ".testCases.$TEST_CASE.method //\"GET\" | ascii_upcase" $FILE)"
    call_api
    echo ""
    echo ""
  done
}

call_api() {
  echo "$METHOD $URL$ROUTE$QUERY_PARAMS"
  local raw_output=$(curl -is --request $METHOD $URL$ROUTE$QUERY_PARAMS \
    --header "Authorization: Bearer $ACCESS_TOKEN : $ID_TOKEN" \
    --data "$BODY" -w '\n{ "ResponseTime": "%{time_total}s" }' || echo "AUTO_API_ERROR")
  if [[ $raw_output == *"AUTO_API_ERROR"* ]]; then
    echo "Problem connecting to $URL"
    return 1
  fi
  local header="$(awk -v bl=1 'bl{bl=0; h=($0 ~ /HTTP\//)} /^\r?$/{bl=1} {if(h)print $0 }' <<<"$raw_output")"
  local json=$(jq -c -R -r '. as $line | try fromjson' <<<"$raw_output")
  BODY=$(sed -n 1p <<<"$json")
  META=$(sed 1d <<<"$json")
  parse_header "$header"
  echo "HEADER:"
  echo "$HEADER" | jq -C
  echo "BODY:"
  echo "$BODY" | jq -C
  echo "META:"
  echo "$META" | jq -C
}

function parse_header() {
  local RESPONSE=($(echo "$header" | tr '\r' ' ' | sed -n 1p))
  local header=$(echo "$header" | sed '1d;$d' | sed 's/: /" : "/' | sed 's/^/"/' | tr '\r' ' ' | sed 's/ $/",/' | sed '1 s/^/{/' | sed '$ s/,$/}/' | jq)
  # echo "$HEADER"
  HEADER=$(echo "$header" "{ \"http_version\": \"${RESPONSE[0]}\", 
           \"http_status\": \"${RESPONSE[1]}\",
           \"http_message\": \"${RESPONSE[@]:2}\",
           \"http_response\": \"${RESPONSE[@]:0}\" }" | jq -s add)
}

# Show usage and exit
function usage() {
  echo "usage: $COMMAND_NAME [-hv] [-f file_name] [CMD] [ARGS]"
  echo "  -h (--help)       print this message"
  echo "  -v (--verbose)    verbose logging"
  echo "  -f (--file)       file to test"
  exit
}

for arg in "$@"; do
  case $arg in
  run | test)
    ACTION="$1"
    shift
    break
    ;;
  -f | --file)
    FILE="$2"
    shift
    ;;
  -h | --help)
    usage
    exit
    ;;
  -v | --verbose)
    VERBOSE=1
    shift
    ;;
  *)
    shift
    ;;
  esac
done

if [ ! -f "$FILE" ]; then
  echo "Please provide an existing file."
  exit 1
fi

case $ACTION in
run)
  run $@
  ;;
test) ;;
*)
  usage
  ;;
esac
