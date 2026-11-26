FROM mcr.microsoft.com/playwright:v1.65.1-noble

WORKDIR /opt/web-qa
COPY package.json package-lock.json ./
RUN npm ci --omit=optional --ignore-scripts --no-audit --no-fund
COPY examples/ ./examples/
USER pwuser
CMD ["./node_modules/.bin/playwright", "run-server", "--port", "3000", "--host", "0.0.0.0", "--artifacts-dir", "/artifacts"]
