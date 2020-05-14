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

  case $ACTION in
  all)
    run
    ;;
  *)
    api_factory $@
    ;;
  esac
}

api_factory() {
  for TEST_CASE in $@; do
    echo_v "${BOLD}Running Case:${RESET} $1"
    echo_v "${BOLD}Description: ${RESET}$(jq -r ".testCases.$TEST_CASE.description" $FILE)"
    echo_v
    ROUTE=$(jq -r ".testCases.$TEST_CASE.path" $FILE)
    BODY="$(jq -r ".testCases.$TEST_CASE.body" $FILE)"
    QUERY_PARAMS=$(cat $FILE | jq -r ".testCases.$TEST_CASE | select(.query != null) | .query  | to_entries | map(\"\(.key)=\(.value|tostring)\") | join(\"&\") | \"?\" + . ")
    call_api
  done
}

call_api() {
  curl -is --request POST $URL$ROUTE$QUERY_PARAMS \
    --header "Authorization: Bearer $ID_TOKEN:$ACCESS_TOKEN" \
    --data "$BODY" -w '\nTotal Time: %{time_total}s' | jq -C -R -r '. as $line | try fromjson catch $line'
  echo ""
  echo ""
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
