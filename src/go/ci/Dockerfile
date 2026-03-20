# Build Stage
FROM golang:1.21-alpine AS build-stage

LABEL app="build-ci"

WORKDIR /src
COPY . .

RUN go build -ldflags '-w -s' -o /ci .

# Final Stage
FROM alpine:3

ARG GIT_COMMIT
ARG VERSION
LABEL GIT_COMMIT=$GIT_COMMIT
LABEL VERSION=$VERSION

COPY --from=build-stage /ci /usr/local/bin/ci

RUN adduser -D -g '' ci
USER ci

ENTRYPOINT ["ci"]
