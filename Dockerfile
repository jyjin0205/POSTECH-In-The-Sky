# Install dependencies only when needed
FROM node:16-alpine AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install

# Rebuild the source code only when needed
FROM node:16-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx next build
COPY .env.production.local .env
# RUN npm run migrate:run

# Production image, copy all the files and run next
FROM node:16-alpine AS runner
WORKDIR /app

ENV NODE_ENV production

RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# You only need to copy next.config.js if you are NOT using the default configuration
# COPY --from=builder /app/next.config.js ./
COPY --from=builder /app/ecosystem.config.js ./ecosystem.config.js
COPY --from=builder /app/src/lib/ormconfig.cli.js ./src/lib/ormconfig.cli.js
# COPY --from=builder /app/package.json ./package.json
# COPY --from=builder /app/package-lock.json ./package-lock.json
COPY --from=builder /app/tsconfig.json ./tsconfig.json

## for migration ###
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/.env.production.local ./.env
COPY --from=builder /app/src/entity ./src/entity
COPY --from=builder /app/src/migration ./src/migration
COPY --from=builder /app/src/enums ./src/enums
COPY --from=builder /app/src/interfaces ./src/interfaces
RUN chown nextjs:nodejs ./src/migration
####################

# Automatically leverage output traces to reduce image size 
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static


RUN npm install -g pm2
USER nextjs

EXPOSE 3000

ENV PORT 3000

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry.
# ENV NEXT_TELEMETRY_DISABLED 1

CMD ["pm2-runtime", "start", "ecosystem.config.js", "--env", "production"]