FROM redis:8-bookworm

COPY redis.conf /usr/local/etc/redis/redis.conf
COPY docker-entrypoint.sh /usr/local/bin/course-redis-entrypoint.sh

RUN chmod +x /usr/local/bin/course-redis-entrypoint.sh

CMD ["course-redis-entrypoint.sh"]
