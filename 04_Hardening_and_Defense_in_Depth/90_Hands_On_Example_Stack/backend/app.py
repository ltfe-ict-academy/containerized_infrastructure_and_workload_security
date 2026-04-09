import json
import logging
import os
import time
from functools import wraps

import psycopg
import redis
from flask import Flask, Response, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from psycopg.rows import dict_row


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "time": self.formatTime(record, self.datefmt),
        }
        return json.dumps(payload)


handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
LOGGER = logging.getLogger("course-backend")
LOGGER.setLevel(logging.INFO)
LOGGER.handlers = [handler]
LOGGER.propagate = False

app = Flask(__name__)

REQUESTS = Counter(
    "app_requests_total",
    "Total HTTP requests handled by the backend",
    ["method", "endpoint", "status"],
)
ERRORS = Counter(
    "app_request_errors_total",
    "Total backend errors",
    ["endpoint"],
)
LATENCY = Histogram(
    "app_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
)


def read_value(name, default=None):
    file_path = os.getenv(f"{name}_FILE")
    if file_path and os.path.exists(file_path):
        with open(file_path, encoding="utf-8") as handle:
            return handle.read().strip()
    return os.getenv(name, default)


APP_DB_HOST = read_value("APP_DB_HOST", "db")
APP_DB_NAME = read_value("APP_DB_NAME", "courseapp")
APP_DB_USER = read_value("APP_DB_USER", "courseapp")
APP_DB_PASSWORD = read_value("APP_DB_PASSWORD", "courseapp")
REDIS_HOST = read_value("REDIS_HOST", "redis")
REDIS_PORT = int(read_value("REDIS_PORT", "6379"))
REDIS_PASSWORD = read_value("REDIS_PASSWORD", "")
ENABLE_DEBUG_ROUTES = read_value("ENABLE_DEBUG_ROUTES", "false").lower() == "true"
USE_SAFE_QUERIES = read_value("USE_SAFE_QUERIES", "true").lower() == "true"


def database_url():
    return (
        f"postgresql://{APP_DB_USER}:{APP_DB_PASSWORD}"
        f"@{APP_DB_HOST}:5432/{APP_DB_NAME}"
    )


def db_connection():
    return psycopg.connect(database_url(), row_factory=dict_row)


def redis_client():
    kwargs = {"host": REDIS_HOST, "port": REDIS_PORT, "decode_responses": True}
    if REDIS_PASSWORD:
        kwargs["password"] = REDIS_PASSWORD
    return redis.Redis(**kwargs)


def wait_for_services():
    for name, check in (("postgres", check_db), ("redis", check_redis)):
        for attempt in range(1, 31):
            try:
                check()
                LOGGER.info("%s is reachable", name)
                break
            except Exception as exc:  # noqa: BLE001
                LOGGER.info("waiting for %s (%s/30): %s", name, attempt, exc)
                time.sleep(2)
        else:
            raise RuntimeError(f"{name} did not become ready in time")


def check_db():
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")


def check_redis():
    redis_client().ping()


def instrument(endpoint_name):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start = time.perf_counter()
            status_code = 500
            try:
                response = func(*args, **kwargs)
                if isinstance(response, tuple):
                    status_code = response[1]
                elif hasattr(response, "status_code"):
                    status_code = response.status_code
                else:
                    status_code = 200
                return response
            except Exception:  # noqa: BLE001
                ERRORS.labels(endpoint=endpoint_name).inc()
                raise
            finally:
                LATENCY.labels(
                    method=request.method,
                    endpoint=endpoint_name,
                ).observe(time.perf_counter() - start)
                REQUESTS.labels(
                    method=request.method,
                    endpoint=endpoint_name,
                    status=str(status_code),
                ).inc()

        return wrapper

    return decorator


def load_products():
    cache = redis_client()
    cached = cache.get("products:all")
    if cached:
        return json.loads(cached), "redis"

    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, name, description, price::float8 AS price
                FROM products
                ORDER BY id
                """
            )
            rows = cur.fetchall()

    cache.setex("products:all", 60, json.dumps(rows))
    return rows, "postgres"


@app.after_request
def set_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    return response


@app.route("/api/health")
@instrument("health")
def health():
    db_ok = True
    redis_ok = True

    try:
        check_db()
    except Exception:  # noqa: BLE001
        db_ok = False

    try:
        check_redis()
    except Exception:  # noqa: BLE001
        redis_ok = False

    return jsonify(
        {
            "service": "course-backend",
            "status": "ok" if db_ok and redis_ok else "degraded",
            "database": db_ok,
            "redis": redis_ok,
            "debug_routes": ENABLE_DEBUG_ROUTES,
            "safe_queries": USE_SAFE_QUERIES,
        }
    )


@app.route("/api/products")
@instrument("products")
def products():
    rows, source = load_products()
    return jsonify({"source": source, "items": rows})


@app.route("/api/products/search")
@instrument("search")
def search_products():
    query = request.args.get("q", "").strip()

    with db_connection() as conn:
        with conn.cursor() as cur:
            if USE_SAFE_QUERIES:
                like = f"%{query}%"
                cur.execute(
                    """
                    SELECT id, name, description, price::float8 AS price
                    FROM products
                    WHERE name ILIKE %s
                       OR description ILIKE %s
                    ORDER BY id
                    """,
                    (like, like),
                )
                sql_mode = "parameterized"
            else:
                sql = f"""
                    SELECT id, name, description, price::float8 AS price
                    FROM products
                    WHERE name ILIKE '%{query}%'
                       OR description ILIKE '%{query}%'
                    ORDER BY id
                """
                cur.execute(sql)
                sql_mode = "unsafe-string-format"

            rows = cur.fetchall()

    return jsonify({"query": query, "query_mode": sql_mode, "items": rows})


@app.route("/api/cache/clear", methods=["POST"])
@instrument("cache_clear")
def clear_cache():
    redis_client().delete("products:all")
    return jsonify({"status": "cleared"})


@app.route("/api/admin/debug")
@instrument("debug")
def debug():
    if not ENABLE_DEBUG_ROUTES:
        return jsonify({"error": "debug routes disabled"}), 404

    return jsonify(
        {
            "process": {
                "uid": os.getuid() if hasattr(os, "getuid") else "n/a",
                "cwd": os.getcwd(),
            },
            "settings": {
                "APP_DB_HOST": APP_DB_HOST,
                "APP_DB_NAME": APP_DB_NAME,
                "APP_DB_USER": APP_DB_USER,
                "REDIS_HOST": REDIS_HOST,
                "REDIS_PORT": REDIS_PORT,
                "ENABLE_DEBUG_ROUTES": ENABLE_DEBUG_ROUTES,
                "USE_SAFE_QUERIES": USE_SAFE_QUERIES,
            },
        }
    )


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    wait_for_services()
    app.run(host="0.0.0.0", port=8000, debug=False)
