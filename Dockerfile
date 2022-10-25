ARG ARCH=$TARGETARCH

FROM golang:1.18.4-alpine3.16 as builder

RUN go env -w GONOSUMDB="github.com/Rookout/GoSDK"
RUN go env -w GOPROXY="https://proxy.golang.org,https://rookout.jfrog.io/artifactory/api/go/rookout-go,direct"

RUN apk add --no-cache gcc musl-dev build-base zlib-static

WORKDIR /app
ADD go.mod go.sum ./
RUN go mod download
ADD . .

# We get the full GoSDK package explicitly so it would register it in the go.sum
# We do it after getting all of the project's files so the go.mod and go.sum will not be overwritten with the stub package
RUN go get -d github.com/Rookout/GoSDK@v0.1.27

RUN go build -tags=alpine314,rookout_static -gcflags='all=-N -l'  -o /app/dist/argo-events ./cmd

####################################################################################################
# base
####################################################################################################
FROM alpine:3.16.2 as base
ARG ARCH
RUN apk update && apk upgrade && \
    apk add ca-certificates && \
    apk --no-cache add tzdata

ENV ARGO_VERSION=v3.4.1

RUN wget -q https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/argo-linux-${ARCH}.gz
RUN gunzip -f argo-linux-${ARCH}.gz
RUN chmod +x argo-linux-${ARCH}
RUN mv ./argo-linux-${ARCH} /usr/local/bin/argo
COPY --from=builder /app/dist/argo-events /bin/argo-events
RUN chmod +x /bin/argo-events

####################################################################################################
# argo-events
####################################################################################################
FROM scratch as argo-events
ARG ARCH
COPY --from=base /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=base /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=base /usr/local/bin/argo /usr/local/bin/argo
COPY --from=base /bin/argo-events /bin/argo-events
ENTRYPOINT [ "/bin/argo-events" ]
