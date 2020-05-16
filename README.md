# api-test

A simple bash script to test JSON API from terminal in a structured and organized way.

## Setting up

### Requirements

- [curl](https://curl.haxx.se/download.html)
- [jq](https://stedolan.github.io/jq/download)

## Installing

```
curl https://raw.githubusercontent.com/subeshb1/api-test/master/api-test.sh
```

### Alternate Approach

Since it is a small bash file, you can copy the content in https://raw.githubusercontent.com/subeshb1/api-test/master/api-test.sh and paste in a file, make it executable and run it.

## Usage

```sh
$ api-test.sh -h

USAGE: api-test [-hv] [-f file_name] [CMD] [ARGS]

OPTIONS:
  -h (--help)       print this message
  -h (--help)       print this message
  -v (--verbose)    verbose logging
  -f (--file)       file to test

COMMANDS:
  run               Run test cases specified in the test file.
                    Example: 'api-test -f test.json run test_case_1 test_case_2', 'api-test -f test.json run all'
```

### Test file

The test file will contain test cases in json format.

Example:
`test.json`

```json
{
  "name": "My API test",
  "testCases": {
    "test_case_1": {
      "path": "/path_1",
      "method": "POST",
      "description": "Best POST api",
      "body": {
        "value": 1
      },
      "header": {
        "X-per": "1"
      }
    },
    "test_case_2": {
      "path": "/path_2",
      "method": "GET",
      "description": "Best GET api",
      "query": {
        "value": 1
      }
    },
    "test_case_3": {
      "path": "/path_1",
      "method": "DELETE",
      "description": "Best DELETE api",
      "body": {
        "value": 1
      }
    }
  },
  "url": "localhost:3000",
  "header": {
    "Authorization": "Bearer  <ACCESS_TOKEN>"
  }
}
```

The test cases are present in the `testCases` object. The main url for the api is store in `url` string. If the test cases share common headers add them in root `header` key.

### Running test case

```
api-test -f test.json run test_case_1 # running single test case
api-test -f test.json run test_case_1 test_case_2 # running multiple test case
api-test -f test.json run all # running all test case. WARNING: Don't name a test case `all`
```
