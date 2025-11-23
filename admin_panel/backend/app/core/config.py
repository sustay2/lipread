from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    FIREBASE_PROJECT_ID: str
    FIREBASE_CLIENT_EMAIL: str
    FIREBASE_PRIVATE_KEY: str
    MEDIA_ROOT: str = "C:/lipread_media"
    MEDIA_BASE_URL: str = "http://localhost:8000/media"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

settings = Settings()
