#!/bin/bash
set -o pipefail

VERSION='0.3.0'
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BOLD=$(tput bold)
UNDERLINE=$(tput smul)
RESET=$(tput sgr 0)

ACTION=""

FILE=""

VERBOSE=0

COMMAND_NAME="api-test"

ACCESS_TOKEN=""
ID_TOKEN=""
URL=""

SHOW_HEADER=0
SUPER_SILENT=0
HEADER_ONLY=0
SILENT=0
API_ERROR=0

# Helper methods
echo_v() {
  if [ $VERBOSE -eq 1 ]; then
    echo $1
  fi
}

echo_t() {
  printf "\t%s\n" "$1"
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
    echo "Run test cases specified in the test file."
    echo ""
    echo "USAGE: $COMMAND_NAME [-v] -f file_name run [-hiIs] [ARGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h (--help)           print this message"
    echo "  -i (--include)        include header"
    echo "  -I (--header-only)    header only"
    echo "  -s (--silent)         print response status and message only"
    echo "  -S (--super-silent)   print response only"
    echo ""
    echo "ARGS:"
    echo "  all                   Run all test case."
    echo "  <test_case_name>      Run provided test case."
    echo ""
    echo "EXAMPLE:"
    echo "'api-test -f test.json run test_case_1 test_case_2', 'api-test -f test.json run all'"
    exit
    ;;
  test)
    echo "Run automated tests for a test case."
    echo ""
    echo "USAGE: $COMMAND_NAME [-v] -f file_name test [ARGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h (--help)           print this message"
    echo ""
    echo "ARGS:"
    echo "  all                   Run all automated tests."
    echo "  <test_case_name>      Run provided automated test."
    echo ""
    echo "EXAMPLE:"
    echo "'api-test -f test.json test test_case_1 test_case_2', 'api-test -f test.json test all'"
    exit
    ;;
  describe)
    echo "List test cases or describe the contents in a test case."
    echo ""
    echo "USAGE: $COMMAND_NAME [-v] -f file_name describe [ARGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h (--help)                 print this message"
    echo ""
    echo "ARGS:"
    echo "  <empty>                     List all test case."
    echo "  <test_case_name>            Describe a test case."
    echo "  <test_case_name>  <path>    Describe a test case property using json path."
    echo ""
    echo "EXAMPLE:"
    echo "'api-test -f test.json describe', 'api-test -f test.json describe test_case_1', 'api-test -f test.json describe test_case_1 body' "
    exit
    ;;
  *)
    echo "A simple program to test JSON APIs."
    echo ""
    echo "USAGE: $COMMAND_NAME [-hv] -f file_name [CMD] [ARGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h (--help)       print this message"
    echo "  -v (--verbose)    verbose logging"
    echo "  -f (--file)       file to test"
    echo "  --version         print the version of the program"
    echo ""
    echo "COMMANDS:"
    echo "  run               Run test cases specified in the test file."
    echo "  test              Run automated test in the test file."
    echo "  describe          List test cases or describe the contents in a test case."
    echo ""
    echo "Run 'api-test COMMAND --help' for more information on a command."
    exit
    ;;
  esac
}

# api methods
call_api() {
  ROUTE=$(jq -r ".testCases.\"$1\".path" $FILE)
  BODY="$(jq -r ".testCases.\"$1\" | select(.body != null) | .body" $FILE)"
  QUERY_PARAMS=$(cat $FILE | jq -r ".testCases.\"$1\" | select(.query != null) | .query  | to_entries | map(\"\(.key)=\(.value|tostring)\") | join(\"&\") | \"?\" + . ")
  REQUEST_HEADER=$(cat $FILE | jq -r ".testCases.\"$1\" | .header | if  . != null then . else {} end   | to_entries | map(\"\(.key): \(.value|tostring)\") | join(\"\n\") | if ( . | length) != 0 then \"-H\" + .  else \"-H \" end")
  METHOD="$(jq -r ".testCases.\"$1\".method //\"GET\" | ascii_upcase" $FILE)"
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
           \"http_response\": \"${RESPONSE[@]:0}\" }" | jq -c -s add)
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
    echo "$RESPONSE_HEADER" | jq -C '.'
  else
    if [[ $SHOW_HEADER == 1 ]]; then
      echo "HEADER:"
      echo "$RESPONSE_HEADER" | jq -C '.'
    fi
    if [[ $SILENT == 0 ]]; then
      echo "BODY:"
      echo "$RESPONSE_BODY" | jq -C '.'
    fi

  fi
  if [[ $SUPER_SILENT == 0 ]]; then
    echo "META:"
    echo "$META" | jq -C '.'
  fi
}

