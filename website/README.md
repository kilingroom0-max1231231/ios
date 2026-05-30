# Mase Telegram — Landing site

Маркетинговый лендинг для iOS-клиента Telegram. Стек: **Python Flask + Jinja2 + Tailwind CSS (CDN) + ванильный JS**.
Дизайн в стиле приложения: тёмная тема, Liquid Glass, анимированный фон, scroll-reveal и переключатель языка RU/EN.

## Возможности

- Адаптивный одностраничный лендинг (hero, возможности, превью интерфейса, установка, FAQ)
- Стеклянный (glassmorphism) UI с анимированными градиентными «блобами»
- Мобильное меню, аккордеон FAQ, появление блоков при скролле
- Переключение языка RU ⇄ EN на лету (сохраняется в `localStorage`)
- Отдельная страница политики конфиденциальности (`/privacy`)
- Эндпоинт проверки `/healthz`

## Структура

```
website/
├── app.py                 # Flask-приложение и контент (features, FAQ)
├── requirements.txt
├── templates/
│   ├── base.html          # общий каркас + Tailwind config
│   ├── index.html         # главная
│   ├── privacy.html       # политика конфиденциальности
│   └── partials/
│       ├── nav.html
│       ├── footer.html
│       └── icons.html
└── static/
    ├── css/styles.css     # кастомные анимации поверх Tailwind
    └── js/main.js         # меню, reveal, FAQ, i18n
```

## Запуск

```bash
cd website
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt
python app.py
```

Открой <http://127.0.0.1:5000>.

## Заметки

- Tailwind подключён через Play CDN — сборка не нужна, всё работает «из коробки».
  Для продакшена рекомендуется собрать Tailwind в статический CSS (Tailwind CLI) и убрать CDN-скрипт.
- Текст контента (возможности, FAQ) задаётся в `app.py`. Переводы EN для интерфейса — в `static/js/main.js` (словарь `EN`).
- Ссылка «Скачать IPA» — заглушка (`#`); подставь URL релиза на GitHub.
