FROM node:alpine
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install

COPY . /app

EXPOSE 3000 4000 5000
ENV NODE_ENV=development
RUN npm run build
USER root
CMD ["node", "server.js"]
