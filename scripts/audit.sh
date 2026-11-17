#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"; ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
# TODO 1: проверьте, что значение параметра port отлично от 22
check "Порт SSH отличен от 22" "no" "$(sudo sshd -T | awk '/^port/{print $2}' | grep -qx 22 && echo yes || echo no)"
# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Лимит попыток аутентификации равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
# источник данных: sudo ufw status verbose | grep Default
check "Политика incoming равна deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}' | cut -d'(' -f1)"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна" "0" "$(sudo nginx -t > /dev/null 2>&1; echo $?)"
# TODO 4в: сертификат истекает не ранее чем через 30 дней
CERT_DAYS_LEFT=$(sudo openssl x509 -in /etc/ssl/certs/devops.crt -checkend 2592000 -noout > /dev/null 2>&1 && echo "0" || echo "1")
check "Сертификат истекает не ранее чем через 30 дней" "0" "$CERT_DAYS_LEFT"
# TODO 4г: нет файлов с правом записи для всех + права ключа 600
WRITABLE_FILES=$(sudo find /var/www/devops-site -perm -o+w 2>/dev/null | wc -l)
KEY_RIGHTS=$(sudo stat -c '%a' /etc/ssl/private/devops.key)
check "Нет файлов с o+w и права ключа 600" "0__600" "${WRITABLE_FILES}__${KEY_RIGHTS}"
echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер СУБД healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"
# Проверка в): порты 5000 и 5432 не прослушиваются ни на одном адресе, кроме 127.0.0.1
PORTS_5000=$(sudo ss -tln | awk '$4 ~ /:5000$/ {print $4}' | grep -v '^127\.0\.0\.1:5000$' | wc -l)
PORTS_5432=$(sudo ss -tln | awk '$4 ~ /:5432$/ {print $4}' | wc -l)
check "Порты 5000/5432 только на 127.0.0.1" "0__0" "${PORTS_5000}__${PORTS_5432}"
# Проверка г): права файла ~/app/.env равны 600
ENV_RIGHTS=$(stat -c '%a' /home/devops/app/.env 2>/dev/null)
check "Права файла ~/app/.env равны 600" "600" "$ENV_RIGHTS"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1