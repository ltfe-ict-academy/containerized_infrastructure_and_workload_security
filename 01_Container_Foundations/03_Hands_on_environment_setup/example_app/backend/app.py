import json
import logging
import os
import time
from contextlib import asynccontextmanager
from decimal import Decimal

import redis
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import Numeric, Text, create_engine, literal, or_, select
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOGGER = logging.getLogger("course-backend")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@db:5432/courseapp")
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
ENABLE_DEBUG_ROUTES = os.getenv("ENABLE_DEBUG_ROUTES", "true").lower() == "true"


def sqlalchemy_database_url(database_url: str) -> str:
    if database_url.startswith("postgresql://"):
        return database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    if database_url.startswith("postgres://"):
        return database_url.replace("postgres://", "postgresql+psycopg://", 1)
    return database_url


engine = create_engine(sqlalchemy_database_url(DATABASE_URL), pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)


@asynccontextmanager
async def lifespan(app: FastAPI):
    wait_for_services()
    yield


app = FastAPI(title="Course Backend", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_headers=["Content-Type"],
    allow_methods=["GET", "POST", "OPTIONS"],
)


def wait_for_services():
    for name, check in (("postgres", check_db), ("redis", check_redis)):
        print(name, check)
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


def redis_client():
    return redis.Redis.from_url(REDIS_URL, decode_responses=True)


def check_db():
    with SessionLocal() as session:
        session.execute(select(literal(1))).scalar_one()


def check_redis():
    redis_client().ping()


def product_to_dict(product: Product):
    return {
        "id": product.id,
        "name": product.name,
        "description": product.description,
        "price": float(product.price),
    }


def load_products():
    cache = redis_client()
    cached = cache.get("products:all")
    if cached:
        return json.loads(cached), "redis"

    with SessionLocal() as session:
        products = session.scalars(select(Product).order_by(Product.id)).all()
        rows = [product_to_dict(product) for product in products]

    cache.setex("products:all", 60, json.dumps(rows))
    return rows, "postgres"


@app.get("/api/health")
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

    return {
        "service": "course-backend",
        "status": "ok" if db_ok and redis_ok else "degraded",
        "database": db_ok,
        "redis": redis_ok,
        "debug_routes": ENABLE_DEBUG_ROUTES,
    }


@app.get("/api/products")
def products():
    rows, source = load_products()
    return {"source": source, "items": rows}


@app.get("/api/products/search")
def search_products(q: str = ""):
    query = q.strip()
    search_pattern = f"%{query}%"

    statement = (
        select(Product)
        .where(
            or_(
                Product.name.ilike(search_pattern),
                Product.description.ilike(search_pattern),
            )
        )
        .order_by(Product.id)
    )

    with SessionLocal() as session:
        products = session.scalars(statement).all()
        rows = [product_to_dict(product) for product in products]

    return {"query": query, "items": rows}


@app.post("/api/cache/clear")
def clear_cache():
    redis_client().delete("products:all")
    return {"status": "cleared"}


@app.get("/api/admin/debug")
def debug():
    if not ENABLE_DEBUG_ROUTES:
        return JSONResponse(
            status_code=404,
            content={"error": "debug routes disabled"},
        )

    return {
        "environment": {
            "DATABASE_URL": DATABASE_URL,
            "REDIS_URL": REDIS_URL,
            "ENABLE_DEBUG_ROUTES": ENABLE_DEBUG_ROUTES,
            "APP_ENV": os.getenv("APP_ENV", "development"),
        },
        "process": {
            "uid": os.getuid() if hasattr(os, "getuid") else "n/a",
            "cwd": os.getcwd(),
        },
    }


if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=True)
