FROM node:22-alpine

# Install build dependencies for better-sqlite3
RUN apk add --no-cache python3 make g++

WORKDIR /app

# Copy package files first for layer caching
COPY package*.json ./

# Install dependencies (rebuild native modules for Linux)
RUN npm ci --only=production

# Copy application files (node_modules excluded via .dockerignore)
COPY . .

# Create data directory for SQLite
RUN mkdir -p /data

EXPOSE 8080

CMD ["node", "server/index.js"]