api_factory() {
  for TEST_CASE in $@; do
    API_ERROR=0
    echo "${BOLD}Running Case:${RESET} $TEST_CASE"
    echo_v "${BOLD}Description: ${RESET}$(jq -r ".testCases.\"$TEST_CASE\".description" $FILE)"
    echo_v "${BOLD}Action: ${RESET}$(jq -r ".testCases.\"$TEST_CASE\".method //\"GET\" | ascii_upcase" $FILE) $(jq -r ".testCases.\"$TEST_CASE\".path" $FILE)"
    call_api $TEST_CASE
    display_results
    echo ""
    echo ""
  done
}

test_factory() {
  TOTAL_TEST_CASE=0
  TOTAL_FAIL_CASE=0
  ANY_API_ERROR=0
  for TEST_CASE in $@; do
    API_ERROR=0
    echo "${BOLD}Testing Case:${RESET} $TEST_CASE"
    echo_v "${BOLD}Description: ${RESET}$(jq -r ".testCases.\"$TEST_CASE\".description" $FILE)"
    echo_v "${BOLD}Action: ${RESET}$(jq -r ".testCases.\"$TEST_CASE\".method //\"GET\" | ascii_upcase" $FILE) $(jq -r ".testCases.\"$TEST_CASE\".path" $FILE)"
    if [[ -z $(jq -r ".testCases.\"$TEST_CASE\".expect? | select(. !=null)" $FILE) ]]; then
      tput cuf 2
      echo "No test cases found"
      echo ""
      echo ""
      continue
    fi
    call_api $TEST_CASE
    if [[ $API_ERROR == 1 ]]; then
      ANY_API_ERROR=1
      tput cuf 2
      echo -e "${BOLD}${RED}Error running tests after failed api request for '$TEST_CASE' ${RESET}"
      echo -e "\n"
      continue
    fi

    local TEST_SCENARIO=$(jq -r ".testCases.\"$TEST_CASE\".expect.header? | select(. !=null and . != {})" $FILE)
    if [[ ! -z $TEST_SCENARIO ]]; then
      tput cuf 2
      echo "${UNDERLINE}Checking condition for header${RESET}"
      test_runner $TEST_CASE "header" "$RESPONSE_HEADER"
      echo ""
      echo ""
    fi

    TEST_SCENARIO=$(jq -r ".testCases.\"$TEST_CASE\".expect.body? | select(. !=null and . != {})" $FILE)
    if [[ ! -z $TEST_SCENARIO ]]; then
      tput cuf 2
      echo "${UNDERLINE}Checking condition for body${RESET}"
      test_runner $TEST_CASE "body" "$RESPONSE_BODY"
      echo ""
      echo ""
    fi

    TEST_SCENARIO=$(jq -r ".testCases.\"$TEST_CASE\".expect.external? | select(. !=null and . != \"\")" $FILE)
    if [[ ! -z $TEST_SCENARIO ]]; then
      tput cuf 2
      echo "${UNDERLINE}Checking condition from external program${RESET}"
      external_script "$TEST_SCENARIO" "$TEST_CASE" "$RESPONSE_BODY" "$RESPONSE_HEADER"
      TOTAL_TEST_CASE=$((TOTAL_TEST_CASE + 1))
      echo ""
      echo ""
    fi

  done
  echo -e "${BOLD}Total tests:\t$TOTAL_TEST_CASE"
  if [[ $(($TOTAL_TEST_CASE - $TOTAL_FAIL_CASE)) != 0 ]]; then
    printf $GREEN
  fi
  echo -e "${BOLD}Total success:\t$(($TOTAL_TEST_CASE - $TOTAL_FAIL_CASE))${RESET}"

  if [[ $TOTAL_FAIL_CASE != 0 ]]; then
    printf $RED
  else
    if [[ $ANY_API_ERROR != 0 ]]; then
      echo -e "\n${BOLD}${RED}Some test cases failed to connect to the requested api.${RESET}"
      exit 1
    else
      echo -e "\n${BOLD}${GREEN}All tests ran successfully!${RESET}"
    fi
    exit 0
  fi
  echo -e "${BOLD}Total failure:\t$TOTAL_FAIL_CASE${RESET}"
  echo -e "\n${BOLD}${RED}Tests Failed!${RESET}"
  exit 1

}

