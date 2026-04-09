FROM nginx:1.29-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY app.js /usr/share/nginx/html/app.js
COPY styles.css /usr/share/nginx/html/styles.css

RUN mkdir -p /var/cache/nginx /var/run /tmp/nginx \
    && chown -R nginx:nginx /usr/share/nginx/html /etc/nginx/conf.d /var/cache/nginx /var/run /tmp/nginx

USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "pid /tmp/nginx.pid; daemon off;"]
