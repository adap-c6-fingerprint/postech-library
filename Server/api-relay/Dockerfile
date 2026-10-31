FROM node:22-alpine@sha256:c610fcdfb1d5b4740dd70c284ed3cb16bb857e0f7166196e36a5501df7a3aa32
WORKDIR /app
COPY --chown=node:node package.json relay.mjs server.mjs daily-budget.mjs ./
USER node
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "server.mjs"]
