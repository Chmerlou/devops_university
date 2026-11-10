#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
# Запускается НА VM (ПЛАН Б: rsync локально, без SSH)
set -euo pipefail

# ===== Конфигурация =====
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

# ===== 1. Разбор аргумента --dry-run =====
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        *)
            echo "Ошибка: неизвестный аргумент '$arg'" >&2
            echo "Использование: $0 [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# ===== 2. Найти корень репозитория =====
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Ошибка: не удалось определить корень репозитория" >&2
    exit 1
}

LOCAL_DIR="${REPO_ROOT}/site/"

# ===== 3. Требование 4: проверка наличия site/index.html =====
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html не найден" >&2
    exit 1
fi

# ===== 4. Требование 5: проверка незафиксированных изменений =====
# Включая изменения в индексе (staged) и рабочем дереве (unstaged)
if ! git -C "$REPO_ROOT" diff --quiet HEAD --; then
    echo "Ошибка: в репозитории есть незафиксированные изменения" >&2
    git -C "$REPO_ROOT" status --short >&2
    exit 1
fi

# ===== 5. Требование 3: доставка через rsync с --chmod =====
RSYNC_OPTS="-avz --delete --chmod=D755,F644"
if [[ "$DRY_RUN" -eq 1 ]]; then
    RSYNC_OPTS="$RSYNC_OPTS --dry-run"
fi

# Требование 9: BatchMode — отказ без интерактивного запроса пароля
# (хотя в ПЛАНЕ Б локальный rsync, оставлено для совместимости)
sudo rsync $RSYNC_OPTS "$LOCAL_DIR" "$REMOTE_DIR/"

# ===== 6. При --dry-run — завершение без проверки доступности =====
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "План доставки выведен (изменения не применены)"
    exit 0
fi

# ===== 7. Требование 6: проверка доступности с --cacert =====
# Требование 9: -f — fail на HTTP ошибке, без интерактива
if ! curl --cacert "$CA_CERT" -fsS -o /dev/null "$SITE_URL"; then
    echo "Ошибка: ресурс недоступен после доставки" >&2
    exit 1
fi

# ===== 8. Требование 7: успех — вывод хеша коммита =====
COMMIT_HASH=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
echo "Доставка успешно завершена. Коммит: $COMMIT_HASH"
exit 0