from functools import lru_cache
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    api_base_url: str = "http://api:8000"
    firebase_project_id: str = "lipread"
    firebase_web_api_key: str = ""
    stripe_secret_key: str | None = None
    stripe_webhook_secret: str | None = None
    environment: str = "local"

    class Config:
        env_prefix = "LIPREAD_ADMIN_"
        env_file = ".env"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
