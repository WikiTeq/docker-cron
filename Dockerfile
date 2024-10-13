FROM alpine:3.20.3

LABEL maintainers="pavel@wikiteq.com"
LABEL org.opencontainers.image.source=https://github.com/WikiTeq/docker-cron

# Install required tools
RUN apk add --no-cache jq curl docker-cli

# Latest releases available at https://github.com/aptible/supercronic/releases
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.32/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=7da26ce6ab48d75e97f7204554afe7c80779d4e0

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

COPY functions.sh /usr/local/bin/functions.sh
RUN chmod +x /usr/local/bin/functions.sh

# Copy the startup script into the container
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

# Copy the cron update script into the container
COPY update_cron.sh /usr/local/bin/update_cron.sh
RUN chmod +x /usr/local/bin/update_cron.sh

# Run the startup script at container startup
CMD ["/usr/local/bin/startup.sh"]
