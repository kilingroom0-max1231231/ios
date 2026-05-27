Положи сюда собранные артефакты TDLib для iOS:

- `tdlib/include/td/telegram/td_json_client.h`
- `tdlib/lib/libtdjson.a` (или `libtdjson.dylib`, если используешь динамику)

Минимум для текущего `project.yml`:
- headers в `tdlib/include`
- library в `tdlib/lib`

Если библиотека не подключена, проект не слинкуется (`-ltdjson`).
