# Практическая работа №2. Знакомство с экосистемой Docker

**Студент:** Арбузина Елена Романовна, ИСУ 465038
**Дисциплина:** Контейнеризация и оркестрация приложений
**Исходное приложение:** [FilBTi/assist-py](https://github.com/FilBTi/assist-py) — FastAPI-сервис «Personal Assistant»

## Персональные параметры

| Параметр | Значение |
|---|---|
| Номер ИСУ | 465038 |
| Персональный порт | 5468 (5430 + 38) |
| Персональный префикс | arbuzina |
| Секретный ключ | secret38arbuzina |

## Структура репозитория

```
.
├── app/
│   └── main.py              # код приложения (FastAPI)
├── requirements.txt         # зависимости Python
├── Dockerfile               # базовый Dockerfile (этап 1)
├── Dockerfile.optimized     # multi-stage + healthcheck (этапы 2 и 4)
├── .dockerignore            # исключения из контекста сборки (этап 3)
└── README.md
```

## Требования

- Linux (проверено на Ubuntu 24.04)
- Docker Engine 28+ (проверено на клиенте 29.1.3 и сервере 28.2.2)
- git, curl

## Воспроизведение

### 0. Клонирование

```bash
git clone https://github.com/ltael/arbuzina-docker-lab2.git
cd arbuzina-docker-lab2
```

### 1. Базовый образ

```bash
docker build -t arbuzina-assistant:v1 .

docker run -d \
  --name arbuzina-assistant-1 \
  -p 5468:5468 \
  -e APP_OWNER=arbuzina \
  -e APP_SECRET=secret38arbuzina \
  arbuzina-assistant:v1
```

Проверка:

```bash
curl http://localhost:5468/ ; echo
curl http://localhost:5468/me ; echo
curl -X POST http://localhost:5468/notes \
  -H "Content-Type: application/json" \
  -d '{"text": "ЛР2: сборка образа"}' ; echo
curl http://localhost:5468/notes ; echo
curl http://localhost:5468/secret/secret38arbuzina ; echo
```

Ожидаемый ответ последнего запроса: `{"flag":"LAB2_SUCCESS_ARBUZINA", ...}`.

Остановка перед следующими шагами (порт 5468 должен быть свободен):

```bash
docker stop arbuzina-assistant-1 && docker rm arbuzina-assistant-1
```

### 2. Оптимизированный образ (multi-stage)

```bash
docker build -t arbuzina-assistant:v2 -f Dockerfile.optimized .
docker images arbuzina-assistant --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```

### 3. Сборка с .dockerignore

```bash
docker build -t arbuzina-assistant:v3 .

# в v1 папка app/__pycache__ присутствует, в v3 — нет
docker run --rm arbuzina-assistant:v1 ls -la /app/app
docker run --rm arbuzina-assistant:v3 ls -la /app/app
```

### 4. Финальный образ с healthcheck

```bash
docker build -t arbuzina-assistant:final -f Dockerfile.optimized .

docker run -d \
  --name arbuzina-assistant-final \
  -p 5468:5468 \
  -e APP_OWNER=arbuzina \
  -e APP_SECRET=secret38arbuzina \
  arbuzina-assistant:final

sleep 10
docker ps --filter "name=arbuzina-assistant-final" --format "table {{.Names}}\t{{.Status}}"
```

Ожидаемый статус: `Up ... (healthy)`. Журнал проверок:

```bash
docker inspect --format '{{json .State.Health}}' arbuzina-assistant-final | python3 -m json.tool
```

### 5. Теги и итоговый артефакт

```bash
docker tag arbuzina-assistant:final arbuzina-assistant:1.0.0
docker tag arbuzina-assistant:final arbuzina-assistant:$(date +%Y%m%d)

echo "========================================" && \
echo "Сборка завершена: $(date '+%d.%m.%Y %H:%M:%S')" && \
echo "Студент: $(whoami)@$(hostname)" && \
echo "Образ: arbuzina-assistant" && \
echo "========================================" && \
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep arbuzina-assistant | awk '{print $1, $2, $3}'
```

### Очистка

```bash
docker stop arbuzina-assistant-final && docker rm arbuzina-assistant-final
docker rmi arbuzina-assistant:v1 arbuzina-assistant:v2 arbuzina-assistant:v3 \
  arbuzina-assistant:final arbuzina-assistant:1.0.0 arbuzina-assistant:$(date +%Y%m%d)
```

## Результаты

| Образ | Dockerfile | Размер | Особенности |
|---|---|---|---|
| v1 | Dockerfile | 188 MB | базовая сборка, кеш pip остаётся в слое |
| v2 | Dockerfile.optimized (этап 2) | 164 MB | multi-stage, `--no-cache-dir`, non-root |
| v3 | Dockerfile + .dockerignore | 188 MB | без `__pycache__` в образе |
| final / 1.0.0 / дата | Dockerfile.optimized (этап 4) | 178 MB | + curl и HEALTHCHECK, статус `healthy` |

Экономия v2 относительно v1: 24 MB (~13 %). Установка curl для healthcheck увеличила финальный образ на 14 MB.

## Найденные проблемы и их решения

1. **В `python:3.11-slim` нет curl**, поэтому HEALTHCHECK из задания всегда завершался бы ошибкой, и контейнер получал бы статус `unhealthy`. Решение: curl устанавливается в финальной стадии с `--no-install-recommends`, а кеш apt удаляется в том же слое `RUN`.
2. **Шаблон `__pycache__/` в `.dockerignore` не исключал `app/__pycache__`.** В `.dockerignore` шаблоны без `**/` применяются только к корню контекста сборки. Первая сборка v3 дала образ, идентичный v1 (тот же ID). Решение: добавлены рекурсивные шаблоны `**/__pycache__`, `**/*.pyc`, `**/*.pyo`.
3. **Команда из задания 5.2 с `awk '{print $1, $2, $7}'` не работает в Docker 29**: изменился формат вывода `docker images` (имя и тег объединены, колонка размера сместилась). Решение: используется явный формат `--format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"`.
4. **Порядок слоёв**: на этапе 2 `RUN useradd` стоял после `COPY app/` и пересобирался при каждом изменении кода. В финальной версии установка curl и создание пользователя перенесены выше копирования кода.
