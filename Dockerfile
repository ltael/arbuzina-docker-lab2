# 1. Базовый образ: облегчённый Python 3.11 на Debian
FROM python:3.11-slim

# 2. Метаданные образа
LABEL maintainer="arbuzina@lab.local"
LABEL version="1.0"

# 3. Рабочая директория внутри контейнера
WORKDIR /app

# 4. Сначала копируем только список зависимостей (для кеширования слоя)
COPY requirements.txt .

# 5. Устанавливаем зависимости
RUN pip install -r requirements.txt

# 6. Копируем код приложения
COPY app/ ./app/

# 7. Документируем порт, который слушает приложение
EXPOSE 5468

# 8. Запуск приложения на персональном порту
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "5468"]
