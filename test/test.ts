import { exec } from "https://deno.land/x/exec/mod.ts";
import { expect } from "https://deno.land/x/expect/mod.ts";
async function run(testCase: string) {
  const cmd = Deno.run({
    cmd: [
      "../api-test.sh",
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
  const outStr = new TextDecoder().decode(output).replace(/META:\n(.*\n){4}/, "").split("\n").filter((x) =>
    x !== ""
  ).map((x) =>
    x.replace(
      /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g,
      "",
    )
  );
  return outStr;
}

Deno.test({
  name: "Get APIs ",
  async fn() {
    let expected = `
Running Case: get_api
Response:
200 OK
BODY:
{
  "id": "1",
  "author": "Robin Wieruch",
  "title": "The Road to React"
}
`.split("\n").filter((x) => x !== "");
    const response = await run("get_api");
    expect(response.map((x, i) => expected[i] === x).filter(x => !x).length).toEqual(0);
  },
  sanitizeResources: false,
  sanitizeOps: false,
});
