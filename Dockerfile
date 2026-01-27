FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
COPY prisma ./prisma
COPY prisma.config.ts ./
COPY tsconfig.json ./

RUN npm ci
RUN npx prisma generate

COPY src ./src

RUN npm run build

ENV NODE_ENV=production
ENV PRISMA_CLIENT_ENGINE_TYPE=library
EXPOSE 3000

CMD ["sh", "-c", "npx prisma migrate deploy && node dist/server.js"]
