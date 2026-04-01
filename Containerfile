FROM alpine:latest

# Install git and git-daemon
RUN apk add --no-cache git git-daemon bash

# Set working directory for repos
WORKDIR /repos

# Copy entrypoint and hook scripts
COPY entrypoint.sh /entrypoint.sh
COPY enforce-safe-writes.sh /usr/local/bin/enforce-safe-writes.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/enforce-safe-writes.sh

# Expose git daemon port
EXPOSE 9418

# Run the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
