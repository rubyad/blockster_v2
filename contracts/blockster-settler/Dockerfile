FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY dist/ ./dist/
COPY keypairs/ ./keypairs/

EXPOSE 3000

CMD ["node", "dist/src/index.js"]
