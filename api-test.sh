#!/bin/bash
set -o pipefail

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BOLD=$(tput bold)
RESET=$(tput sgr 0)

ACTION=""

FILE=""

VERBOSE=0

COMMAND_NAME="api-test"

ACCESS_TOKEN=""
ID_TOKEN=""
URL=""

SHOW_HEADER=0
HEADER_ONLY=0
SILENT=0
API_ERROR=0

# Helper methods
echo_v() {
  if [ $VERBOSE -eq 1 ]; then
    echo $1
  fi
}

bytes_to_human() {
  b=${1:-0}
  d=''
  s=0
  S=(Bytes {K,M,G,T,E,P,Y,Z}B)
  while ((b > 1024)); do
    d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
    b=$((b / 1024))
    let s++
  done
  echo "$b$d ${S[$s]}"
}

color_response() {
  case $1 in
  2[0-9][0-9]) echo $GREEN ;;
  [45][0-9][0-9]) echo $RED ;;
  *) ;;
  esac
}

# Show usage
function usage() {
  case $1 in
  run)
    echo "USAGE: $COMMAND_NAME [-v] -f file_name run [-hiIs] [ARGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h (--help)           print this message"
    echo "  -i (--include)        include header"
    echo "  -I (--header-only)    header only"
    echo "  -s (--silent)         silent mode"
    echo ""
    echo "ARGS:"
    echo "  all                   Run all test case."
    echo "  <test_case_name>      Run provided test case."
    echo ""
    echo "EXAMPLE:"
    echo "'api-test -f test.json run test_case_1 test_case_2', 'api-test -f test.json run all'"
    exit
    ;;
  *)
    echo "USAGE: $COMMAND_NAME [-hv] -f file_name [CMD] [ARGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h (--help)       print this message"
    echo "  -v (--verbose)    verbose logging"
    echo "  -f (--file)       file to test"
    echo ""
    echo "COMMANDS:"
    echo "  run               Run test cases specified in the test file."
    echo "                    Example: 'api-test -f test.json run test_case_1 test_case_2', 'api-test -f test.json run all'"
    exit
    ;;
  esac
}

# api methods
call_api() {
  ROUTE=$(jq -r ".testCases.$1.path" $FILE)
  BODY="$(jq -r ".testCases.$1.body" $FILE)"
  QUERY_PARAMS=$(cat $FILE | jq -r ".testCases.$1 | select(.query != null) | .query  | to_entries | map(\"\(.key)=\(.value|tostring)\") | join(\"&\") | \"?\" + . ")
  REQUEST_HEADER=$(cat $FILE | jq -r ".testCases.$1 | .header | if  . != null then . else {} end   | to_entries | map(\"\(.key): \(.value|tostring)\") | join(\"\n\") | if ( . | length) != 0 then \"-H\" + .  else \"-H \" end")
  METHOD="$(jq -r ".testCases.$1.method //\"GET\" | ascii_upcase" $FILE)"
  # curl -ivs --request $METHOD "$URL$ROUTE$QUERY_PARAMS" \
  #   --data "$BODY" \
  #   "$COMMON_HEADER" \
  #   "$REQUEST_HEADER" \
  #   -w '\n{ "ResponseTime": "%{time_total}s" }\n'
  local raw_output=$(curl -is --request $METHOD "$URL$ROUTE$QUERY_PARAMS" \
    --data "$BODY" \
    "$COMMON_HEADER" \
    "$REQUEST_HEADER" \
    -w '\n{ "ResponseTime": "%{time_total}s", "Size": %{size_download} }' || echo "AUTO_API_ERROR")

  if [[ $raw_output == *"AUTO_API_ERROR"* ]]; then
    echo "Problem connecting to $URL"
    API_ERROR=1
    return 1
  fi
  local header="$(awk -v bl=1 'bl{bl=0; h=($0 ~ /HTTP\//)} /^\r?$/{bl=1} {if(h)print $0 }' <<<"$raw_output")"
  local json=$(jq -c -R -r '. as $line | try fromjson' <<<"$raw_output")
  RESPONSE_BODY=$(sed -n 1p <<<"$json")
  META=$(sed 1d <<<"$json")
  META=$(jq -r ".Size = \"$(bytes_to_human $(jq -r '.Size' <<<"$META"))\"" <<<"$META")
  parse_header "$header"
}

