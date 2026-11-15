# Корпоративные apt-источники

Сюда кладутся файлы для сети, где `deb.debian.org` закрыт и пакеты идут через внутреннее зеркало. Визард копирует их сюда из папки, которую ты укажешь, а руками их можно положить и самому. Всё, кроме этого README, в `.gitignore`: внутренние адреса и пароли в репозиторий не попадают.

- `*.sources` или `*.list` заменяют стандартные источники Debian целиком;
- `*.conf` ложатся в `/etc/apt/apt.conf.d/`: прокси, логин к зеркалу, `Acquire::https::CAInfo`;
- `*.crt` становятся доверенными сертификатами в образе.

Пример `corp.sources` для trixie:

```
Types: deb
URIs: https://nexus.example.corp/repository/debian
Suites: trixie trixie-updates
Components: main

Types: deb
URIs: https://nexus.example.corp/repository/debian-security
Suites: trixie-security
Components: main
```

Если зеркало на https с корпоративным сертификатом, положи рядом `corp-ca.crt` и `corp-ca.conf` со строкой `Acquire::https::CAInfo "/usr/local/share/ca-certificates/corp-ca.crt";`: при первом `apt-get update` пакета `ca-certificates` в образе ещё нет.

`*.conf` действуют только во время сборки и в образ не попадают: логин и прокси не должны жить в слое. Поэтому логин клади в `*.conf`, а не в адрес внутри `*.sources`: источники и сертификаты в образе остаются. Из-за этого `apt-get install` руками в запущенном контейнере до зеркала не достучится. Нужные пакеты добавляй через `EXTRA_APT_PACKAGES` в `.env` и пересобирай образ.

После изменений пересобери образ: `docker compose up -d --build`.
