# Build Stage
FROM golang:alpine AS build-stage

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG GIT_COMMIT
ARG VERSION
ARG BUILD_DATE

RUN CGO_ENABLED=0 go build -ldflags "-w -s \
  -X github.com/gregarendse/ci/version.GitCommit=${GIT_COMMIT} \
  -X github.com/gregarendse/ci/version.BuildDate=${BUILD_DATE}" \
  -o /ci .

# Final Stage
FROM scratch

COPY --from=build-stage /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build-stage /ci /ci

ENTRYPOINT ["/ci"]
