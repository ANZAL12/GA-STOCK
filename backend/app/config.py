from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Database
    database_url: str

    # JWT
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days (10080 minutes)
    refresh_token_expire_days: int = 30

    # App
    debug: bool = False

    # Tally Integration
    tally_host: str = "localhost"
    tally_port: int = 9000
    tally_hosts: str | None = None  # Comma-separated: "localhost:9000, 100.x.y.z:9000"
    tally_company_name: str | None = None
    tally_auto_sync: bool = True
    tally_sync_interval_minutes: int = 1
    tally_sync_interval_seconds: int = 10
    tally_agent_token: str = "ga-tally-secret-2026"


settings = Settings()
