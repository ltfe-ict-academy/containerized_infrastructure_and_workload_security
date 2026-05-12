import json
import logging
import os
import time

import psycopg
import redis
from flask import Flask, jsonify, request
from psycopg.rows import dict_row


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOGGER = logging.getLogger("course-backend")

app = Flask(__name__)

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://postgres:postgres@db:5432/courseapp"
)
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
ENABLE_DEBUG_ROUTES = os.getenv("ENABLE_DEBUG_ROUTES", "true").lower() == "true"


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


def db_connection():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


def redis_client():
    return redis.Redis.from_url(REDIS_URL, decode_responses=True)


def check_db():
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")


def check_redis():
    redis_client().ping()


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
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    return response


@app.route("/api/health")
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
        }
    )


@app.route("/api/products")
def products():
    rows, source = load_products()
    return jsonify({"source": source, "items": rows})


@app.route("/api/products/search")
def search_products():
    query = request.args.get("q", "").strip()

    sql = f"""
        SELECT id, name, description, price::float8 AS price
        FROM products
        WHERE name ILIKE '%{query}%'
           OR description ILIKE '%{query}%'
        ORDER BY id
    """

    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            rows = cur.fetchall()

    return jsonify({"query": query, "sql": sql, "items": rows})


@app.route("/api/cache/clear", methods=["POST"])
def clear_cache():
    redis_client().delete("products:all")
    return jsonify({"status": "cleared"})


@app.route("/api/admin/debug")
def debug():
    if not ENABLE_DEBUG_ROUTES:
        return jsonify({"error": "debug routes disabled"}), 404

    return jsonify(
        {
            "environment": {
                "DATABASE_URL": DATABASE_URL,
                "REDIS_URL": REDIS_URL,
                "ENABLE_DEBUG_ROUTES": ENABLE_DEBUG_ROUTES,
                "FLASK_ENV": os.getenv("FLASK_ENV", "development"),
            },
            "process": {
                "uid": os.getuid() if hasattr(os, "getuid") else "n/a",
                "cwd": os.getcwd(),
            },
        }
    )


if __name__ == "__main__":
    wait_for_services()
    app.run(host="0.0.0.0", port=8000, debug=True)
