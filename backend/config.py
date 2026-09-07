import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev_secret_key_12345')
    DATABASE_TYPE = os.getenv('DATABASE_TYPE', 'sqlite').lower()

    if DATABASE_TYPE == 'mysql':
        user = os.getenv('MYSQL_USER', 'root')
        password = os.getenv('MYSQL_PASSWORD', '')
        host = os.getenv('MYSQL_HOST', 'localhost')
        port = os.getenv('MYSQL_PORT', '3306')
        db = os.getenv('MYSQL_DB', 'my_flask_db')
        # Using pymysql driver for MySQL in SQLAlchemy
        SQLALCHEMY_DATABASE_URI = f"mysql+pymysql://{user}:{password}@{host}:{port}/{db}"
    else:
        # Default to SQLite
        sqlite_db = os.getenv('SQLITE_DB_PATH', 'app_database.db')
        base_dir = os.path.abspath(os.path.dirname(__file__))
        db_path = os.path.join(base_dir, sqlite_db)
        SQLALCHEMY_DATABASE_URI = f"sqlite:///{db_path}"

    SQLALCHEMY_TRACK_MODIFICATIONS = False