test_runner() {
  for test in ""contains eq path_eq path_contains hasKey[]""; do
    local TEST_SCENARIO=$(jq -c -r ".testCases.\"$1\".expect.$2.$test? | select(. !=null)" $FILE)
    if [[ -z $TEST_SCENARIO ]]; then
      continue
    fi
    TOTAL_TEST_CASE=$((TOTAL_TEST_CASE + 1))
    tput cuf 4
    if [[ $test == "contains" ]]; then
      echo "Checking contains comparision${RESET}"
      contains "$TEST_SCENARIO" "$3"
    elif [[ $test == "eq" ]]; then
      echo "Checking equality comparision${RESET}"
      check_eq "$TEST_SCENARIO" "$3"
    elif [[ $test == "path_eq" ]]; then
      echo "Checking path equality comparision${RESET}"
      path_checker "$TEST_SCENARIO" "$3"
    elif [[ $test == "path_contains" ]]; then
      echo "Checking path contains comparision${RESET}"
      path_checker "$TEST_SCENARIO" "$3" 1
    else
      echo "Checking has key comparision${RESET}"
      has_key "$TEST_SCENARIO" "$3"
    fi
  done
}

external_script() {
  $1 "$2" "$3" "$4"
  local EXIT_CODE=$?
  if [[ $EXIT_CODE == 0 ]]; then
    tput cuf 4
    echo "${GREEN}${BOLD}Check Passed${RESET}"
  else
    tput cuf 4
    echo "${RED}${BOLD}Check Failed${RESET}"
    TOTAL_FAIL_CASE=$((TOTAL_FAIL_CASE + 1))
  fi
}

contains() {
  tput cuf 6
  local check=$(jq -c --argjson a "$1" --argjson b "$2" -n '$a | select(. != null) | $b | contains($a)')
  if [[ $check == "true" ]]; then
    echo "${GREEN}${BOLD}Check Passed${RESET}"
  else
    echo "${RED}${BOLD}Check Failed${RESET}"
    TOTAL_FAIL_CASE=$((TOTAL_FAIL_CASE + 1))
    echo "EXPECTED:"
    echo "${GREEN}$1${RESET}"
    echo "GOT:"
    echo "${RED}$2${RESET}"
    echo ""
  fi
}

has_key() {
  # local paths=$(jq -r 'def path2text($value):
  #   def tos: if type == "number" then . else "\"\(tojson)\"" end;
  #   reduce .[] as $segment ("";  .
  #     + ($segment
  #       | if type == "string" then "." + . else "[\(.)]" end));
  #   paths(scalars) as $p
  #     | getpath($p) as $v
  #     | $p | path2text($v)' <<<"$2")
  local paths=$(jq -r 'path(..)|[.[]|tostring]|join(".")' <<<"$2")
  tput cuf 6
  for path in $1; do
    local FOUND=0
    for data_path in $paths; do
      if [[ "$path" == "$data_path" ]]; then
        FOUND=1
        break
      fi
    done
    if [[ $FOUND == 0 ]]; then
      echo "${RED}${BOLD}Check Failed${RESET}"
      TOTAL_FAIL_CASE=$((TOTAL_FAIL_CASE + 1))
      echo "CANNOT FIND KEY:"
      echo "${RED}$path${RESET}"
      echo ""
      return
    fi
  done
  echo "${GREEN}${BOLD}Check Passed${RESET}"
}

check_eq() {
  tput cuf 6
  local type=$(jq -r -c --argjson a "$1" -n '$a|type' 2>/dev/null)
  local check
  if [[ $type == "object" || $type == "array" ]]; then
    check=$(jq -c --argjson a "$1" --argjson b "$2" -n 'def post_recurse(f): def r: (f | select(. != null) | r), .; r; def post_recurse: post_recurse(.[]?); ($a | (post_recurse | arrays) |= sort) as $a | ($b | (post_recurse | arrays) |= sort) as $b | $a == $b')
  elif [[ $type == "number" || $type == "boolean" || $type == "null" || $type == "string" ]]; then
    check=$(jq -c --argjson a "$1" --argjson b "$2" -n '$a == $b')
  else
    if [[ $1 == $2 ]]; then
      check="true"
    else
      check="false"
    fi
  fi
  if [[ $check == "true" ]]; then
    echo "${GREEN}${BOLD}Check Passed${RESET}"
  else
    tput cuf 2
    echo "${RED}${BOLD}Check Failed${RESET}"
    TOTAL_FAIL_CASE=$((TOTAL_FAIL_CASE + 1))
    echo "EXPECTED:"
    echo "${GREEN}$1${RESET}"
    echo "GOT:"
    echo "${RED}$2${RESET}"
    echo ""
  fi
}

