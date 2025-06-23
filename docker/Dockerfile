FROM alpine:latest
ARG HY2_VERSION=2.4.0
ARG TARGETARCH=amd64
RUN apk add --no-cache curl tar
RUN curl -L "https://github.com/apernet/hysteria/releases/download/v${HY2_VERSION}/hysteria-linux-${TARGETARCH}.tar.gz" | tar -xz \
    && mv "hysteria-linux-${TARGETARCH}" /usr/local/bin/hysteria \
    && chmod +x /usr/local/bin/hysteria
EXPOSE 443/udp
ENTRYPOINT ["hysteria"]
CMD ["server", "-c", "/etc/hysteria/config.yaml"]
