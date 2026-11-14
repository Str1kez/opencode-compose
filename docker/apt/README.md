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

После изменений пересобери образ: `docker compose up -d --build`.
