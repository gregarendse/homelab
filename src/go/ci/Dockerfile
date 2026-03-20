# Build Stage
FROM lacion/alpine-golang-buildimage:1.13 AS build-stage

LABEL app="build-ci"
LABEL REPO="https://github.com/gregarendse/ci"

ENV PROJPATH=/go/src/github.com/gregarendse/ci

# Because of https://github.com/docker/docker/issues/14914
ENV PATH=$PATH:$GOROOT/bin:$GOPATH/bin

ADD . /go/src/github.com/gregarendse/ci
WORKDIR /go/src/github.com/gregarendse/ci

RUN make build-alpine

# Final Stage
FROM scratch

ARG GIT_COMMIT
ARG VERSION
LABEL REPO="https://github.com/gregarendse/ci"
LABEL GIT_COMMIT=$GIT_COMMIT
LABEL VERSION=$VERSION

# Because of https://github.com/docker/docker/issues/14914
ENV PATH=$PATH:/opt/ci/bin

WORKDIR /opt/ci/bin

COPY --from=build-stage /go/src/github.com/gregarendse/ci/bin/ci /opt/ci/bin/
RUN chmod +x /opt/ci/bin/ci

# Create appuser
RUN adduser -D -g '' ci
USER ci

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["/opt/ci/bin/ci"]