path_checker() {
  local keys=$(jq -c -r --argjson a "$1" -n '$a | keys[]')
  if [[ -z "$keys" ]]; then
    return
  fi
  for key in $keys; do
    tput cuf 6
    local value=$(jq -c -r --argjson a "$1" -n "\$a | .\"$key\"")
    echo "When path is '$key'"
    local compare_value=$(jq -c -r --argjson a "$2" -n "\$a | try .$key catch \"OBJECT_FETCH_ERROR_JQ_API_TEST\"" 2>/dev/null)
    if [[ -z "$compare_value" ]]; then
      tput cuf 8
      echo "${RED}${BOLD}Check Failed${RESET}"
      TOTAL_FAIL_CASE=$((TOTAL_FAIL_CASE + 1))
      tput cuf 2
      echo "INVALID PATH SYNTAX: ${RED}data[0]target_id${RESET}"
      return
    fi
    tput cuf 2
    if [[ $3 == 1 ]]; then
      contains "$value" "$compare_value"
    else
      check_eq "$value" "$compare_value"
    fi
  done
}

# run command
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
    -S | --super-silent)
      SILENT=1
      SUPER_SILENT=1
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
  '') usage run ;;
  *)
    api_factory $@
    ;;
  esac
}

# test command
test() {
  for arg in "$@"; do
    case $arg in
    -h | --help)
      usage test
      exit
      ;;
    esac
  done

  case $1 in
  all)
    test_factory "$(jq -r '.testCases | keys[]' $FILE)"
    ;;
  '')
    usage test
    ;;
  *)
    test_factory $@
    ;;
  esac
}

# describe command
describe() {
  for arg in "$@"; do
    case $arg in
    -h | --help)
      usage describe
      exit
      ;;
    esac
  done

  case $1 in
  '')
    echo -e "S.N.\tTest case"
    jq -r '.testCases |  keys[]' $FILE | awk '{print NR "\t" $0}'
    ;;
  *)
    jq -r ".testCases | .$1 | .$2?" $FILE
    ;;
  esac
}

# INIT COMMANDS AND CHECKS
for arg in "$@"; do
  case $arg in
  run | test | describe)
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
  --version)
    echo "api-test version $VERSION"
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

# Check for dependency programs
command -v curl >/dev/null 2>&1 || {
  echo >&2 "This program requires 'curl' to run. Please install 'curl'"
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo >&2 "This program requires 'jq' to run. Please install 'jq'"
  exit 1
}

if [ ! -f "$FILE" ]; then
  DEFAULT_FILE=("test.json api-test.json template.json")
  FOUND_FILE=0
  for default in $DEFAULT_FILE; do
    if [ -f "$default" ]; then
      FOUND_FILE=1
      FILE=$default
      break
    fi
  done
  if [[ $FOUND_FILE == 0 ]]; then
    echo "Please provide an existing file."
    exit 1
  fi
fi

jq empty $FILE

if [ $? -ne 0 ]; then
  exit 1
fi

# Check if url is present
URL=$(jq -r '.url | select( . != null)' $FILE)
if [[ -z $URL ]]; then
  echo "'url' is a required field in base object of a test file and must be a string."
  exit 1
fi

COMMON_HEADER=$(cat $FILE | jq -r -c ". | .header | if  . != null then . else {} end   | to_entries | map(\"\(.key): \(.value|tostring)\") | join(\"\n\") | if ( . | length) != 0 then \"-H\" + .  else \"-H \" end")
# Check if test cases is present
if [[ -z $(jq -r '.testCases | select(. != null and . != {})' $FILE) ]]; then
  echo "'testCases' is a required field in base object of a test file and must have atleast one test case."
  exit 1
fi

case $ACTION in
run)
  run $@
  ;;
test) test $@ ;;
describe) describe $@ ;;
*)
  usage
  ;;
esac
