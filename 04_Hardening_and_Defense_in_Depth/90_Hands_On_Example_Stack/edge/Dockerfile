FROM nginx:1.29-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /var/cache/nginx /var/run /tmp/nginx /etc/nginx/certs \
    && chown -R nginx:nginx /etc/nginx/conf.d /var/cache/nginx /var/run /tmp/nginx /etc/nginx/certs

USER nginx

EXPOSE 8080
EXPOSE 8443

CMD ["nginx", "-g", "pid /tmp/nginx.pid; daemon off;"]
