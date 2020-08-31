FROM hayd/ubuntu-deno:1.3.1


WORKDIR /app

# Prefer not to run as root.
RUN apt-get -qq update \
  && apt-get install -y jq curl

USER deno
# Cache the dependencies as a layer (the following two steps are re-run only when deps.ts is modified).
# Ideally fetch deps.ts will download and compile _all_ external files used in main.ts.
COPY deps.ts .
RUN deno cache deps.ts

# These steps will be re-run upon each file change in your working directory:
ADD . .
# Compile the main app so that it doesn't need to be compiled each startup/entry.
RUN deno cache main.ts
RUN deno cache test.ts



CMD ["run","--allow-net", "--allow-env", "main.ts"]
