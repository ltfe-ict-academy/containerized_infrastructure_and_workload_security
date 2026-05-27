import json
import logging
import os
import time
from contextlib import asynccontextmanager
from decimal import Decimal
from urllib.parse import quote

import redis
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import Numeric, Text, create_engine, literal, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOGGER = logging.getLogger("course-backend")

DB_HOST = os.getenv("DB_HOST", "db")
DB_PORT = os.getenv("DB_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB", os.getenv("DB_NAME", "courseapp"))
POSTGRES_USER = os.getenv("POSTGRES_USER", "courseapp")
POSTGRES_PASSWORD_FILE = os.getenv("POSTGRES_PASSWORD_FILE", "/run/secrets/postgres_password")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
REDIS_DB = os.getenv("REDIS_DB", "0")
REDIS_PASSWORD_FILE = os.getenv("REDIS_PASSWORD_FILE", "/run/secrets/redis_password")

ENABLE_DEBUG_ROUTES = os.getenv("ENABLE_DEBUG_ROUTES", "false").lower() == "true"


def read_secret_file(path: str, *, fallback: str | None = None, required: bool = True) -> str:
    """Read a runtime secret from a mounted file without logging its value."""
    try:
        with open(path, "r", encoding="utf-8") as secret_file:
            value = secret_file.read().strip()
    except FileNotFoundError:
        if fallback is not None:
            return fallback
        if required:
            raise RuntimeError(f"required secret file is missing: {path}") from None
        return ""

    if not value and required:
        raise RuntimeError(f"required secret file is empty: {path}")
    return value


def url_quote(value: str) -> str:
    return quote(value, safe="")


def build_database_url() -> str:
    explicit_url = os.getenv("DATABASE_URL")
    if explicit_url:
        return explicit_url

    password = read_secret_file(
        POSTGRES_PASSWORD_FILE,
        fallback=os.getenv("POSTGRES_PASSWORD"),
        required=True,
    )
    return (
        f"postgresql://{url_quote(POSTGRES_USER)}:{url_quote(password)}"
        f"@{DB_HOST}:{DB_PORT}/{url_quote(POSTGRES_DB)}"
    )


def build_redis_url() -> str:
    explicit_url = os.getenv("REDIS_URL")
    if explicit_url:
        return explicit_url

    password = read_secret_file(
        REDIS_PASSWORD_FILE,
        fallback=os.getenv("REDIS_PASSWORD"),
        required=False,
    )
    credentials = f":{url_quote(password)}@" if password else ""
    return f"redis://{credentials}{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}"


DATABASE_URL = build_database_url()
REDIS_URL = build_redis_url()


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


class AppUser(Base):
    __tablename__ = "app_users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str] = mapped_column(Text, nullable=False)


_SEED_PRODUCTS = [
    {"name": "Red Mug", "description": "Ceramic coffee mug used by the frontend demo.", "price": Decimal("12.50")},
    {"name": "Blue Hoodie", "description": "Lightweight hoodie for conference labs.", "price": Decimal("39.00")},
    {"name": "Sticker Pack", "description": "Security-themed stickers for laptops.", "price": Decimal("7.00")},
    {"name": "Notebook", "description": "Paper notebook for architecture sketches.", "price": Decimal("9.50")},
]

_SEED_USERS = [
    {
        "username": "admin",
        "password_hash": "$2b$12$trainingonlyplaceholderhashforadminuser0000000000",
        "role": "admin",
    },
    {
        "username": "analyst",
        "password_hash": "$2b$12$trainingonlyplaceholderhashforanalyst000000000",
        "role": "analyst",
    },
]


def init_db():
    Base.metadata.create_all(engine)
    with SessionLocal() as session:
        session.execute(pg_insert(Product).values(_SEED_PRODUCTS).on_conflict_do_nothing())
        session.execute(
            pg_insert(AppUser).values(_SEED_USERS).on_conflict_do_nothing(index_elements=["username"])
        )
        session.commit()
    LOGGER.info("database schema and seed data initialised")


@asynccontextmanager
async def lifespan(app: FastAPI):
    wait_for_services()
    init_db()
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

    healthy = db_ok and redis_ok
    payload = {
        "service": "course-backend",
        "status": "ok" if healthy else "degraded",
        "database": db_ok,
        "redis": redis_ok,
        "debug_routes": ENABLE_DEBUG_ROUTES,
    }
    return JSONResponse(status_code=200 if healthy else 503, content=payload)


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
        "configuration": {
            "database": {
                "host": DB_HOST,
                "port": DB_PORT,
                "name": POSTGRES_DB,
                "user": POSTGRES_USER,
                "password_source": POSTGRES_PASSWORD_FILE,
            },
            "redis": {
                "host": REDIS_HOST,
                "port": REDIS_PORT,
                "db": REDIS_DB,
                "password_source": REDIS_PASSWORD_FILE,
            },
            "debug_routes": ENABLE_DEBUG_ROUTES,
            "app_env": os.getenv("APP_ENV", "production"),
        },
        "process": {
            "uid": os.getuid() if hasattr(os, "getuid") else "n/a",
            "gid": os.getgid() if hasattr(os, "getgid") else "n/a",
            "cwd": os.getcwd(),
        },
    }


if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=False)
