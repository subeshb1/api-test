# Changelog

## v0.3.2
- Fixed a bug for `path_eq` comparison where when a string value is compared by a path, an error is thrown by jq. Error Link: https://github.com/subeshb1/api-test/issues/27. Special thanks to @badevos for the fix

## v0.3.2
- Fix script breaking on test cases starting with numbers Eg: `01_testcase, 02_testcase` and containing hyphen `-` Eg: `test-case`

## v0.3.1
- Fixed null body being sent when no body content was provided.
- Fixed typo in external script test message.

## v0.3.0

- External script injection for testing.

## v0.2.0

- Support for Automated testing.

## v0.1.0

- Added automated api calling feature.
