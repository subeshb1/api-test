import { exec } from "https://deno.land/x/exec/mod.ts";
import { expect } from "https://deno.land/x/expect/mod.ts";
async function run(testCase: string) {
  const cmd = Deno.run({
    cmd: [
      "./api-test.sh",
      "-f",
      "test.json",
      "run",
      testCase,
    ],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await cmd.output();
  cmd.close();
  const outStr = new TextDecoder().decode(output).replace(
    /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g,
    "",
  );
  return outStr;
}

Deno.test({
  name: "GET API",
  async fn() {
    const response = await run("get_api");
    expect(response.includes("Running Case: get_api")).toBeTruthy();
    expect(response.includes("200 OK")).toBeTruthy();
    expect(response.includes(
      `BODY:
{
  "id": "1",
  "author": "Robin Wieruch",
  "title": "The Road to React"
}`,
    )).toBeTruthy();
    expect(response.includes(
      `META:
{
  "ResponseTime":`,
    )).toBeTruthy();
  },
  sanitizeResources: false,
  sanitizeOps: false,
});

Deno.test({
  name: "POST API",
  async fn() {
    const response = await run("post_api");
    expect(response.includes("Running Case: post_api")).toBeTruthy();
    expect(response.includes("200 OK")).toBeTruthy();
    expect(response.includes(
      `BODY:
{
  "id": "5",
  "author": "Robin Wieruch",
  "title": "The Road to React"
}`,
    )).toBeTruthy();
    expect(response.includes(
      `META:
{
  "ResponseTime":`,
    )).toBeTruthy();
  },
  sanitizeResources: false,
  sanitizeOps: false,
});
