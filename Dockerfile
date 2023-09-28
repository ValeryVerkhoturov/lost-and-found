FROM node:18-alpine AS base

##### DEPENDENCIES

FROM base AS deps
RUN apk add --no-cache libc6-compat openssl1.1-compat
WORKDIR /app

# Install Prisma Client - remove if not using Prisma

COPY prisma ./prisma/

# Install dependencies based on the preferred package manager

COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

RUN \
 if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
 elif [ -f package-lock.json ]; then npm ci; \
 elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && pnpm i; \
 else echo "Lockfile not found." && exit 1; \
 fi

##### BUILDER

FROM base AS builder

ENV NODE_ENV production

ENV ANALYZE=false
ENV DISABLE_PWA=false

ARG NEXT_PUBLIC_CDN_ENDPOINT_URL
ENV NEXT_PUBLIC_CDN_ENDPOINT_URL=$NEXT_PUBLIC_CDN_ENDPOINT_URL
ARG NEXT_PUBLIC_S3_UPLOAD_RESOURCE_FORMATS
ENV NEXT_PUBLIC_S3_UPLOAD_RESOURCE_FORMATS=$NEXT_PUBLIC_S3_UPLOAD_RESOURCE_FORMATS
ARG NEXT_PUBLIC_NEXTAUTH_URL
ENV NEXT_PUBLIC_NEXTAUTH_URL=$NEXT_PUBLIC_NEXTAUTH_URL

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/prisma ./prisma
COPY . .

ENV NEXT_TELEMETRY_DISABLED 1

# Prisma telemetry disabled
ENV CHECKPOINT_DISABLE 1

RUN \
 if [ -f yarn.lock ]; then SKIP_ENV_VALIDATION=1 yarn build; \
 elif [ -f package-lock.json ]; then SKIP_ENV_VALIDATION=1 npm run build; \
 elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && SKIP_ENV_VALIDATION=1 pnpm run build; \
 else echo "Lockfile not found." && exit 1; \
 fi

##### RUNNER

FROM base AS runner
WORKDIR /app

RUN npm i -g prisma npm@latest

ENV NODE_ENV production

ENV NEXT_TELEMETRY_DISABLED 1

# Prisma telemetry disabled
ENV CHECKPOINT_DISABLE 1


COPY --from=builder /app/next.config.mjs ./
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/prisma ./prisma

RUN chmod -R 777 ./public/rss

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# TODO: Remove this line after fix
# https://github.com/vercel/next.js/issues/48077
# https://github.com/vercel/next.js/issues/48173
COPY --from=builder /app/node_modules/next/dist/compiled/jest-worker ./node_modules/next/dist/compiled/jest-worker

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT 3000

CMD ["npm", "run", "production"]