parse_header() {
  local RESPONSE=($(echo "$header" | tr '\r' ' ' | sed -n 1p))
  local header=$(echo "$header" | sed '1d;$d' | sed 's/: /" : "/' | sed 's/^/"/' | tr '\r' ' ' | sed 's/ $/",/' | sed '1 s/^/{/' | sed '$ s/,$/}/')
  RESPONSE_HEADER=$(echo "$header" "{ \"http_version\": \"${RESPONSE[0]}\", 
           \"http_status\": \"${RESPONSE[1]}\",
           \"http_message\": \"${RESPONSE[@]:2}\",
           \"http_response\": \"${RESPONSE[@]:0}\" }" | jq -s add)
}

## run specific methods
display_results() {

  if [[ $API_ERROR == 1 ]]; then
    return
  fi

  local res=$(jq -r '.http_status + " " + .http_message ' <<<"$RESPONSE_HEADER")
  local status=$(jq -r '.http_status' <<<"$RESPONSE_HEADER")
  echo "Response:"
  echo "${BOLD}$(color_response $status)$res${RESET}"
  if [[ $HEADER_ONLY == 1 ]]; then
    echo "HEADER:"
    echo "$RESPONSE_HEADER" | jq -C
  else
    if [[ $SHOW_HEADER == 1 ]]; then
      echo "HEADER:"
      echo "$RESPONSE_HEADER" | jq -C
    fi
    if [[ $SILENT == 0 ]]; then
      echo "BODY:"
      echo "$RESPONSE_BODY" | jq -C
    fi

  fi
  echo "META:"
  echo "$META" | jq -C
}

api_factory() {
  for TEST_CASE in $@; do
    API_ERROR=0
    echo "${BOLD}Running Case:${RESET} $TEST_CASE"
    echo_v "${BOLD}Description: ${RESET}$(jq -r ".testCases.$TEST_CASE.description" $FILE)"
    echo_v "${BOLD}Action: ${RESET}$(jq -r ".testCases.$TEST_CASE.method //\"GET\" | ascii_upcase" $FILE) $(jq -r ".testCases.$TEST_CASE.path" $FILE)"
    call_api $TEST_CASE
    display_results
    echo ""
    echo ""
  done
}

test_factory() {
  for TEST_CASE in $@; do
    echo "${BOLD}Testing Case:${RESET} $TEST_CASE"
    echo_v "${BOLD}Description: ${RESET}$(jq -r ".testCases.$TEST_CASE.description" $FILE)"
    echo_v "${BOLD}Action: ${RESET}$(jq -r ".testCases.$TEST_CASE.method //\"GET\" | ascii_upcase" $FILE) $(jq -r ".testCases.$TEST_CASE.path" $FILE)"
    call_api $TEST_CASE

    echo ""
    echo ""
  done
}

run() {
  for arg in "$@"; do
    case $arg in
    -i | --include)
      SHOW_HEADER=1
      shift
      ;;
    -I | --header-only)
      HEADER_ONLY=1
      shift
      ;;
    -s | --silent)
      SILENT=1
      shift
      ;;
    -h | --help)
      usage run
      exit
      ;;
    esac
  done

  case $1 in
  all)
    api_factory "$(jq -r '.testCases | keys[]' $FILE)"
    ;;
  *)
    api_factory $@
    ;;
  esac
}

test() {
  for arg in "$@"; do
    case $arg in
    -i | --include)
      SHOW_HEADER=1
      shift
      ;;
    -I | --header-only)
      HEADER_ONLY=1
      shift
      ;;
    -s | --silent)
      SILENT=1
      shift
      ;;
    -h | --help)
      usage run
      exit
      ;;
    esac
  done

  case $1 in
  all)
    test_factory "$(jq -r '.testCases | keys[]' $FILE)"
    ;;
  *)
    test_factory $@
    ;;
  esac
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

cat $FILE | jq empty
if [ $? -ne 0 ]; then
  echo "Empty file"
  exit
fi
URL=$(jq -r '.url' $FILE)
ACCESS_TOKEN=$(jq -r '.accessToken' $FILE)
ID_TOKEN=$(jq -r '.idToken' $FILE)
COMMON_HEADER=$(cat $FILE | jq -r -c ". | .header | if  . != null then . else {} end   | to_entries | map(\"\(.key): \(.value|tostring)\") | join(\"\n\") | if ( . | length) != 0 then \"-H\" + .  else \"-H \" end")

case $ACTION in
run)
  run $@
  ;;
test) test $@ ;;
*)
  usage
  ;;
esac
